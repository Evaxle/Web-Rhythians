extends Node

signal files_selected(paths)
signal file_selected(path)
signal dir_selected(path)
signal folder_selected(path)
signal canceled

var title = ""
var dialog_title = ""
var filters = []
var initial_path = ""
var current_dir = ""
var current_file = ""
var multiselect = false

func show():
	emit_signal("canceled")

func popup():
	emit_signal("canceled")
