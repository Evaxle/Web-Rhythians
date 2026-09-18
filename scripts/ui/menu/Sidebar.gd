extends Panel

var portal:Control
var account:Button
var nav = [["home","Home"],["maps","Maps"],["daily","Daily"],["path","Path"],["challenge","Challenge"],["online","Online"],["leaderboards","Leaderboards"],["battles","Battles"],["clips","Clips"],["search","Search"],["messages","Messages"],["global-chat","Global Chat"],["wiki","Wiki"],["rules","Rules"],["community","Community"]]

var pending_page:String = ""
var active_page:String = "play"
var navigation_scheduled:bool = false

func _ready():
	set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	anchor_right = 1.0
	rect_min_size.y = 78
	call_deferred("raise")
	for child in get_children(): child.visible = false
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
	brand.text = "Rhythia · " + version
	brand.add_color_override("font_color",Color(0.72,0.75,0.82))
	brand.add_font_override("font",RhythianUI.font(13))
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(brand)
	var center_scroll = ScrollContainer.new()
	center_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_scroll.scroll_horizontal_enabled = true
	center_scroll.scroll_vertical_enabled = false
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
	for item in nav:
		var b = _button(item[1],false)
		b.rect_min_size.x = 70 if item[1].length() <= 8 else 88
		center.add_child(b)
		b.connect("pressed",self,"open_page",[item[0]])
	account = _button(Rhythian.username if Rhythian.logged_in else "Sign in",false)
	account.rect_min_size = Vector2(112,44)
	bar.add_child(account)
	account.connect("pressed",self,"open_account")
	portal = load("res://scripts/ui/menu/RhythiansPortal.gd").new()
	call_deferred("_attach_portal")

func _attach_portal():
	if portal == null: return
	var parent = get_parent()
	if parent != null and portal.get_parent() == null:
		parent.add_child(portal)
		portal.raise()
	if OS.has_feature("HTML5"): WebPortal.menu_ready()

func _button(text:String,primary:bool) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_color_override("font_color",Color(1,1,1,1))
	b.add_color_override("font_color_hover",Color(1,1,1,1))
	b.add_font_override("font",RhythianUI.font(16 if primary else 12,1 if primary else 0))
	return b

func _process(_delta:float):
	if account != null:
		account.text = Rhythian.username if Rhythian.logged_in else "Sign in"

func open_page(page:String):
	if page == "":
		return
	pending_page = page
	if navigation_scheduled:
		return
	navigation_scheduled = true
	call_deferred("_apply_pending_page")

func _apply_pending_page():
	navigation_scheduled = false
	var page = pending_page
	pending_page = ""
	if page == "":
		return
	if active_page == page and portal != null and portal.visible:
		return
	active_page = page
	_hide_game_pages()
	if portal != null and portal.has_method("open_page"):
		portal.open_page(page)

func open_account():
	open_page("account")

func to_play():
	pending_page = ""
	navigation_scheduled = false
	active_page = "play"
	if portal != null and portal.has_method("close_page"):
		portal.close_page()
	_hide_game_pages()
	var results = get_node_or_null("../Main/Results")
	if results != null:
		results.visible = true

func _hide_game_pages():
	for path in ["../Main/Results","../Main/Maps","../Main/Settings","../Main/Credits","../Main/Content","../Main/Language","../Main/Rhythian"]:
		var node = get_node_or_null(path)
		if node != null:
			node.visible = false
