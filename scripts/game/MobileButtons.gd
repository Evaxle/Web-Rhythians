extends Control

func _on_Pause_pressed():
	Input.action_press("pause")
	
func _on_Pause_released():
	Input.action_release("pause")
	
func _on_GiveUp_pressed():
	Input.action_press("give_up")
	
func _on_GiveUp_released():
	Input.action_release("give_up")

func _ready():
	var tween:Tween = Tween.new()
	add_child(tween)
	
	var mobile_buttons=OS.has_feature("Android") or (OS.has_feature("HTML5") and WebPortal.mobile_touch)
	$Pause/Button.visible = mobile_buttons
	$GiveUp/Button.visible = mobile_buttons
	
	if Rhythia.mirror_buttons and mobile_buttons:
		var viewport_width=float(OS.get_window_safe_area().size.x)
		if OS.has_feature("HTML5") and WebPortal.mobile_touch:
			viewport_width=WebPortal.mobile_viewport.x
		$Pause/Button.position.x = max(0,viewport_width - 150)
		$GiveUp/Button.position.x = max(0,viewport_width - 150)
	
	tween.interpolate_property($Pause, "modulate", Color(1,1,1,0.5), Color(1,1,1,0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
	tween.interpolate_property($GiveUp, "modulate", Color(1,1,1,0.5), Color(1,1,1,0), 1, Tween.TRANS_QUAD, Tween.EASE_IN_OUT, 1)
	tween.start()
