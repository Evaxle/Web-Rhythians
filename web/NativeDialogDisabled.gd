extends Node
signal files_selected(paths)
signal file_selected(path)
signal dir_selected(path)
signal canceled
var dialog_title = ""
var filters = []
var current_dir = ""
var current_file = ""
func show():
	emit_signal("canceled")
func popup():
	emit_signal("canceled")
