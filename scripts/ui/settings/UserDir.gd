extends Button

func _pressed():
	if OS.has_feature("HTML5"):
		return
	if not OS.has_feature("Android"):
		OS.shell_open(ProjectSettings.globalize_path(Globals.p("user://")))

func _ready():
	if OS.has_feature("HTML5"):
		disabled = true
		text = "User data is stored in browser storage"
	elif OS.has_feature("Android"):
		disabled = true
		text = "User folder location: " + Globals.p("user://")
