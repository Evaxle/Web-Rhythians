extends MenuButton

const PROFILE_ID_BASE = 1000
const CREATE_ID = 2000
const IMPORT_ID = 2001

var profiles:Array = []
var overwrite_submenu:PopupMenu = PopupMenu.new()
var delete_submenu:PopupMenu = PopupMenu.new()
var initialized:bool = false
var import_button:Button

func _ready():
	if not initialized:
		initialized = true
		overwrite_submenu.name = "Overwrite"
		delete_submenu.name = "Delete"
		get_popup().add_child(overwrite_submenu)
		get_popup().add_child(delete_submenu)
		get_popup().connect("id_pressed",self,"on_pressed")
		overwrite_submenu.connect("id_pressed",self,"overwrite_profile")
		delete_submenu.connect("id_pressed",self,"delete_profile")
		if OS.has_feature("HTML5") and WebPortal.has_signal("settings_imported") and not WebPortal.is_connected("settings_imported",self,"_browser_import_finished"):
			WebPortal.connect("settings_imported",self,"_browser_import_finished")
		import_button=Button.new()
		import_button.name="ImportSettings"
		import_button.text="Import Settings"
		import_button.rect_min_size=Vector2(120,33)
		import_button.focus_mode=Control.FOCUS_NONE
		get_parent().add_child(import_button)
		get_parent().move_child(import_button,get_index()+1)
		import_button.connect("pressed",self,"_import_profile")
	_refresh_profiles()

func _refresh_profiles():
	get_popup().clear()
	delete_submenu.clear()
	overwrite_submenu.clear()
	profiles = Globals.get_files_recursive([Globals.p("user://")],1,"json").files
	for i in range(profiles.size()-1,-1,-1):
		if not str(profiles[i]).ends_with(".settings.json"):
			profiles.remove(i)
	profiles.sort()
	for i in range(profiles.size()):
		var profile_name = _profile_name(profiles[i])
		var id = PROFILE_ID_BASE+i
		get_popup().add_item(profile_name,id)
		delete_submenu.add_item(profile_name,id)
		overwrite_submenu.add_item(profile_name,id)
	get_popup().add_separator()
	get_popup().add_item("Create New From Current",CREATE_ID)
	get_popup().add_item("Import Settings File",IMPORT_ID)
	if profiles.size()>0:
		get_popup().add_separator()
		get_popup().add_submenu_item("Overwrite Profile","Overwrite")
		get_popup().add_submenu_item("Delete Profile","Delete")

func _profile_name(path:String) -> String:
	var file_name = path.get_file()
	if file_name.ends_with(".settings.json"):
		return file_name.substr(0,file_name.length()-14)
	return file_name.get_basename()

func _profile_index(id:int) -> int:
	return id-PROFILE_ID_BASE

func on_pressed(id:int):
	if id==CREATE_ID:
		_create_profile()
		return
	if id==IMPORT_ID:
		_import_profile()
		return
	var index=_profile_index(id)
	if index<0 or index>=profiles.size():
		return
	_switch_profile(profiles[index])

func _create_profile():
	var title="Enter Profile Name"
	var response:int=0
	while true:
		Globals.string_prompt.open("Input a valid file name for the new profile",title,"Profile Name",[{text="OK"},{text="Cancel",wait=0}])
		Globals.string_prompt.s_alert.play()
		response=yield(Globals.string_prompt,"option_selected")
		var name=Globals.string_prompt.input.get_text().strip_edges()
		Globals.string_prompt.close()
		if response!=0:
			return
		yield(get_tree().create_timer(0.1),"timeout")
		if name.is_valid_filename() and name!="":
			Rhythia.save_settings()
			Rhythia.save_settings(Globals.p("user://"+name+".settings.json"))
			_refresh_profiles()
			return
		title="Invalid Profile Name"

func _switch_profile(path:String):
	var result=Rhythia.load_saved_settings(path)
	if result!=0:
		_show_error("Could not load this settings profile. Error "+str(result)+".")
		return
	Rhythia.save_settings()
	if OS.has_feature("HTML5"):
		WebPortal.persist_user_data()
	var menu=get_viewport().get_node_or_null("Menu")
	if menu!=null:
		menu.black_fade_target=true
	yield(get_tree().create_timer(0.15),"timeout")
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func _import_profile():
	if OS.has_feature("HTML5"):
		WebPortal.request_settings_import()
		return
	Globals.file_sel.open_file(self,"import_selected",PoolStringArray(["*.json ; Rhythia settings"]))

func import_selected(files:Array):
	if files.empty():
		return
	_import_settings_file(str(files[0]),str(files[0]).get_file())

func _import_settings_file(source_path:String,original_name:String):
	var source=File.new()
	if source.open(source_path,File.READ)!=OK:
		_show_error("Could not read the settings file.")
		return
	var text=source.get_as_text()
	source.close()
	var parsed=JSON.parse(text)
	if parsed.error!=OK or typeof(parsed.result)!=TYPE_DICTIONARY:
		_show_error("That file is not a valid Rhythia settings JSON file.")
		return
	var name=_safe_import_name(original_name)
	var target=Globals.p("user://"+name+".settings.json")
	var output=File.new()
	if output.open(target,File.WRITE)!=OK:
		_show_error("Could not save the imported settings profile.")
		return
	output.store_string(text)
	output.close()
	_refresh_profiles()

func _safe_import_name(original_name:String) -> String:
	var name=original_name.get_file()
	if name.ends_with(".settings.json"):
		name=name.substr(0,name.length()-14)
	elif name.ends_with(".json"):
		name=name.substr(0,name.length()-5)
	var safe=""
	for i in range(name.length()):
		var ch=name.substr(i,1)
		if ch.is_valid_identifier() or ch in ["0","1","2","3","4","5","6","7","8","9"," ","-","_","(",")","[","]"]:
			safe+=ch
	safe=safe.strip_edges()
	if safe=="":
		safe="Imported "+str(OS.get_unix_time())
	return safe

func _browser_import_finished(success:bool,message:String,_path:String):
	if success:
		_refresh_profiles()
	text="Select Profile" if success else "Import failed"
	hint_tooltip=message

func overwrite_profile(id:int):
	var index=_profile_index(id)
	if index<0 or index>=profiles.size():
		return
	Rhythia.save_settings(profiles[index])
	if OS.has_feature("HTML5"):
		WebPortal.persist_user_data()
	_refresh_profiles()

func delete_profile(id:int):
	var index=_profile_index(id)
	if index<0 or index>=profiles.size():
		return
	var user_dir=Directory.new()
	var result=user_dir.remove(profiles[index])
	if result!=OK:
		_show_error("Could not delete this settings profile. Error "+str(result)+".")
		return
	if OS.has_feature("HTML5"):
		WebPortal.persist_user_data()
	_refresh_profiles()

func _show_error(message:String):
	Globals.confirm_prompt.open(message,"Settings Profile",[{text="OK"}])
