extends Node

var callback
var window
var active_map = {}
var menu_loaded = false
var active_mode = "lock"

func _ready():
	if not OS.has_feature("HTML5"):
		return
	window = JavaScript.get_interface("window")
	callback = JavaScript.create_callback(self, "command")
	window.rhythiansCommand = callback

func menu_ready():
	menu_loaded = true
	print("RHYTHIANS_MENU_READY")
	if window:
		window.rhythiansReady(JSON.print({"persistent": OS.is_userfs_persistent()}))

func pick_sspm():
	if window:
		window.rhythiansPickSspm()

func command(args):
	if args.empty():
		return
	var parsed = JSON.parse(str(args[0]))
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var data = parsed.result
	match data.get("action", ""):
		"save":
			Rhythia.save_settings()
		"import":
			_import_files(data.get("files", []))

func _import_files(files):
	if not menu_loaded or typeof(files) != TYPE_ARRAY:
		return
	var imported = 0
	var selected = null
	for entry in files:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var song = _import_sspm(str(entry.get("path", "")), str(entry.get("name", "")))
		if song != null:
			selected = song
			imported += 1
	if selected != null:
		Rhythia.select_song(selected)
	if window:
		var message = "%d SSPM map%s imported into the client." % [imported, "" if imported == 1 else "s"]
		window.rhythiansImported(imported, message)
	if imported > 0:
		menu_loaded = false
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func _import_sspm(path:String, original_name:String):
	if not path.begins_with("/tmp/rhythians-import-") or not path.ends_with(".sspm"):
		return null
	var name = original_name.get_file()
	if name == "" or not name.to_lower().ends_with(".sspm"):
		return null
	var directory = Directory.new()
	if not directory.dir_exists(Rhythia.user_map_dir):
		if directory.make_dir_recursive(Rhythia.user_map_dir) != OK:
			return null
	var target = Rhythia.user_map_dir.plus_file(name)
	if directory.file_exists(target):
		var stem = name.get_basename()
		var extension = name.get_extension()
		target = Rhythia.user_map_dir.plus_file("%s-%d.%s" % [stem, OS.get_ticks_msec(), extension])
	if directory.copy(path, target) != OK:
		return null
	var song = Rhythia.registry_song.add_sspm_map(target)
	if song == null:
		directory.remove(target)
		if window:
			window.rhythiansError("The selected SSPM file could not be loaded by the client.")
		return null
	return song

func begin_run():
	active_mode = "spin" if Rhythia.cam_unlock else "lock"

func finished():
	if not window or active_map.empty():
		return
	var total = max(Rhythia.song_end_total_notes, 1)
	var mods = []
	for key in ["mod_mirror_x", "mod_mirror_y", "mod_extra_energy", "mod_no_regen", "mod_sudden_death", "mod_ghost", "mod_flashlight", "mod_nearsighted", "mod_hardrock", "mod_chaos"]:
		if Rhythia.get(key):
			mods.append(key)
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
