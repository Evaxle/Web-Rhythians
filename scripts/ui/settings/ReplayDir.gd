extends Button

func _pressed():
	if OS.has_feature("HTML5"):
		return
	OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://replays/")))

func _ready():
	if OS.has_feature("HTML5"):
		disabled = true
		text = "Replays are stored in browser storage"
	else:
		visible = not OS.has_feature("Android")
