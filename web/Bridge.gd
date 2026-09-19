extends Node

signal settings_imported(success,message,path)

var callback
var window
var active_map = {}
var active_map_path = ""
var menu_loaded = false
var active_mode = "lock"
var mode_sync_enabled = false
var last_spin = false
var last_score_payload = {}
var mobile_layout:bool = false
var mobile_touch:bool = false
var mobile_viewport:Vector2 = Vector2(1280,720)
var mobile_layout_accum:float = 0.0
var account_settings_loading:bool = false
var account_settings_saving:bool = false
var account_settings_save_pending:bool = false
var account_settings_ready:bool = false
var applying_account_settings:bool = false
var settings_account_user_id:String = ""
var settings_watch_accum:float = 0.0
var settings_sync_delay:float = -1.0
var last_settings_fingerprint:String = ""
var mobile_keyboard_control:Control = null
var mobile_keyboard_open:bool = false
var mobile_keyboard_pending_text:String = ""
var run_start_offset:float = 0.0

func _ready():
	if not OS.has_feature("HTML5"): return
	window = JavaScript.get_interface("window")
	callback = JavaScript.create_callback(self, "command")
	window.rhythiansCommand = callback
	if not Rhythian.is_connected("maps_updated", self, "_maps_updated"):
		Rhythian.connect("maps_updated", self, "_maps_updated")
	if not Rhythian.is_connected("auth_changed", self, "_auth_changed"):
		Rhythian.connect("auth_changed", self, "_auth_changed")
	if not Rhythian.is_connected("score_submitted", self, "_score_submitted"):
		Rhythian.connect("score_submitted", self, "_score_submitted")

func menu_ready():
	menu_loaded = true
	print("RHYTHIANS_MENU_READY")
	if mobile_layout:
		call_deferred("_reapply_mobile_layout")
	if window and window.rhythiansReady:
		window.rhythiansReady(JSON.print({
			"persistent": OS.is_userfs_persistent(),
			"spin": Rhythia.cam_unlock
		}))

func request_signin():
	if window:
		window.rhythiansRequestSignin()

func request_map_download(map:Dictionary):
	if window and window.rhythiansDownloadMap:
		var id=str(map.get("id",""))
		var file_name="rhythians-"+id+".sspm"
		window.rhythiansDownloadMap(JSON.print({"id":id,"fileName":file_name}))

func open_downloaded_map(map:Dictionary):
	if window and window.rhythiansOpenDownloadedMap:
		window.rhythiansOpenDownloadedMap(JSON.print({"id":str(map.get("id","")),"map":map}))

func request_settings_import():
	if window and window.rhythiansRequestSettingsImport:
		window.rhythiansRequestSettingsImport()

func persist_user_data():
	if not OS.has_feature("HTML5"):
		return
	if window and window.rhythiansPersistUserData:
		window.rhythiansPersistUserData()

func _settings_sync_status(state:String,message:String):
	if window and window.rhythiansSettingsSync:
		window.rhythiansSettingsSync(state,message)

func _read_local_settings() -> Dictionary:
	var file=File.new()
	if file.open(Globals.p("user://settings.json"),File.READ)!=OK:
		return {}
	var parsed=JSON.parse(file.get_as_text())
	file.close()
	if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:
		return {}
	return parsed.result

func _write_local_settings(data:Dictionary) -> bool:
	var file=File.new()
	if file.open(Globals.p("user://settings.json"),File.WRITE)!=OK:
		return false
	file.store_string(JSON.print(data,"\t"))
	file.flush()
	file.close()
	return true

func _settings_fingerprint(settings:Dictionary) -> String:
	return JSON.print(settings)

func save_and_sync_settings(show_status:bool=true):
	Rhythia.save_settings()
	var settings=_read_local_settings()
	if not settings.empty():
		last_settings_fingerprint=_settings_fingerprint(settings)
	persist_user_data()
	if Rhythian.logged_in:
		call_deferred("save_account_settings",show_status)

func _schedule_settings_sync(delay:float=0.9):
	settings_sync_delay=delay if settings_sync_delay<0 else min(settings_sync_delay,delay)

