extends Button

var debounce = false

func _ready():
	if OS.has_feature("HTML5"):
		visible = false

func _pressed():
	if OS.has_feature("HTML5") or debounce or !Rhythia.selected_song:
		return
	debounce = true
	text = "Saving"
	$SaveFile.set_initial_path("~/Downloads/%s.txt" % Rhythia.selected_song.id)
	$SaveFile.show()
	var path = yield($SaveFile,"file_selected")
	disabled = true
	if str(path) != "":
		Rhythia.selected_song.export_text(path)
	text = "Export map data"
	disabled = false
	debounce = false
