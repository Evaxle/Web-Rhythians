extends Node

var callback
var window
var active_map = {}
var menu_loaded = false
var active_mode = "lock"
var mode_sync_enabled = false
var last_spin = false

func _ready():
	if not OS.has_feature("HTML5"): return
	window = JavaScript.get_interface("window")
	callback = JavaScript.create_callback(self, "command")
	window.rhythiansCommand = callback
	if not Rhythian.is_connected("maps_updated", self, "_maps_updated"):
		Rhythian.connect("maps_updated", self, "_maps_updated")
	if not Rhythian.is_connected("auth_changed", self, "_auth_changed"):
		Rhythian.connect("auth_changed", self, "_auth_changed")

func menu_ready():
	menu_loaded = true
	print("RHYTHIANS_MENU_READY")
	if window:
		window.rhythiansReady(JSON.print({
			"persistent": OS.is_userfs_persistent(),
			"spin": Rhythia.cam_unlock
		}))

func request_signin():
	if window:
		window.rhythiansRequestSignin()

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
			if window:
				window.rhythiansAccountApplied(JSON.print({"loggedIn": false, "username": ""}))
		"spin":
			Rhythia.cam_unlock = bool(data.get("enabled", false))
			Rhythia.save_settings()
		"save":
			Rhythia.save_settings()
		"portal":
			Rhythia.save_settings()
			active_map.clear()
			menu_loaded = false
			get_tree().paused = false
			get_tree().change_scene("res://scenes/loaders/menuload.tscn")
		"play":
			_play_web_map(data)
		"import":
			_import_sspm(data)

func _play_web_map(data:Dictionary):
	if not menu_loaded: return
	var path = str(data.get("path", ""))
	if not path.begins_with("/tmp/rhythians-") or not path.ends_with(".sspm"): return
	var song = Rhythia.registry_song.add_sspm_map(path)
	if song == null:
		if window: window.rhythiansError("This map cannot be loaded by the client.")
		return
	active_map = data.get("map", {})
	Rhythia.cam_unlock = bool(data.get("spin", false))
	active_mode = "spin" if Rhythia.cam_unlock else "lock"
	Rhythia.save_settings()
	mode_sync_enabled = true
	last_spin = Rhythia.cam_unlock
	Rhythia.select_song(song)
	var sidebar = get_tree().current_scene.get_node_or_null("Sidebar")
	if sidebar: sidebar.press(0)
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
	var dir = Directory.new()
	var target_dir = Globals.p("user://maps/browser imports")
	dir.make_dir_recursive(target_dir)
	var target = target_dir.trim_suffix("/") + "/" + safe_name
	var suffix = 2
	while File.new().file_exists(target):
		target = target_dir.trim_suffix("/") + "/" + safe_name.get_basename() + "-" + str(suffix) + ".sspm"
		suffix += 1
	var source = File.new()
	if source.open(path, File.READ) != OK:
		if window: window.rhythiansImported(safe_name, false, "Could not read the imported SSPM.")
		return
	var bytes = source.get_buffer(source.get_len())
	source.close()
	if bytes.size() < 4 or bytes[0] != 0x53 or bytes[1] != 0x53 or bytes[2] != 0x2b or bytes[3] != 0x6d:
		if window: window.rhythiansImported(safe_name, false, "The file is not a valid SSPM.")
		return
	var output = File.new()
	if output.open(target, File.WRITE) != OK:
		if window: window.rhythiansImported(safe_name, false, "Could not save the SSPM in browser storage.")
		return
	output.store_buffer(bytes)
	output.close()
	var song = Rhythia.registry_song.add_sspm_map(target)
	if song == null:
		dir.remove(target)
		if window: window.rhythiansImported(safe_name, false, "The client could not load this SSPM.")
		return
	if window: window.rhythiansImported(safe_name, true, "")

func _selected_rhythian_map() -> Dictionary:
	var song = Rhythia.selected_song
	if song == null: return {}
	var fname = str(song.filePath).get_file()
	if not Rhythian.registry.has(fname): return {}
	var saved = Rhythian.registry[fname]
	var map_id = str(saved.get("id", ""))
	if map_id == "": return {}
	for map in Rhythian.maps_cache:
		if typeof(map) == TYPE_DICTIONARY and str(map.get("id", "")) == map_id:
			return map.duplicate()
	return saved.duplicate()

func begin_run():
	active_map = _selected_rhythian_map()
	active_mode = "spin" if Rhythia.cam_unlock else "lock"

func finished():
	if not window: return
	if active_map.empty():
		active_map = _selected_rhythian_map()
	if active_map.empty(): return
	active_mode = "spin" if Rhythia.cam_unlock else "lock"
	var total = max(Rhythia.song_end_total_notes, 1)
	var mods = []
	for key in ["mod_mirror_x", "mod_mirror_y", "mod_extra_energy", "mod_no_regen", "mod_sudden_death", "mod_ghost", "mod_flashlight", "mod_nearsighted", "mod_hardrock", "mod_chaos"]:
		if Rhythia.get(key): mods.append(key)
	window.rhythiansScore(JSON.print({
		"challengeMapId": str(active_map.get("id", "")),
		"accuracy": float(Rhythia.song_end_hits) / total * 100.0,
		"misses": int(Rhythia.song_end_misses),
		"speed": float(Globals.speed_multi[Rhythia.mod_speed_level]),
		"cameraMode": active_mode,
		"modifiers": PoolStringArray(mods).join(","),
		"resultQualified": true,
		"gameVersion": "rhythians-web-2",
		"integrationVersion": "rhythians-web-2"
	}))

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
		window.rhythiansCatalogReady(Rhythian.maps_cache.size())

func _process(_delta):
	if window and mode_sync_enabled and last_spin != Rhythia.cam_unlock:
		last_spin = Rhythia.cam_unlock
		window.rhythiansMode(last_spin)