func _watch_settings(delta:float):
	if applying_account_settings or not account_settings_ready or not Rhythian.logged_in:
		return
	settings_watch_accum+=delta
	if settings_watch_accum>=0.75:
		settings_watch_accum=0.0
		Rhythia.save_settings()
		var settings=_read_local_settings()
		if not settings.empty():
			var fingerprint=_settings_fingerprint(settings)
			if last_settings_fingerprint=="":
				last_settings_fingerprint=fingerprint
			elif fingerprint!=last_settings_fingerprint:
				last_settings_fingerprint=fingerprint
				persist_user_data()
				_schedule_settings_sync()
	if settings_sync_delay>=0:
		settings_sync_delay-=delta
		if settings_sync_delay<=0:
			settings_sync_delay=-1
			call_deferred("save_account_settings",false)

func save_account_settings(show_status:bool=true):
	if applying_account_settings or not Rhythian.logged_in:
		return
	if not account_settings_ready:
		account_settings_save_pending=true
		return
	if account_settings_saving:
		account_settings_save_pending=true
		return
	var settings=_read_local_settings()
	if settings.empty():
		return
	var user_at_start=Rhythian.user_id
	account_settings_saving=true
	var res=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/rhythkit/settings",{"settings":settings},true,25.0),"completed")
	account_settings_saving=false
	if user_at_start!=Rhythian.user_id:
		account_settings_save_pending=false
		return
	var ok=bool(res.get("ok",false))
	var json=res.get("json",null)
	if ok and typeof(json)==TYPE_DICTIONARY and bool(json.get("ok",true)):
		last_settings_fingerprint=_settings_fingerprint(settings)
		if show_status:
			_settings_sync_status("saved","Settings saved to your Rhythians account.")
	else:
		last_settings_fingerprint=""
		_settings_sync_status("error",Rhythian._http_error_message(res,"account settings"))
	if account_settings_save_pending:
		account_settings_save_pending=false
		call_deferred("save_account_settings",show_status)

func load_account_settings():
	if account_settings_loading or not Rhythian.logged_in:
		return
	var user_at_start=Rhythian.user_id
	var allow_seed=settings_account_user_id=="" or settings_account_user_id==user_at_start
	account_settings_loading=true
	var res=yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/rhythkit/settings",null,true,25.0),"completed")
	account_settings_loading=false
	if user_at_start!=Rhythian.user_id:
		return
	if not bool(res.get("ok",false)):
		_settings_sync_status("error",Rhythian._http_error_message(res,"account settings"))
		return
	var json=res.get("json",null)
	if typeof(json)!=TYPE_DICTIONARY or not bool(json.get("ok",false)):
		_settings_sync_status("error","Rhythians returned an invalid settings response.")
		return
	var remote=json.get("settings",null)
	settings_account_user_id=user_at_start
	account_settings_ready=true
	if remote==null:
		if allow_seed:
			Rhythia.save_settings()
			var local_settings=_read_local_settings()
			if not local_settings.empty():
				last_settings_fingerprint=_settings_fingerprint(local_settings)
			persist_user_data()
			call_deferred("save_account_settings",true)
			_settings_sync_status("saving","Saving these settings to your Rhythians account for the first time.")
		else:
			var local_settings=_read_local_settings()
			if not local_settings.empty():
				last_settings_fingerprint=_settings_fingerprint(local_settings)
			_settings_sync_status("loaded","This Rhythians account does not have cloud settings yet. Your current device settings stay local until you change or save them.")
		return
	if typeof(remote)!=TYPE_DICTIONARY:
		_settings_sync_status("error","Your Rhythians account settings are invalid.")
		return
	applying_account_settings=true
	var wrote=_write_local_settings(remote)
	var load_result=-1
	if wrote:
		load_result=Rhythia.load_saved_settings()
	applying_account_settings=false
	if not wrote or load_result!=0:
		_settings_sync_status("error","Cloud settings were found but the client could not apply them.")
		return
	last_settings_fingerprint=_settings_fingerprint(remote)
	persist_user_data()
	_settings_sync_status("loaded","Settings loaded from your Rhythians account.")
	if menu_loaded:
		menu_loaded=false
		get_tree().call_deferred("change_scene","res://scenes/loaders/menuload.tscn")
	if account_settings_save_pending:
		account_settings_save_pending=false
		call_deferred("save_account_settings")

