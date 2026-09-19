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
	if window and window.rhythiansPersistUserData:
		window.rhythiansPersistUserData()

func command(args):
	if args.empty(): return
	var parsed = JSON.parse(str(args[0]))
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return
	var data = parsed.result
	match data.get("action", ""):
		"auth":
			var account = data.get("account", {})
			if typeof(account) != TYPE_DICTIONARY: return
			Rhythian.apply_browser_auth(account)
			if window:
				window.rhythiansAccountApplied(JSON.print({
					"loggedIn": Rhythian.logged_in,
					"username": Rhythian.username
				}))
		"guest":
			Rhythian.logout()
			active_map.clear()
			active_map_path = ""
			if window:
				window.rhythiansAccountApplied(JSON.print({"loggedIn": false, "username": ""}))
		"spin":
			Rhythia.cam_unlock = bool(data.get("enabled", false))
			Rhythia.save_settings()
		"save":
			Rhythia.save_settings()
		"flush":
			if Rhythian.logged_in:
				Rhythian._flush_score_queue()
		"portal":
			Rhythia.save_settings()
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
		"import":
			_import_sspm(data)
		"import-settings":
			_import_settings(data)

func _play_web_map(data:Dictionary):
	if not menu_loaded: return
	var path = str(data.get("path", ""))
	if not path.begins_with("/tmp/rhythians-") or not path.ends_with(".sspm"): return
	Rhythian.clear_runtime_song()
	var song = Rhythia.registry_song.add_sspm_map(path)
	if song == null:
		if window: window.rhythiansError("This map cannot be loaded by the client.")
		return
	active_map = data.get("map", {})
	active_map_path = path
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

func _process(_delta):
	if window and mode_sync_enabled and last_spin != Rhythia.cam_unlock:
		last_spin = Rhythia.cam_unlock
		window.rhythiansMode(last_spin)


func _score_submitted(success:bool, message:String):
	if window and window.rhythiansScoreResult:
		window.rhythiansScoreResult(success, message)
