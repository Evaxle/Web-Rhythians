extends Node

var failures = 0

class Capture extends Reference:
	var payload = {}
	var count = 0
	var import_ok = false
	var import_name = ""
	var import_message = ""
	func rhythiansScore(text):
		payload = JSON.parse(text).result
		count += 1
	func rhythiansImported(name, ok, message):
		import_name = str(name)
		import_ok = bool(ok)
		import_message = str(message)
	func rhythiansCatalogReady(_count): pass
	func rhythiansAccountApplied(_text): pass
	func rhythiansAuthChanged(_text): pass

func check(value,label):
	if value:
		print("PASS: " + label)
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

	var source = File.new()
	var source_ok = source.open("res://web/tests/v2.sspm", File.READ) == OK
	check(source_ok, "browser import fixture opens")
	if source_ok:
		var bytes = source.get_buffer(source.get_len())
		source.close()
		var tmp_path = "/tmp/rhythians-import-smoke.sspm"
		var temp = File.new()
		var write_ok = temp.open(tmp_path, File.WRITE) == OK
		check(write_ok, "browser import temp file opens")
		if write_ok:
			temp.store_buffer(bytes)
			temp.close()
			WebPortal._import_sspm({"path": tmp_path, "name": "smoke-browser-import.sspm"})
			check(capture.import_ok, "browser SSPM import succeeds")
			var imported_path = Globals.p("user://maps/browser imports/smoke-browser-import.sspm")
			check(File.new().file_exists(imported_path), "browser SSPM persists in user maps")

	WebPortal.window = null
	var menu = load("res://scenes/menu/menu2.tscn").instance()
	get_tree().root.add_child(menu)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var sidebar = menu.get_node_or_null("Sidebar")
	check(sidebar != null, "real client Sidebar loads")
	if sidebar != null:
		check(sidebar.portal != null and sidebar.portal.get_parent() != null, "Rhythians portal attaches")
		if sidebar.portal != null:
			sidebar.open_page("home")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.visible and sidebar.portal.selected_page == "home", "Rhythians Home opens inside Godot")
			sidebar.open_page("maps")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.visible and sidebar.portal.selected_page == "maps", "Rhythians Maps opens inside Godot")

			for i in range(40):
				var rapid_page = ["community","account","maps"][i % 3]
				sidebar.open_page(rapid_page)
			sidebar.open_page("community")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.selected_page == "community", "rapid tab switching coalesces to the latest page")

			var wiki_key = sidebar.portal._cache_key("wiki",{})
			sidebar.portal.api_cache[wiki_key] = {"articles":[{"title":"Old page result","slug":"old-page-result","description":"must not render after leaving"}]}
			sidebar.portal.api_cache_time[wiki_key] = OS.get_ticks_msec()
			sidebar.open_page("wiki")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			sidebar.open_page("community")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.selected_page == "community" and sidebar.portal.title_label.text == "Community Settings", "stale async page cannot overwrite the active tab")

			var old_logged_in = Rhythian.logged_in
			var old_profile = Rhythian.profile.duplicate(true)
			var old_maps = Rhythian.maps_cache.duplicate(true)
			Rhythian.logged_in = true
			Rhythian.profile = {"rhp":1000}
			Rhythian.maps_cache = []
			for i in range(100):
				Rhythian.maps_cache.append({
					"id":"smoke-map-"+str(i),
					"title":"Smoke Map "+str(i),
					"artist":"Artist",
					"mapper":"Mapper",
					"rating":1.5,
					"rankName":"Silver",
					"noteCount":100,
					"length":60,
					"completion":{"passed":false}
				})
			Rhythian.catalog_loading = false
			sidebar.open_page("maps")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.selected_page == "maps", "optimized Maps page renders")
			check(sidebar.portal.content.get_child_count() <= 30, "Maps page renders only one lightweight catalog page")
			Rhythian.logged_in = old_logged_in
			Rhythian.profile = old_profile
			Rhythian.maps_cache = old_maps

			sidebar.to_play()
			yield(get_tree(), "idle_frame")
			check(not sidebar.portal.visible, "Play returns to the normal Godot client")

	print("SMOKE_FAILURES=" + str(failures))
	get_tree().quit(1 if failures else 0)