func command(args):
	if args.empty(): return
	var parsed = JSON.parse(str(args[0]))
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return
	var data = parsed.result
	match data.get("action", ""):
		"auth":
			var account = data.get("account", {})
			if typeof(account) != TYPE_DICTIONARY: return
			account_settings_ready=false
			account_settings_save_pending=false
			Rhythian.apply_browser_auth(account)
			if Rhythian.logged_in:
				call_deferred("load_account_settings")
			if window:
				window.rhythiansAccountApplied(JSON.print({
					"loggedIn": Rhythian.logged_in,
					"username": Rhythian.username
				}))
		"guest":
			Rhythian.logout()
			account_settings_ready=false
			account_settings_save_pending=false
			active_map.clear()
			active_map_path = ""
			if window:
				window.rhythiansAccountApplied(JSON.print({"loggedIn": false, "username": ""}))
		"spin":
			Rhythia.cam_unlock = bool(data.get("enabled", false))
			save_and_sync_settings()
		"save":
			save_and_sync_settings()
		"flush":
			if Rhythian.logged_in:
				Rhythian._flush_score_queue()
		"portal":
			save_and_sync_settings()
			active_map.clear()
			active_map_path = ""
			menu_loaded = false
			get_tree().paused = false
			get_tree().change_scene("res://scenes/loaders/menuload.tscn")
		"play":
			_play_web_map(data)
		"download-progress":
			Rhythian.browser_download_progress(str(data.get("id","")),int(data.get("received",0)),int(data.get("total",0)))
		"download-complete":
			Rhythian.browser_download_complete(str(data.get("id","")),bool(data.get("success",false)),str(data.get("fileName","")),str(data.get("message","")))
		"download-missing":
			var missing_id=str(data.get("id",""))
			Rhythian.forget_downloaded_map(missing_id)
			Rhythian.emit_signal("map_downloaded",missing_id,false,"The cached map file is missing. Download it again.")
		"materialize-progress":
			pass
		"mobile-layout":
			_apply_mobile_layout(data)
		"import":
			_import_sspm(data)
		"import-settings":
			_import_settings(data)
		"mobile-keyboard-text":
			_mobile_keyboard_text(str(data.get("text","")))
		"mobile-keyboard-done":
			_mobile_keyboard_done(str(data.get("text",mobile_keyboard_pending_text)))

func _play_web_map(data:Dictionary):
	if not menu_loaded: return
	var temp_path = str(data.get("path", ""))
	if not temp_path.begins_with("/tmp/rhythians-") or not temp_path.ends_with(".sspm"): return
	active_map = data.get("map", {})
	if typeof(active_map)!=TYPE_DICTIONARY:
		active_map={}
	var map_id=str(active_map.get("id",""))
	if map_id=="":
		if window: window.rhythiansError("This downloaded map has no Rhythians id.")
		return

	var dir=Directory.new()
	var target_dir=Globals.p(Rhythian.MAP_DIR)
	dir.make_dir_recursive(target_dir)
	var file_name="rhythians-"+map_id+".sspm"
	var target=target_dir.trim_suffix("/")+"/"+file_name
	if File.new().file_exists(target):
		dir.remove(target)
	if dir.copy(temp_path,target)!=OK:
		if window: window.rhythiansError("The downloaded SSPM could not be saved into the client map library.")
		return
	dir.remove(temp_path)

	Rhythian._registry_add(file_name,active_map)
	var song=Rhythian.get_song_for_map_id(map_id)
	if song == null:
		dir.remove(target)
		Rhythian.forget_downloaded_map(map_id)
		if window: window.rhythiansError("This SSPM downloaded, but Rhythia could not parse it.")
		return

	active_map_path = target
	Rhythian.register_runtime_song(song,active_map)
	active_mode = "spin" if Rhythia.cam_unlock else "lock"
	mode_sync_enabled = true
	last_spin = Rhythia.cam_unlock
	var map_list = get_tree().current_scene.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list != null and map_list.has_method("refresh_visible_list"):
		map_list.call_deferred("refresh_visible_list")
	Rhythia.select_song(song)
	var sidebar = get_tree().current_scene.get_node_or_null("Sidebar")
	if sidebar != null and sidebar.has_method("to_play"): sidebar.to_play()
	persist_user_data()
	if window: window.rhythiansSelected()

