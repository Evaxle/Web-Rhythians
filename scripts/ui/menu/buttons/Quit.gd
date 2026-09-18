extends Button

func _ready():
	if OS.has_feature("HTML5"):
		visible = false

func _pressed():
	if OS.has_feature("HTML5"):
		return
	get_tree().quit()
