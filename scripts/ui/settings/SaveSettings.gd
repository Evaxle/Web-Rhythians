extends Button

func _pressed():
	Rhythia.save_settings()
	if OS.has_feature("HTML5"):
		WebPortal.persist_user_data()

func _exit_tree():
	if !OS.has_feature("debug"):
		Rhythia.save_settings()
		if OS.has_feature("HTML5"):
			WebPortal.persist_user_data()

func _ready():
	visible = OS.has_feature("debug") or OS.has_feature("HTML5")