func _import_sspm(data:Dictionary):
	var path = str(data.get("path", ""))
	var original_name = str(data.get("name", "import.sspm")).get_file()
	if not path.begins_with("/tmp/rhythians-import-") or not path.ends_with(".sspm"):
		if window: window.rhythiansImported(original_name, false, "Invalid import path.")
		return
	if not original_name.to_lower().ends_with(".sspm"):
		original_name += ".sspm"
	var safe_name = ""
	for i in range(original_name.length()):
		var ch = original_name.substr(i, 1)
		if ch.is_valid_identifier() or ch in [" ", "-", "_", ".", "(", ")", "[", "]"]:
			safe_name += ch
	if safe_name == "" or safe_name == ".sspm":
		safe_name = "imported-" + str(OS.get_unix_time()) + ".sspm"
	var source = File.new()
	if source.open(path, File.READ) != OK:
		if window: window.rhythiansImported(safe_name, false, "Could not read the imported SSPM.")
		return
	var header = source.get_buffer(4)
	source.close()
	if header.size() != 4 or header[0] != 0x53 or header[1] != 0x53 or header[2] != 0x2b or header[3] != 0x6d:
		if window: window.rhythiansImported(safe_name, false, "The file is not a valid SSPM.")
		return
	var dir = Directory.new()
	var target_dir = Globals.p("user://maps/browser imports")
	dir.make_dir_recursive(target_dir)
	var target = target_dir.trim_suffix("/") + "/" + safe_name
	var suffix = 2
	while File.new().file_exists(target):
		target = target_dir.trim_suffix("/") + "/" + safe_name.get_basename() + "-" + str(suffix) + ".sspm"
		suffix += 1
	if dir.copy(path, target) != OK:
		if window: window.rhythiansImported(safe_name, false, "Could not save the SSPM in browser storage.")
		return
	dir.remove(path)
	call_deferred("_finish_sspm_import",target,safe_name)

