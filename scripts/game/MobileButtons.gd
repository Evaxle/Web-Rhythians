extends Control

var pause_button:Button
var leave_button:Button
var hint_label:Label

func _on_Pause_pressed():
	Input.action_press("pause")

func _on_Pause_released():
	Input.action_release("pause")

func _on_GiveUp_pressed():
	Input.action_press("give_up")

func _on_GiveUp_released():
	Input.action_release("give_up")

func _make_action_button(text:String) -> Button:
	var button=Button.new()
	button.text=text
	button.pause_mode=Node.PAUSE_MODE_PROCESS
	button.focus_mode=Control.FOCUS_NONE
	button.rect_min_size=Vector2(116,54)
	button.add_font_override("font",RhythianUI.font(17,1))
	return button

func _install_web_controls():
	if not (OS.has_feature("HTML5") and WebPortal.mobile_touch):
		return
	$Pause/Button.visible=false
	$GiveUp/Button.visible=false
	pause_button=_make_action_button("Pause")
	leave_button=_make_action_button("Hold Leave")
	add_child(pause_button)
	add_child(leave_button)
	pause_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	leave_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.rect_position=Vector2(14,14)
	leave_button.rect_position=Vector2(-130,14)
	pause_button.connect("button_down",self,"_on_Pause_pressed")
	pause_button.connect("button_up",self,"_on_Pause_released")
	leave_button.connect("button_down",self,"_on_GiveUp_pressed")
	leave_button.connect("button_up",self,"_on_GiveUp_released")
	hint_label=Label.new()
	hint_label.text="Tap anywhere to skip"
	hint_label.align=Label.ALIGN_CENTER
	hint_label.add_font_override("font",RhythianUI.font(18,1))
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.margin_left=120
	hint_label.margin_right=-120
	hint_label.margin_top=-52
	hint_label.margin_bottom=-16
	hint_label.visible=false
	add_child(hint_label)

func _input(event):
	if not (OS.has_feature("HTML5") and WebPortal.mobile_touch):
		return
	if event is InputEventScreenTouch and event.pressed:
		var spawn=get_node_or_null("../../Spawn")
		if spawn!=null and bool(spawn.get("can_skip")) and spawn.has_method("mobile_tap_skip"):
			spawn.mobile_tap_skip()

func _process(_delta):
	if hint_label!=null:
		var spawn=get_node_or_null("../../Spawn")
		hint_label.visible=spawn!=null and bool(spawn.get("can_skip"))

func _ready():
	var tween:Tween = Tween.new()
	add_child(tween)

	var mobile_buttons=OS.has_feature("Android") or (OS.has_feature("HTML5") and WebPortal.mobile_touch)
	$Pause/Button.visible = mobile_buttons
	$GiveUp/Button.visible = mobile_buttons

	if OS.has_feature("HTML5") and WebPortal.mobile_touch:
		_install_web_controls()
	elif Rhythia.mirror_buttons and mobile_buttons:
		var viewport_width=float(OS.get_window_safe_area().size.x)
		$Pause/Button.position.x = max(0,viewport_width - 150)
		$GiveUp/Button.position.x = max(0,viewport_width - 150)

	tween.interpolate_property($Pause, "modulate", Color(1,1,1,0.5), Color(1,1,1,0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
	tween.interpolate_property($GiveUp, "modulate", Color(1,1,1,0.5), Color(1,1,1,0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
