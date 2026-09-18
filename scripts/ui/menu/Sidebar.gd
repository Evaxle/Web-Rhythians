extends Panel

var portal:Control
var account:Button
var nav = [["home","Home"],["maps","Maps"],["clips","Community"],["wiki","Learn"],["account","Profile"]]
var native_nav = [["settings","Settings"],["content","Content"],["language","Language"],["credits","Credits"]]

var pending_page:String = ""
var pending_native:String = ""
var active_page:String = "play"
var navigation_scheduled:bool = false

func _ready():
	set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	anchor_right = 1.0
	rect_min_size.y = 78
	for child in get_children():
		child.visible = false
	var background = ColorRect.new()
	background.color = Color(0.035,0.045,0.07,0.98)
	background.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var bar = HBoxContainer.new()
	bar.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	bar.margin_left = 18
	bar.margin_right = -18
	bar.margin_top = 9
	bar.margin_bottom = -9
	bar.add_constant_override("separation", 6)
	add_child(bar)
	var brand = Label.new()
	var version = "nightly"
	if ProjectSettings.has_setting("application/config/version"):
		version = str(ProjectSettings.get_setting("application/config/version"))
	brand.text = "Rhythians Web · " + version
	brand.add_color_override("font_color",Color(0.72,0.75,0.82))
	brand.add_font_override("font",RhythianUI.font(13))
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(brand)
	var center_scroll = ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.scroll_horizontal_enabled = true
	center_scroll.scroll_vertical_enabled = false
	center_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(center_scroll)
	var center = HBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGN_CENTER
	center.add_constant_override("separation",4)
	center_scroll.add_child(center)
	var play = _button("Play",true)
	play.rect_min_size = Vector2(88,52)
	center.add_child(play)
	play.connect("pressed",self,"to_play")
	for item in native_nav:
		var native_button = _button(item[1],false)
		native_button.rect_min_size.x = 76 if item[1].length() <= 8 else 94
		center.add_child(native_button)
		native_button.connect("pressed",self,"open_native_page",[item[0]])
	for item in nav:
		var button = _button(item[1],false)
		button.rect_min_size.x = 70 if item[1].length() <= 8 else 88
		center.add_child(button)
		button.connect("pressed",self,"open_page",[item[0]])
	account = _button(Rhythian.username if Rhythian.logged_in else "Sign in",false)
	account.rect_min_size = Vector2(112,44)
	bar.add_child(account)
	account.connect("pressed",self,"open_account")
	portal = load("res://scripts/ui/menu/RhythiansPortal.gd").new()
	call_deferred("_attach_portal")
	call_deferred("_raise_nav")

func _attach_portal():
	if portal == null:
		return
	var parent = get_parent()
	if parent != null and portal.get_parent() == null:
		parent.add_child(portal)
		portal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portal.raise()
	call_deferred("_raise_nav")
	if OS.has_feature("HTML5"):
		WebPortal.menu_ready()

func _raise_nav():
	raise()

func _button(text:String,primary:bool) -> Button:
	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_color_override("font_color",Color(1,1,1,1))
	button.add_color_override("font_color_hover",Color(1,1,1,1))
	button.add_font_override("font",RhythianUI.font(16 if primary else 12,1 if primary else 0))
	return button

func _process(_delta:float):
	if account != null:
		account.text = Rhythian.username if Rhythian.logged_in else "Sign in"

func open_page(page:String):
	if page == "":
		return
	_save_settings_if_needed()
	pending_native = ""
	pending_page = page
	_schedule_navigation()

func open_native_page(page:String):
	if page == "":
		return
	_save_settings_if_needed()
	pending_page = ""
	pending_native = page
	_schedule_navigation()

func _schedule_navigation():
	if navigation_scheduled:
		return
	navigation_scheduled = true
	call_deferred("_apply_pending_navigation")

func _apply_pending_navigation():
	navigation_scheduled = false
	if pending_native != "":
		var native_page = pending_native
		pending_native = ""
		_show_native_page(native_page)
		return
	var page = pending_page
	pending_page = ""
	if page == "":
		return
	if portal == null or portal.get_parent() == null:
		pending_page = page
		navigation_scheduled = true
		call_deferred("_apply_pending_navigation")
		return
	if active_page == page and portal.visible:
		return
	active_page = page
	_hide_game_pages()
	if portal.has_method("open_page"):
		portal.open_page(page)
	call_deferred("_raise_nav")

func _show_native_page(page:String):
	var paths = {
		"settings":"../Main/Settings",
		"credits":"../Main/Credits",
		"content":"../Main/Content",
		"language":"../Main/Language"
	}
	if not paths.has(page):
		return
	active_page = page
	if portal != null and portal.has_method("close_page"):
		portal.close_page()
	_hide_game_pages()
	var node = get_node_or_null(paths[page])
	if node != null:
		if page == "settings":
			node.margin_top = 78
		node.margin_left = 0
		node.margin_right = 0
		node.margin_bottom = 0
		node.raise()
		node.visible = true
		call_deferred("_raise_nav")
	else:
		to_play()

func open_account():
	open_page("account")

func to_play():
	_save_settings_if_needed()
	pending_page = ""
	pending_native = ""
	navigation_scheduled = false
	active_page = "play"
	if portal != null and portal.has_method("close_page"):
		portal.close_page()
	_hide_game_pages()
	var play_root = get_node_or_null("../Main/Maps")
	if play_root != null:
		play_root.visible = true
	var results = get_node_or_null("../Main/Maps/Results")
	if results != null:
		results.visible = true
	var map_list = get_node_or_null("../Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list != null and map_list.has_method("refresh_visible_list"):
		map_list.call_deferred("refresh_visible_list")
	call_deferred("_raise_nav")

func _save_settings_if_needed():
	if active_page=="settings":
		Rhythia.save_settings()
		if OS.has_feature("HTML5"):
			WebPortal.persist_user_data()

func _hide_game_pages():
	for path in ["../Main/Results","../Main/Maps","../Main/Settings","../Main/Credits","../Main/Content","../Main/Language","../Main/Rhythian"]:
		var node = get_node_or_null(path)
		if node != null:
			node.visible = false