func _finish_sspm_import(target:String,safe_name:String):
	var dir=Directory.new()
	var song = Rhythia.registry_song.add_sspm_map(target)
	if song == null:
		dir.remove(target)
		if window: window.rhythiansImported(safe_name, false, "The client could not load this SSPM.")
		return
	var map_list = get_tree().current_scene.get_node_or_null("Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list != null and map_list.has_method("refresh_visible_list"):
		map_list.call_deferred("refresh_visible_list")
	if Rhythian.logged_in:
		Rhythian.call_deferred("start_auto_link_unchecked")
	if window: window.rhythiansImported(target.get_file(), true, "")

func _import_settings(data:Dictionary):
	var path=str(data.get("path",""))
	var original_name=str(data.get("name","imported-settings.json")).get_file()
	if not path.begins_with("/tmp/rhythians-settings-") or not path.ends_with(".json"):
		_finish_settings_import(false,"Invalid settings import path.","")
		return
	var source=File.new()
	if source.open(path,File.READ)!=OK:
		_finish_settings_import(false,"Could not read the settings file.","")
		return
	var text=source.get_as_text()
	source.close()
	var parsed=JSON.parse(text)
	if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:
		_finish_settings_import(false,"That file is not a valid Rhythia settings JSON file.","")
		return
	var base=original_name
	if base.ends_with(".settings.json"):
		base=base.substr(0,base.length()-14)
	elif base.ends_with(".json"):
		base=base.substr(0,base.length()-5)
	var safe=""
	for i in range(base.length()):
		var ch=base.substr(i,1)
		if ch.is_valid_identifier() or ch in ["0","1","2","3","4","5","6","7","8","9"," ","-","_","(",")","[","]"]:
			safe+=ch
	safe=safe.strip_edges()
	if safe=="":
		safe="Imported "+str(OS.get_unix_time())
	var target_dir=Globals.p("user://")
	var target=target_dir+safe+".settings.json"
	var suffix=2
	while File.new().file_exists(target):
		target=target_dir+safe+" "+str(suffix)+".settings.json"
		suffix+=1
	var output=File.new()
	if output.open(target,File.WRITE)!=OK:
		_finish_settings_import(false,"Could not save the imported settings profile.","")
		return
	output.store_string(text)
	output.close()
	_finish_settings_import(true,"Imported "+target.get_file()+". Select it from the profile menu.",target)
	persist_user_data()

func _finish_settings_import(success:bool,message:String,path:String):
	emit_signal("settings_imported",success,message,path)
	if window and window.rhythiansSettingsImported:
		window.rhythiansSettingsImported(success,message)

func _selected_rhythian_map() -> Dictionary:
	var song = Rhythia.selected_song
	if song == null: return {}
	var saved=Rhythian.get_song_metadata(song)
	if saved.empty(): return {}
	var map_id = str(saved.get("id", ""))
	if map_id == "": return {}
	for map in Rhythian.maps_cache:
		if typeof(map) == TYPE_DICTIONARY and str(map.get("id", "")) == map_id:
			return map.duplicate()
	return saved.duplicate()

func begin_run():
	run_start_offset=Rhythia.start_offset
	var selected = _selected_rhythian_map()
	if not selected.empty():
		active_map = selected
		active_map_path = str(Rhythia.selected_song.filePath) if Rhythia.selected_song != null else ""
	elif Rhythia.selected_song == null or active_map_path == "" or str(Rhythia.selected_song.filePath) != active_map_path:
		active_map.clear()
		active_map_path = ""
	active_mode = "spin" if Rhythia.cam_unlock else "lock"
	last_spin = Rhythia.cam_unlock

func finished():
	if not window: return
	if abs(run_start_offset)>0.001 or abs(Rhythia.start_offset-run_start_offset)>0.001:
		active_map.clear()
		active_map_path=""
		return
	if Rhythia.song_end_type!=Globals.END_PASS or Rhythia.replaying or Rhythia.mod_nofail:
		active_map.clear()
		active_map_path=""
		return
	if Rhythia.replay!=null and Rhythia.replay.autoplayer:
		active_map.clear()
		active_map_path=""
		return
	var selected = _selected_rhythian_map()
	if not selected.empty():
		active_map = selected
		active_map_path = str(Rhythia.selected_song.filePath) if Rhythia.selected_song != null else ""
	elif Rhythia.selected_song == null or active_map_path == "" or str(Rhythia.selected_song.filePath) != active_map_path:
		active_map.clear()
		active_map_path = ""
		return
	if active_map.empty(): return
	var total = max(Rhythia.song_end_total_notes, 1)
	var mods = []
	for key in ["mod_mirror_x", "mod_mirror_y", "mod_extra_energy", "mod_no_regen", "mod_sudden_death", "mod_ghost", "mod_flashlight", "mod_nearsighted", "mod_hardrock", "mod_chaos"]:
		if Rhythia.get(key): mods.append(key)
	var payload={
		"challengeMapId": str(active_map.get("id", "")),
		"accuracy": float(Rhythia.song_end_hits) / total * 100.0,
		"misses": int(Rhythia.song_end_misses),
		"speed": float(Globals.speed_multi[Rhythia.mod_speed_level]),
		"cameraMode": active_mode,
		"modifiers": PoolStringArray(mods).join(","),
		"resultQualified": true,
		"gameVersion": "rhythians-web-3",
		"integrationVersion": "rhythians-web-3"
	}
	last_score_payload=payload.duplicate(true)
	Rhythian.submit_web_score(payload)
	active_map.clear()
	active_map_path = ""
func _auth_changed():
	if window:
		window.rhythiansAuthChanged(JSON.print({
			"loggedIn": Rhythian.logged_in,
			"username": Rhythian.username,
			"userId": Rhythian.user_id,
			"installationId": Rhythian.installation_id
		}))

func _maps_updated(success:bool, _message:String):
	if window and success:
		window.rhythiansCatalogReady(Rhythian.maps_total)

func _process(delta):
	_watch_settings(delta)
	if window and mode_sync_enabled and last_spin != Rhythia.cam_unlock:
		last_spin = Rhythia.cam_unlock
		window.rhythiansMode(last_spin)
	if mobile_layout:
		mobile_layout_accum += delta
		if mobile_layout_accum >= 0.75:
			mobile_layout_accum = 0.0
			_enhance_mobile_controls(get_tree().current_scene)


func _reapply_mobile_layout():
	if not mobile_layout:
		return
	_apply_mobile_layout({
		"width":mobile_viewport.x,
		"height":mobile_viewport.y,
		"touch":mobile_touch
	})

func _apply_mobile_layout(data:Dictionary):
	mobile_layout=true
	mobile_touch=bool(data.get("touch",false))
	mobile_viewport=Vector2(max(1,int(data.get("width",1280))),max(1,int(data.get("height",720))))
	var scene=get_tree().current_scene
	if scene!=null:
		_enhance_mobile_controls(scene)
		var sidebar=scene.get_node_or_null("Sidebar")
		if sidebar!=null and sidebar.has_method("apply_mobile_layout"):
			sidebar.call_deferred("apply_mobile_layout",mobile_viewport.x,mobile_viewport.y,mobile_touch)
		var portal=scene.get_node_or_null("RhythiansPortal")
		if portal==null and sidebar!=null:
			portal=sidebar.get("portal")
		if portal!=null and is_instance_valid(portal) and portal.has_method("apply_mobile_layout"):
			portal.call_deferred("apply_mobile_layout",mobile_viewport.x,mobile_viewport.y,mobile_touch)

func _enhance_mobile_controls(node):
	if node==null:
		return
	if node is BaseButton:
		node.rect_min_size.y=max(node.rect_min_size.y,62 if mobile_touch else 46)
		if node is Button or node is CheckButton or node is OptionButton or node is MenuButton:
			node.add_font_override("font",RhythianUI.font(18 if mobile_touch else 14,1 if node is Button else 0))
	elif node is LineEdit or node is TextEdit:
		node.rect_min_size.y=max(node.rect_min_size.y,60 if mobile_touch else 44)
		if mobile_touch:
			node.add_font_override("font",RhythianUI.font(18))
			_register_mobile_text_control(node)
	elif node is SpinBox:
		node.rect_min_size.y=max(node.rect_min_size.y,60 if mobile_touch else 44)
		if mobile_touch:
			var line=node.get_line_edit()
			if line!=null:
				line.add_font_override("font",RhythianUI.font(18))
				_register_mobile_text_control(line)
	elif node is HSlider or node is VSlider:
		if mobile_touch:
			node.rect_min_size.y=max(node.rect_min_size.y,46)
	for child in node.get_children():
		_enhance_mobile_controls(child)

func _mobile_text_focus_entered(control:Control):
	if not mobile_touch or control==null or not is_instance_valid(control):
		return
	if mobile_keyboard_open and mobile_keyboard_control==control:
		return
	mobile_keyboard_control=control
	mobile_keyboard_open=true
	var current=""
	var multiline=false
	var input_mode="text"
	if control is LineEdit:
		current=control.text
		if control.get_parent() is SpinBox:
			input_mode="decimal"
	elif control is TextEdit:
		current=control.text
		multiline=true
	mobile_keyboard_pending_text=current
	if window and window.rhythiansOpenKeyboard:
		window.rhythiansOpenKeyboard(current,multiline,input_mode)

func _mobile_text_focus_exited(control:Control):
	if mobile_keyboard_control!=control:
		return
	if mobile_keyboard_open:
		return
	mobile_keyboard_control=null
	mobile_keyboard_pending_text=""

func _mobile_keyboard_text(value:String):
	if not mobile_keyboard_open or mobile_keyboard_control==null or not is_instance_valid(mobile_keyboard_control):
		return
	mobile_keyboard_pending_text=value
	if mobile_keyboard_control is LineEdit:
		var parent=mobile_keyboard_control.get_parent()
		if parent is SpinBox:
			return
		mobile_keyboard_control.text=value
		mobile_keyboard_control.caret_position=value.length()
		mobile_keyboard_control.emit_signal("text_changed",value)
	elif mobile_keyboard_control is TextEdit:
		mobile_keyboard_control.text=value

func _mobile_keyboard_done(value:String):
	if mobile_keyboard_control==null or not is_instance_valid(mobile_keyboard_control):
		mobile_keyboard_open=false
		mobile_keyboard_pending_text=""
		return
	var control=mobile_keyboard_control
	mobile_keyboard_pending_text=value
	if control is LineEdit:
		var parent=control.get_parent()
		if parent is SpinBox:
			if value.strip_edges().is_valid_float():
				parent.value=float(value)
			control.text=str(parent.value)
		else:
			control.text=value
			control.caret_position=value.length()
			control.emit_signal("text_changed",value)
			control.emit_signal("text_entered",value)
	elif control is TextEdit:
		control.text=value
	mobile_keyboard_open=false
	mobile_keyboard_control=null
	mobile_keyboard_pending_text=""
	control.release_focus()
	save_and_sync_settings(false)


func _register_mobile_text_control(control:Control):
	if control==null or control.has_meta("rhythians_mobile_keyboard"):
		return
	control.set_meta("rhythians_mobile_keyboard",true)
	control.connect("focus_entered",self,"_mobile_text_focus_entered",[control])
	control.connect("focus_exited",self,"_mobile_text_focus_exited",[control])

func _score_submitted(success:bool, message:String):
	if window and window.rhythiansScoreResult:
		window.rhythiansScoreResult(success, message)
