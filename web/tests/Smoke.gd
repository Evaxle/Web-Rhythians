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
	Rhythia.song_end_type = Globals.END_PASS
	Rhythia.song_end_total_notes = 5
	Rhythia.song_end_hits = 4
	Rhythia.song_end_misses = 1
	WebPortal.finished()
	check(WebPortal.last_score_payload.cameraMode == "spin" and WebPortal.last_score_payload.accuracy == 80, "spin setting submits a spin score")

	Rhythia.cam_unlock = false
	WebPortal.begin_run()
	WebPortal.finished()
	check(WebPortal.last_score_payload.cameraMode == "lock", "lock setting submits a lock score")

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

	WebPortal.last_score_payload = {}
	var portal_mode_test = load("res://scripts/ui/menu/RhythiansPortal.gd").new()
	portal_mode_test.spin_enabled = false
	portal_mode_test._spin_toggled(true)
	check(Rhythia.cam_unlock, "Rhythians Spin setting enables spin gameplay and score mode")
	portal_mode_test._spin_toggled(false)
	check(not Rhythia.cam_unlock, "Rhythians Spin setting disables spin for lock scores")
	portal_mode_test.queue_free()

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
			yield(get_tree(),"idle_frame")
			yield(get_tree(),"idle_frame")
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
			var old_maps_total = Rhythian.maps_total
			var old_maps_offset = Rhythian.maps_loaded_offset
			var old_maps_query = Rhythian.maps_loaded_query
			var old_maps_rank = Rhythian.maps_loaded_rank_index
			var old_maps_page_loaded = Rhythian.maps_page_loaded
			Rhythian.logged_in = true
			Rhythian.profile = {"rhp":1000}
			Rhythian.maps_cache = []
			for i in range(40):
				Rhythian.maps_cache.append({
					"id":"smoke-map-"+str(i),
					"title":"Smoke Map "+str(i),
					"artist":"Artist",
					"mapper":"Mapper",
					"rating":1.5,
					"rankName":"Copper",
					"noteCount":100,
					"length":60,
					"completion":{"passed":false}
				})
			Rhythian.maps_total = 100
			Rhythian.maps_loaded_offset = 0
			Rhythian.maps_loaded_query = ""
			Rhythian.maps_loaded_rank_index = -1
			Rhythian.maps_page_loaded = true
			Rhythian.catalog_loading = false
			sidebar.open_page("maps")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.portal.selected_page == "maps", "optimized Maps page renders")
			check(sidebar.portal.content.get_child_count() <= 10, "Maps page keeps 40 cards inside one catalog grid")
			var map_grid=sidebar.portal.content.get_node_or_null("MapCatalogGrid")
			check(map_grid!=null and map_grid.columns==4, "Maps catalog renders four maps across")
			check(map_grid!=null and map_grid.get_child_count()==40, "Maps catalog renders exactly 40 maps per full page")
			check(sidebar.nav.has(["maps","Maps"]), "Maps is exposed as a top navigation tab")
			check(sidebar.portal._safe_user_name({"displayName":null,"username":"FallbackPlayer"})=="FallbackPlayer", "online players fall back from null display names")
			Rhythian.logged_in = old_logged_in
			Rhythian.profile = old_profile
			Rhythian.maps_cache = old_maps
			Rhythian.maps_total = old_maps_total
			Rhythian.maps_loaded_offset = old_maps_offset
			Rhythian.maps_loaded_query = old_maps_query
			Rhythian.maps_loaded_rank_index = old_maps_rank
			Rhythian.maps_page_loaded = old_maps_page_loaded

			sidebar.open_native_page("settings")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			var settings_page=menu.get_node_or_null("Main/Settings")
			check(settings_page!=null and settings_page.visible, "normal Settings page is reachable from top navigation")
			check(not sidebar.portal.visible, "Rhythians portal closes before native Settings opens")
			check(sidebar.get_index()>sidebar.portal.get_index(), "top navigation remains above the Rhythians portal")
			var settings_tabs=menu.get_node_or_null("Main/Settings/S/F/TabContainer")
			check(settings_tabs!=null and settings_tabs.get_tab_count()>=3, "full normal Settings tab container is present")
			var profiles=menu.get_node_or_null("Main/Settings/S/F/TopButtons/TopButtonsHBox/Presets")
			check(profiles!=null, "settings profile selector is present")
			check(profiles!=null and profiles.get_parent().get_node_or_null("ImportSettings")!=null, "Import Settings button is present")

			var settings_source=File.new()
			var settings_temp="/tmp/rhythians-settings-smoke.json"
			check(settings_source.open(settings_temp,File.WRITE)==OK, "settings import smoke file opens")
			settings_source.store_string("{\"sensitivity\":1.25,\"cam_unlock\":true}")
			settings_source.close()
			WebPortal._import_settings({"path":settings_temp,"name":"Smoke 2026.settings.json"})
			var imported_settings=Globals.p("user://Smoke 2026.settings.json")
			check(File.new().file_exists(imported_settings), "browser settings import persists a profile")

			for native_page in ["credits","content","language","settings"]:
				sidebar.open_native_page(native_page)
				yield(get_tree(), "idle_frame")
				yield(get_tree(), "idle_frame")
				check(sidebar.active_page==native_page, "native nav opens "+native_page)

			for i in range(30):
				if i%2==0:
					sidebar.open_page("community")
				else:
					sidebar.open_native_page("settings")
			sidebar.open_native_page("settings")
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(sidebar.active_page=="settings" and menu.get_node("Main/Settings").visible, "rapid mixed navigation resolves to Settings")

			var meta_test={
				"id":"metadata-smoke",
				"title":"Metadata Smoke",
				"rating":4.25,
				"difficulty":"Gold",
				"rankName":"Gold",
				"isRanked":true,
				"isLegacy":false,
				"maxRewards":{"lock":120,"spin":140,"vr":160}
			}
			var persisted_meta=Rhythian._map_registry_payload(meta_test)
			check(int(persisted_meta.get("maxRewards",{}).get("vr",0))==160, "downloaded map metadata preserves RPV")
			check(Rhythian.get_map_summary(meta_test).find("RPL +120")!=-1 and Rhythian.get_map_summary(meta_test).find("RPV +160")!=-1, "Play metadata summary includes rating and all rank rewards")

			sidebar.to_play()
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(not sidebar.portal.visible, "Play returns to the normal Godot client")
			check(menu.get_node("Main/Maps").visible, "Play root is restored after leaving another tab")

	print("SMOKE_FAILURES=" + str(failures))
	get_tree().quit(1 if failures else 0)
