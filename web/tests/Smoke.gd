extends Node
var failures = 0
class Capture extends Reference:
	var payload = {}
	var count = 0
	func rhythiansScore(text):
		payload = JSON.parse(text).result
		count += 1
func check(value,label):
	if value: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func _ready():
	var start = OS.get_ticks_msec()
	while not Rhythia.first_init_done and OS.get_ticks_msec() - start < 15000:
		yield(get_tree(), "idle_frame")
	check(Rhythia.first_init_done, "client initializes")
	var score_song = null
	for version in [1, 2]:
		var song = Rhythia.registry_song.add_sspm_map("res://web/tests/v%d.sspm" % version)
		check(song != null and not song.is_broken and song.note_count == 5, "SSPM v%d import" % version)
		check(song != null and song.stream() != null and abs(song.stream().get_length() - 6.0) < 0.01, "embedded audio duration")
		score_song = song
	Rhythia.select_song(score_song)
	Rhythian.registry[str(score_song.filePath).get_file()] = {"id": "test"}
	var capture = Capture.new()
	WebPortal.window = capture
	Rhythia.cam_unlock = true
	WebPortal.begin_run()
	Rhythia.song_end_total_notes = 5
	Rhythia.song_end_hits = 4
	Rhythia.song_end_misses = 1
	WebPortal.finished()
	check(capture.payload.cameraMode == "spin" and capture.payload.accuracy == 80, "spin score payload uses actual camera mode")
	Rhythia.cam_unlock = false
	WebPortal.begin_run()
	WebPortal.finished()
	check(capture.payload.cameraMode == "lock", "lock score payload")
	var count = capture.count
	Rhythia.mod_nofail = true
	Rhythian.on_song_ended(Globals.END_PASS)
	check(capture.count == count, "no-fail runs are not submitted")
	Rhythia.mod_nofail = false
	Rhythia.cam_unlock = true
	Rhythia.save_settings()
	Rhythia.cam_unlock = false
	Rhythia.load_saved_settings()
	check(Rhythia.cam_unlock, "spin preference saves and restores")
	WebPortal.window = null
	var menu = load("res://scenes/menu/menu2.tscn").instance()
	get_tree().root.add_child(menu)
	yield(get_tree(), "idle_frame")
	check(menu != null and menu.get_node_or_null("Sidebar") != null, "real client menu loads")
	print("SMOKE_FAILURES=" + str(failures))
	get_tree().quit(1 if failures else 0)
