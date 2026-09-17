extends Button

var has_been_pressed:bool = false

func _pressed():
	if has_been_pressed:
		return
	if OS.has_feature("HTML5"):
		has_been_pressed = true
		WebPortal.pick_sspm()
		has_been_pressed = false
		return
	has_been_pressed = true
	get_parent().black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	Rhythia.conmgr_transit = "addsongs"
	get_tree().change_scene("res://scenes/loaders/contentmgrload.tscn")

func _ready():
	visible = OS.has_feature("HTML5") or ProjectSettings.get_setting("application/config/enable_new_content_mgr")
