extends Button

func _pressed():
	if OS.has_feature("HTML5"):
		WebPortal.save_and_sync_settings()
	else:
		Rhythia.save_settings()

func _exit_tree():
	if !OS.has_feature("debug"):
		if OS.has_feature("HTML5"):
			WebPortal.save_and_sync_settings()
		else:
			Rhythia.save_settings()

func _ready():
	visible = OS.has_feature("debug") or OS.has_feature("HTML5")
