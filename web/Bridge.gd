extends Node

var callback
var window
var active_map = {}
var menu_loaded = false
var active_mode = "lock"

func _ready():
	if not OS.has_feature("HTML5"): return
	window = JavaScript.get_interface("window")
	callback = JavaScript.create_callback(self, "command")
	window.rhythiansCommand = callback

func menu_ready():
	menu_loaded = true
	print("RHYTHIANS_MENU_READY")
	if window: window.rhythiansReady(JSON.print({"persistent": OS.is_userfs_persistent(), "spin": Rhythia.cam_unlock}))

func command(args):
	if args.empty(): return
	var parsed = JSON.parse(str(args[0]))
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY: return
	var data = parsed.result
	match data.get("action", ""):
		"spin":
			Rhythia.cam_unlock = bool(data.get("enabled", false))
			Rhythia.save_settings()
		"save": Rhythia.save_settings()
		"portal":
			Rhythia.save_settings()
			active_map.clear()
			menu_loaded = false
			get_tree().paused = false
			get_tree().change_scene("res://scenes/loaders/menuload.tscn")
		"play":
			if not menu_loaded: return
			var path = str(data.get("path", ""))
			if not path.begins_with("/tmp/rhythians-") or not path.ends_with(".sspm"): return
			var song = Rhythia.registry_song.add_sspm_map(path)
			if song == null:
				window.rhythiansError("This map cannot be loaded by the client.")
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
			window.rhythiansSelected()

func begin_run():
	active_mode = "spin" if Rhythia.cam_unlock else "lock"

func finished():
	if not window or active_map.empty(): return
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
		"gameVersion": "rhythians-web-1",
		"integrationVersion": "rhythians-web-1"
	}))

var mode_sync_enabled = false
var last_spin = false
func _process(_delta):
	if window and mode_sync_enabled and last_spin != Rhythia.cam_unlock:
		last_spin = Rhythia.cam_unlock
		window.rhythiansMode(last_spin)
