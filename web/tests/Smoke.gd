extends Node

var failures = 0

class Capture extends Reference:
	var payload = {}
	var count = 0
	var import_ok = false
	var import_name = ""
	var import_message = ""
	var selected_count = 0
	var last_error = ""
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
	func rhythiansSelected(): selected_count += 1
	func rhythiansError(message): last_error = str(message)
	func rhythiansPersistUserData(): return true

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

	var local_key=str(score_song.filePath).get_file()
	Rhythian.registry.erase(local_key)
	Rhythian.song_links[local_key]={
		"id":"linked-local",
		"title":"Linked Local",
		"rating":4.25,
		"difficulty":"Gold",
		"rankName":"Gold",
		"isRanked":true,
		"isLegacy":false,
		"maxRewards":{"lock":120,"spin":140,"vr":160}
	}
	WebPortal.last_score_payload={}
	Rhythia.start_offset=0
	WebPortal.begin_run()
	Rhythia.song_end_type=Globals.END_PASS
	Rhythia.song_end_total_notes=5
	Rhythia.song_end_hits=5
	Rhythia.song_end_misses=0
	WebPortal.finished()
	check(str(WebPortal.last_score_payload.get("challengeMapId",""))=="linked-local", "locally linked Rhythians map produces a score payload")

	WebPortal.last_score_payload={}
	var unchanged_start_count = capture.count
	Rhythia.start_offset = 0
	WebPortal.begin_run()
	Rhythia.start_offset = 750
	WebPortal.finished()
	check(capture.count == unchanged_start_count and WebPortal.last_score_payload.empty(), "changing start time during a run blocks Rhythians score submission")
	Rhythia.start_offset = 0

	var count = capture.count
	Rhythia.mod_nofail = true
	Rhythian.on_song_ended(Globals.END_PASS)
	check(capture.count == count, "no-fail runs are not submitted")
	Rhythia.mod_nofail = false

	var downloaded_source=File.new()
	var downloaded_source_ok=downloaded_source.open("res://web/tests/v2.sspm",File.READ)==OK
	check(downloaded_source_ok,"downloaded map fixture opens")
	if downloaded_source_ok:
		var downloaded_bytes=downloaded_source.get_buffer(downloaded_source.get_len())
		downloaded_source.close()
		var downloaded_tmp="/tmp/rhythians-cached-smoke-downloaded.sspm"
		var downloaded_temp=File.new()
		var downloaded_write_ok=downloaded_temp.open(downloaded_tmp,File.WRITE)==OK
		check(downloaded_write_ok,"downloaded map temp bridge file opens")
		if downloaded_write_ok:
			downloaded_temp.store_buffer(downloaded_bytes)
			downloaded_temp.close()
			if score_song!=null:
				Rhythia.registry_song.check_and_remove_id(score_song.id)
			WebPortal.menu_loaded=true
			var downloaded_meta={
				"id":"smoke-downloaded",
				"title":"Smoke Downloaded",
				"artist":"Smoke Artist",
				"mapper":"Smoke Mapper",
				"rating":4.25,
				"difficulty":"Gold",
				"rankName":"Gold",
				"isRanked":true,
				"maxRewards":{"lock":120,"spin":140,"vr":160}
			}
			WebPortal._play_web_map({"path":downloaded_tmp,"map":downloaded_meta})
			var persisted_download=Globals.p(Rhythian.MAP_DIR).trim_suffix("/")+"/rhythians-smoke-downloaded.sspm"
			check(File.new().file_exists(persisted_download),"Go to map persists the full SSPM into the client map library")
			check(Rhythia.selected_song!=null and str(Rhythia.selected_song.filePath)==persisted_download,"downloaded SSPM becomes the selected playable client song")
			var downloaded_song_meta=Rhythian.get_song_metadata(Rhythia.selected_song)
			check(str(downloaded_song_meta.get("id",""))=="smoke-downloaded","playable downloaded song keeps Rhythians metadata")
			Rhythia.cam_unlock=false
			WebPortal.begin_run()
			Rhythia.song_end_type=Globals.END_PASS
			Rhythia.song_end_total_notes=5
			Rhythia.song_end_hits=5
			Rhythia.song_end_misses=0
			WebPortal.finished()
			check(str(WebPortal.last_score_payload.get("challengeMapId",""))=="smoke-downloaded" and str(WebPortal.last_score_payload.get("cameraMode",""))=="lock","downloaded Rhythians map produces a profile score payload")
			check(capture.selected_count>0 and capture.last_error=="","downloaded map opens without browser bridge errors")

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
			sidebar.portal._update_download_progress_controls("smoke-map-0",50,100)
			check(sidebar.portal.map_progress_labels.has("smoke-map-0") and sidebar.portal.map_progress_labels["smoke-map-0"].text.find("50%")!=-1, "map download card shows progress percentage")
			sidebar.portal._map_downloaded("smoke-map-0",true,"rhythians-smoke-map-0.sspm")
			check(sidebar.portal.map_go_buttons.has("smoke-map-0") and sidebar.portal.map_go_buttons["smoke-map-0"].visible, "completed download shows Go to map")
			check(sidebar.portal.map_download_buttons.has("smoke-map-0") and not sidebar.portal.map_download_buttons["smoke-map-0"].visible, "completed download replaces Download button")
			WebPortal._apply_mobile_layout({"width":390,"height":844,"touch":true,"ios":true,"standalone":true})
			sidebar.apply_mobile_layout(390,844,true)
			sidebar.portal.apply_mobile_layout(390,844,true)
			yield(get_tree(),"idle_frame")
			yield(get_tree(),"idle_frame")
			sidebar.open_page("maps")
			yield(get_tree(),"idle_frame")
			yield(get_tree(),"idle_frame")
			var mobile_grid=sidebar.portal.content.get_node_or_null("MapCatalogGrid")
			check(sidebar.rect_min_size.y>=94,"mobile touch layout enlarges the top navigation")
			check(sidebar.portal.page_margin!=null and sidebar.portal.page_margin.margin_left<=10,"mobile portal uses narrow safe margins")
			check(mobile_grid!=null and mobile_grid.columns==1,"iPhone-width map catalog reflows to one column")
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
			Rhythian.register_runtime_song(score_song,meta_test)
			var runtime_meta=Rhythian.get_song_metadata(score_song)
			check(not runtime_meta.empty() and str(runtime_meta.get("id",""))=="metadata-smoke", "materialized cached map keeps Rhythians metadata in Play")
			check(Rhythian.is_rhythian_song(score_song), "materialized cached map is marked as a Rhythians Play map")
			check(Rhythian.get_map_summary(runtime_meta).find("4.25")!=-1 and Rhythian.get_map_summary(runtime_meta).find("RPS +140")!=-1, "Play Rhythians metadata exposes difficulty and mode rewards")
			Rhythian.clear_runtime_song()

			sidebar.to_play()
			yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			check(not sidebar.portal.visible, "Play returns to the normal Godot client")
			check(menu.get_node("Main/Maps").visible, "Play root is restored after leaving another tab")

	print("SMOKE_FAILURES=" + str(failures))
	get_tree().quit(1 if failures else 0)
