extends Control

func _ready():
	if OS.has_feature("HTML5"):
		yield(get_tree().create_timer(0.35), "timeout")
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")
	elif has_node("dya"):
		$dya.play()

func _on_dya_finished():
	get_tree().quit()
