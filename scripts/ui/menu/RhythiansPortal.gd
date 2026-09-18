extends Control

const BASE_URL = "https://www.rhythians.com"
const SETTINGS_FILE = "user://rhythian/client-settings.json"

var title_label:Label
var content:VBoxContainer
var status:Label
var selected_page="home"
var spin_enabled=false
var battle_mode="1v1"
var battle_type="ranked"
var battle:Node
var clips:Node
var search_query=""
var chat_handle=""
var profile_handle=""
var global_refresh_accum=0.0
var direct_refresh_accum=0.0
var map_page=0
var map_search=""
var page_epoch:int=0
var render_scheduled:bool=false
var pending_page:String="home"
var page_dirty:bool=true
var api_cache:Dictionary={}
var api_cache_time:Dictionary={}
var last_connection_check_msec:int=0

func _ready():
	Rhythian.base_url=BASE_URL
	_load_settings()
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	anchor_right=1.0
	anchor_bottom=1.0
	visible=false
	var margin=MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_WIDE)
	margin.margin_left=40
	margin.margin_right=-40
	margin.margin_top=86
	margin.margin_bottom=-24
	add_child(margin)
	var scroll=ScrollContainer.new()
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var root=VBoxContainer.new()
	root.add_constant_override("separation",14)
	root.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	title_label=RhythianUI.label("Home",34,RhythianUI.C_WHITE,1)
	root.add_child(title_label)
	root.add_child(RhythianUI.label("Rhythians inside Rhythia",14,RhythianUI.C_MUTED))
	content=RhythianUI.vbox(12)
	root.add_child(content)
	status=RhythianUI.label("",13,RhythianUI.C_MUTED)
	root.add_child(status)
	battle=load("res://scripts/network/BattleClient.gd").new()
	add_child(battle)
	battle.start()
	battle.connect("state_changed",self,"_battle_state_changed")
	battle.connect("error",self,"_network_error")
	clips=load("res://scripts/network/ClipClient.gd").new()
	add_child(clips)
	clips.connect("upload_finished",self,"_clip_upload_finished")
	Rhythian.connect("auth_changed",self,"_auth_changed")
	Rhythian.connect("profile_updated",self,"_refresh_page")
	Rhythian.connect("maps_updated",self,"_refresh_page")
	Rhythian.connect("map_downloaded",self,"_map_downloaded")
	Rhythian.connect("connection_checked",self,"_connection_checked")
	show_page("home",true)

func _process(delta:float):
	if not visible:
		return
	global_refresh_accum+=delta
	direct_refresh_accum+=delta
	if selected_page=="global-chat" and global_refresh_accum>=10.0:
		global_refresh_accum=0.0
		if get_focus_owner()==null or not (get_focus_owner() is LineEdit):
			_refresh_global_chat_silent()
	if selected_page=="messages" and chat_handle!="" and direct_refresh_accum>=8.0:
		direct_refresh_accum=0.0
		if get_focus_owner()==null or not (get_focus_owner() is LineEdit):
			_refresh_direct_silent()

func open_page(page:String):
	if page=="":
		return
	visible=true
	show_page(page,false)

func close_page():
	visible=false
	page_epoch+=1
	render_scheduled=false

func _refresh_page(_a=null,_b=null):
	if not visible:
		page_dirty=true
		return
	show_page(selected_page,true)

func _auth_changed():
	api_cache.clear()
	api_cache_time.clear()
	map_page=0
	map_search=""
	profile_handle=""
	chat_handle=""
	search_query=""
	_refresh_page()

func _battle_state_changed(_data):
	if visible and selected_page=="battles":
		show_page("battles",true)

func _network_error(message:String):
	if status!=null:
		status.text=message
	if visible and selected_page=="battles":
		show_page("battles",true)

func _connection_checked(web_ok:bool,db_ok:bool):
	if visible and selected_page=="home":
		status.text="Internet: %s · Rhythians API: %s · Database: %s" % ["connected" if web_ok else "offline","online" if web_ok else "unavailable","connected" if db_ok else "unavailable"]

func _load_settings():
	var file=File.new()
	if not file.file_exists(Globals.p(SETTINGS_FILE)):
		return
	if file.open(Globals.p(SETTINGS_FILE),File.READ)!=OK:
		return
	var parsed=JSON.parse(file.get_as_text())
	file.close()
	if parsed.error==OK and typeof(parsed.result)==TYPE_DICTIONARY:
		spin_enabled=bool(parsed.result.get("spinEnabled",false))

func _save_settings():
	var file=File.new()
	if file.open(Globals.p(SETTINGS_FILE),File.WRITE)!=OK:
		return
	file.store_string(JSON.print({"spinEnabled":spin_enabled}))
	file.close()

func _clear():
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status.text=""

func _panel(name:String,text:String="") -> VBoxContainer:
	var panel=RhythianUI.make_panel(20,20)
	var box=RhythianUI.vbox(8)
	panel.add_child(box)
	box.add_child(RhythianUI.label(name,19,RhythianUI.C_WHITE,1))
	if text!="":
		var body=RhythianUI.label(text,13,RhythianUI.C_MUTED)
		body.autowrap=true
		box.add_child(body)
	content.add_child(panel)
	return box

func _button(parent:Container,text:String,primary:bool=false) -> Button:
	var button=RhythianUI.accent_button(text) if primary else RhythianUI.ghost_button(text)
	parent.add_child(button)
	return button

func _line(parent:Container,placeholder:String,initial:String="") -> LineEdit:
	var field=LineEdit.new()
	field.placeholder_text=placeholder
	field.text=initial
	field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	RhythianUI.input_style(field)
	parent.add_child(field)
	return field

func show_page(page:String,force:bool=true):
	if page=="":
		page="home"
	if not force and page==selected_page and not page_dirty:
		return
	selected_page=page
	page_dirty=false
	page_epoch+=1
	pending_page=page
	global_refresh_accum=0.0
	direct_refresh_accum=0.0
	if render_scheduled:
		return
	render_scheduled=true
	call_deferred("_render_pending_page")

func _render_pending_page():
	render_scheduled=false
	if not visible:
		page_dirty=true
		return
	var page=pending_page
	if page!=selected_page:
		return
	_clear()
	match page:
		"home": _home()
		"maps": _maps()
		"daily": _daily()
		"path": _path()
		"challenge": _challenge()
		"online": _online()
		"leaderboards": _leaderboards()
		"battles": _battles()
		"clips": _clips()
		"search": _search()
		"messages": _messages()
		"global-chat": _global_chat()
		"wiki": _wiki()
		"rules": _rules()
		"community": _community()
		"account": _account()
		"profile": _profile(profile_handle if profile_handle!="" else Rhythian.username)
		_: _home()

func _page_is_current(page:String,epoch:int) -> bool:
	return visible and selected_page==page and page_epoch==epoch

func _cache_key(page:String,extra:Dictionary) -> String:
	var keys=extra.keys()
	keys.sort()
	var key=page
	for k in keys:
		key+="|"+str(k)+"="+str(extra[k])
	return key

func _cache_ttl(page:String) -> int:
	match page:
		"wiki","rules": return 300000
		"daily","path","challenge": return 60000
		"leaderboards": return 30000
		"online","clips","profile","search": return 15000
		"messages","global-chat": return 0
		_: return 10000

func _invalidate_cache(page:String):
	var remove=[]
	for key in api_cache.keys():
		if str(key).begins_with(page+"|") or str(key)==page:
			remove.append(key)
	for key in remove:
		api_cache.erase(key)
		api_cache_time.erase(key)

func _api_page(page:String,extra:Dictionary={},force:bool=false) -> Dictionary:
	var key=_cache_key(page,extra)
	var ttl=_cache_ttl(page)
	var now=OS.get_ticks_msec()
	if not force and ttl>0 and api_cache.has(key) and now-int(api_cache_time.get(key,0))<ttl:
		yield(get_tree(),"idle_frame")
		var cached=api_cache[key].duplicate(true)
		cached["ok"]=true
		return cached
	var query="page="+page
	var keys=extra.keys()
	keys.sort()
	for k in keys:
		query+="&"+str(k).http_escape()+"="+str(extra[k]).http_escape()
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_GET,"/api/rhythkit/portal?"+query,null,true,35.0),"completed")
	if not result.get("ok",false):
		return {"ok":false,"message":Rhythian._http_error_message(result,page)}
	var json=result.get("json",{})
	if typeof(json)!=TYPE_DICTIONARY:
		return {"ok":false,"message":"The Rhythians API returned an invalid response."}
	api_cache[key]=json.duplicate(true)
	api_cache_time[key]=OS.get_ticks_msec()
	json["ok"]=true
	return json

func _home():
	title_label.text="Home"
	var account=_panel("Account","%s · %d RHP" % [Rhythian.username,int(Rhythian.profile.get("rhp",0))] if Rhythian.logged_in else "Not signed in")
	var row=RhythianUI.hbox(10)
	account.add_child(row)
	if Rhythian.logged_in:
		var refresh=_button(row,"Refresh account")
		refresh.connect("pressed",Rhythian,"fetch_profile")
		var profile=_button(row,"Open profile")
		profile.connect("pressed",self,"open_page",["profile"])
		var logout=_button(row,"Log out")
		logout.connect("pressed",Rhythian,"logout")
	else:
		var login=_button(row,"Sign in with Rhythians",true)
		login.connect("pressed",self,"_login")
	var score=_panel("Score pools","RPL is used when Spin is disabled. RPS is used when Spin is enabled. RPV is not supported in this client. RBP remains battle-only.")
	var totals=_mode_totals()
	var points=RhythianUI.hbox(22)
	score.add_child(points)
	points.add_child(RhythianUI.label("RPL %d" % totals["rpl"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RPS %d" % totals["rps"],18,RhythianUI.C_WHITE,1))
	points.add_child(RhythianUI.label("RHP %d" % int(Rhythian.profile.get("rhp",0)),18,RhythianUI.C_WHITE,1))
	var actions=_panel("Quick actions")
	var ar=RhythianUI.hbox(10)
	actions.add_child(ar)
	for pair in [["Maps","maps"],["Daily","daily"],["Path","path"],["Challenge","challenge"],["Battles","battles"],["Clips","clips"],["Global Chat","global-chat"],["Search","search"]]:
		var b=_button(ar,pair[0],pair[1]=="battles")
		b.connect("pressed",self,"open_page",[pair[1]])
	var now=OS.get_ticks_msec()
	if now-last_connection_check_msec>30000:
		last_connection_check_msec=now
		Rhythian.check_connection()
func _maps():
	title_label.text="Maps"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Sign in to synchronize your ranks and the complete Rhythians map catalog.")
		var login=_button(need,"Sign in with Rhythians",true)
		login.connect("pressed",self,"_login")
		return
	var rhp=int(Rhythian.profile.get("rhp",0))
	var rank=Rhythian.get_rank_info(rhp)
	var banner=_panel("Current rank","%s · %d RHP · the catalog below is synchronized from the current Rhythians Maps page." % [str(rank.name),rhp])
	var controls=RhythianUI.hbox(8)
	banner.add_child(controls)
	var refresh=_button(controls,"Refresh maps",true)
	refresh.disabled=Rhythian.catalog_loading
	refresh.connect("pressed",self,"_refresh_maps")
	var check=_button(controls,"Check scores")
	check.connect("pressed",self,"_check_all_maps")
	var search_row=RhythianUI.hbox(8)
	banner.add_child(search_row)
	var search=_line(search_row,"Search title, artist, mapper, or rank",map_search)
	var search_button=_button(search_row,"Search")
	search_button.connect("pressed",self,"_set_map_search",[search])
	if map_search!="":
		var clear=_button(search_row,"Clear")
		clear.connect("pressed",self,"_clear_map_search")
	if Rhythian.maps_cache.empty():
		if not Rhythian.catalog_loading:
			Rhythian.call_deferred("fetch_maps")
		_panel("Map catalog",Rhythian.maps_error if Rhythian.maps_error!="" else "Loading the current Rhythians map catalog…")
		return
	var maps=_filtered_maps()
	var page_size=24
	var max_page=max(0,int(ceil(maps.size()/float(page_size)))-1)
	map_page=int(clamp(map_page,0,max_page))
	var start=map_page*page_size
	var finish=min(start+page_size,maps.size())
	var summary="%d current maps synced" % Rhythian.maps_cache.size()
	if map_search!="":
		summary+=" · %d matches" % maps.size()
	if Rhythian.catalog_loading:
		summary+=" · refreshing in background"
	var pager=_panel("Map catalog",summary+" · page %d of %d" % [map_page+1,max_page+1])
	var page_row=RhythianUI.hbox(8)
	pager.add_child(page_row)
	var prev=_button(page_row,"Previous")
	prev.disabled=map_page<=0
	prev.connect("pressed",self,"_map_page_change",[-1])
	var next=_button(page_row,"Next")
	next.disabled=map_page>=max_page
	next.connect("pressed",self,"_map_page_change",[1])
	if maps.empty():
		_panel("No maps found","Try a different search.")
		return
	for i in range(start,finish):
		var map=maps[i]
		var rating=Rhythian.get_map_rating(map)
		var rank_name=str(map.get("rankName","Unranked"))
		var details="%.2f rating · %s" % [rating,rank_name]
		var challenge_level=map.get("challengeLevel",null)
		var placement=str(map.get("challengePlacement",""))
		if challenge_level!=null:
			details+=" · %s level %s" % [_challenge_name(placement),str(challenge_level)]
		elif str(map.get("submissionType",""))=="challenge":
			details+=" · %s challenge" % _challenge_name(placement)
		if int(map.get("noteCount",0))>0:
			details+=" · %d notes" % int(map.get("noteCount",0))
		if int(map.get("length",0))>0:
			details+=" · "+Rhythian.format_length(map.get("length",0))
		var completion=map.get("completion",{})
		if typeof(completion)==TYPE_DICTIONARY and bool(completion.get("passed",false)):
			details+=" · Passed"
		var rewards=map.get("maxRewards",null)
		if typeof(rewards)==TYPE_DICTIONARY:
			details+=" · max RPL %d / RPS %d" % [int(rewards.get("lock",0)),int(rewards.get("spin",0))]
		var row=_panel(str(map.get("title","Unknown map")),details)
		row.add_child(RhythianUI.label("%s · mapped by %s" % [str(map.get("artist","Unknown Artist")),str(map.get("mapper",map.get("mapperName","Unknown")))],13,RhythianUI.C_MUTED))
		var action=_button(row,"Play" if Rhythian.is_map_playable(str(map.get("id",""))) else "Download",true)
		action.connect("pressed",self,"_map_action",[map])
func _filtered_maps() -> Array:
	if map_search=="":
		return Rhythian.maps_cache
	var q=map_search.to_lower()
	var filtered=[]
	for map in Rhythian.maps_cache:
		if typeof(map)!=TYPE_DICTIONARY:
			continue
		var text=(str(map.get("title",""))+" "+str(map.get("artist",""))+" "+str(map.get("mapper",map.get("mapperName","")))+" "+str(map.get("rankName",""))).to_lower()
		if text.find(q)!=-1:
			filtered.append(map)
	return filtered

func _set_map_search(field:LineEdit):
	map_search=field.text.strip_edges()
	map_page=0
	show_page("maps",true)

func _clear_map_search():
	map_search=""
	map_page=0
	show_page("maps",true)

func _refresh_maps():
	if Rhythian.catalog_loading:
		status.text="The current map catalog is already refreshing."
		return
	status.text="Refreshing the current Rhythians map catalog…"
	Rhythian.fetch_maps()

func _challenge_name(value:String) -> String:
	match value:
		"main": return "Main Challenge"
		"jumps": return "Jumps"
		"stream": return "Stream"
		"tech": return "Tech"
		"off_grid": return "Off-Grid"
		"vibro": return "Vibro"
		_: return "Challenge"

func _map_page_change(delta:int):
	map_page=max(0,map_page+delta)
	show_page("maps",true)
func _map_action(map:Dictionary):
	var id=str(map.get("id",""))
	if id=="":
		status.text="This map has no Rhythians map id."
		return
	if Rhythian.is_map_playable(id):
		var song=Rhythian.get_song_for_map_id(id)
		if song==null:
			status.text="The downloaded map could not be loaded."
			return
		Rhythia.select_song(song)
		close_page()
		var sidebar=get_tree().current_scene.get_node_or_null("Sidebar")
		if sidebar!=null and sidebar.has_method("to_play"): sidebar.to_play()
		return
	status.text="Downloading %s…" % str(map.get("title","map"))
	Rhythian.download_map(map)

func _map_downloaded(_id:String,success:bool,message:String):
	if status!=null:
		status.text="Map downloaded into the Play library." if success else message
	if visible and (selected_page=="maps" or selected_page=="challenge"):
		show_page(selected_page,true)
func _check_all_maps():
	status.text="Checking your Rhythians scores…"
	var state=Rhythian.check_all_maps()
	if state is GDScriptFunctionState:
		state.connect("completed",self,"_check_all_maps_done")
	else:
		_check_all_maps_done(state)

func _check_all_maps_done(result):
	if typeof(result)==TYPE_DICTIONARY and result.has("error"):
		status.text=str(result.error)
	else:
		status.text="Score check complete."
func _daily():
	title_label.text="Daily"
	var epoch=page_epoch
	var data=yield(_api_page("daily"),"completed")
	if not _page_is_current("daily",epoch):
		return
	if not data.get("ok",false):
		_panel("Daily unavailable",data.get("message","Could not load daily."))
		return
	var daily=data.get("daily",{})
	var card=_panel("Today's map","%s · %s · %.2f rating" % [str(daily.get("title","Daily map")),str(data.get("formattedDate","")),float(daily.get("starRating",0))])
	card.add_child(RhythianUI.label("%s · %s" % [str(daily.get("artist","")),str(daily.get("mapperName",""))],14))
	card.add_child(RhythianUI.label("Reward: %d RHP at 100%% · streak %d" % [int(daily.get("reward",0)),int(data.get("streak",0))],14,RhythianUI.C_ACCENT2,1))
	var beat=data.get("beat",null)
	if beat!=null:
		card.add_child(RhythianUI.label("Completed · %s%% · %d points · %d misses" % [str(beat.get("accuracy",0)),int(beat.get("points",0)),int(beat.get("misses",0))],14))
	else:
		card.add_child(RhythianUI.label("Not completed yet",14))
	if str(daily.get("downloadUrl",""))!="":
		var play=_button(card,"Download / Play daily map",true)
		play.connect("pressed",RhythianUI,"open_url",[str(daily.get("downloadUrl"))])
func _path():
	title_label.text="Path"
	var epoch=page_epoch
	var data=yield(_api_page("path"),"completed")
	if not _page_is_current("path",epoch):
		return
	if not data.get("ok",false):
		_panel("Path unavailable",data.get("message","Could not load path."))
		return
	var path=data.get("path",{})
	_panel("Seasonal Rhythian Path","Season %s · ends %s" % [str(path.get("season",{}).get("seasonNumber","")),str(path.get("season",{}).get("endsAt",""))])
	for rank in path.get("ranks",[]):
		var box=_panel(str(rank.get("name","Rank")),"Rank %d" % int(rank.get("index",0)+1))
		var map=rank.get("map",null)
		if map!=null:
			box.add_child(RhythianUI.label("%s · %.2f rating" % [str(map.get("title","Map")),float(map.get("rating",0))],14))
			box.add_child(RhythianUI.label("%s" % ("Completed" if bool(map.get("completed",false)) else "Not completed"),14,RhythianUI.C_ACCENT2 if bool(map.get("completed",false)) else RhythianUI.C_MUTED,1))
func _challenge():
	title_label.text="Challenge"
	var epoch=page_epoch
	var data=yield(_api_page("challenge"),"completed")
	if not _page_is_current("challenge",epoch):
		return
	if not data.get("ok",false):
		_panel("Challenge unavailable",data.get("message","Could not load challenge."))
		return
	_panel("Challenge progression","Current level %d" % int(data.get("level",0)))
	var maps=data.get("maps",[])
	var limit=min(60,maps.size())
	for i in range(limit):
		var map=maps[i]
		var level=map.get("level",map.get("challengeLevel","?"))
		var complete=bool(map.get("completed",map.get("passed",false)))
		var box=_panel(str(map.get("title","Challenge map")),"Level %s · %s" % [str(level),"Passed" if complete else "Available"])
		box.add_child(RhythianUI.label("%s · %.2f rating" % [str(map.get("artist","Unknown Artist")),Rhythian.get_map_rating(map)],13,RhythianUI.C_MUTED))
		var id=str(map.get("id",""))
		if id!="":
			var action=_button(box,"Play" if Rhythian.is_map_playable(id) else "Download",true)
			action.connect("pressed",self,"_map_action",[map])
func _online():
	title_label.text="Online"
	var epoch=page_epoch
	var data=yield(_api_page("online"),"completed")
	if not _page_is_current("online",epoch):
		return
	if not data.get("ok",false):
		_panel("Online unavailable",data.get("message","Could not load online users."))
		return
	var users=data.get("users",[])
	_panel("Who's online","%d users currently online · showing up to 40" % users.size())
	for i in range(min(40,users.size())):
		var user=users[i]
		var row=_panel(str(user.get("displayName",user.get("username","User"))),"%d RHP · #%s global · Level %s" % [int(user.get("rhp",0)),str(user.get("globalPosition","-")),str(user.get("challengeLevel",0))])
		var open=_button(row,"View profile")
		open.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
		var message=_button(row,"Message")
		message.connect("pressed",self,"open_message_handle",[str(user.get("profileHandle",""))])
func _leaderboards():
	title_label.text="Leaderboards"
	var epoch=page_epoch
	var data=yield(_api_page("leaderboards"),"completed")
	if not _page_is_current("leaderboards",epoch):
		return
	if not data.get("ok",false):
		_panel("Leaderboards unavailable",data.get("message","Could not load leaderboards."))
		return
	var rhp=data.get("rhp",[])
	var board=_panel("RHP global","Top 30 Rhythians")
	for i in range(min(30,rhp.size())):
		var user=rhp[i]
		var row=_panel("#%d · %s · %d RHP" % [int(user.get("position",i+1)),str(user.get("displayName",user.get("username",""))),int(user.get("rhp",0))])
		var open=_button(row,"Profile")
		open.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
	var modes=data.get("modes",{})
	for mode_name in ["lock","spin"]:
		var mode_box=_panel(mode_name.to_upper(),"Top 15 mode leaderboard")
		var entries=modes.get(mode_name,[])
		for i in range(min(15,entries.size())):
			mode_box.add_child(RhythianUI.label("#%d %s" % [i+1,str(entries[i].get("username",entries[i].get("displayName","Player")))],13))
func _battles():
	title_label.text="Battles"
	if not Rhythian.logged_in:
		var need=_panel("Sign in required","Battles use your Rhythians installation account.")
		var login=_button(need,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var connection=_panel("Connection","HTTPS API + live database state. Connection failures are shown here.")
	var check=_button(connection,"Check connection")
	check.connect("pressed",self,"_check_connection")
	if battle.match_id!="": _battle_match_view(); return
	if battle.lobby_id!="": _render_lobby(_panel("Active lobby")); return
	var queue=_panel("Find a battle","Ranked battles award RBP only. Casual battles do not modify RBP.")
	var row=RhythianUI.hbox(10)
	queue.add_child(row)
	var modes=RhythianUI.option_button(["1v1","2v2","3v3","15v15"],0,100)
	row.add_child(modes)
	modes.connect("item_selected",self,"_battle_mode")
	var kinds=RhythianUI.option_button(["Ranked","Casual"],0,100)
	row.add_child(kinds)
	kinds.connect("item_selected",self,"_battle_type")
	var find=_button(row,"Find opponent",true)
	find.connect("pressed",self,"_queue_battle")
	var lobby=_panel("Lobbies","Live lobby list, ready state, map votes and chat.")
	var create_row=RhythianUI.hbox(10)
	lobby.add_child(create_row)
	var name=_line(create_row,"Lobby name")
	var create=_button(create_row,"Create lobby",true)
	create.connect("pressed",self,"_create_lobby",[name])
	var refresh=_button(lobby,"Refresh")
	refresh.connect("pressed",self,"_refresh_lobbies")
	_refresh_lobbies()

func _battle_match_view():
	var data=battle.match_data
	var match_info=data.get("match",{})
	var mode=str(match_info.get("mode","1v1")).split(":")[0]
	var panel=_panel("Battle %s" % mode,"Status: %s · %s" % [str(match_info.get("status","unknown")),str(match_info.get("matchType","casual"))])
	for player in data.get("players",[]): panel.add_child(RhythianUI.label("Team %d · %s · %s" % [int(player.get("team",0)),str(player.get("displayName",player.get("username","Player"))),"—" if player.get("accuracy",null)==null else "%.2f%%" % float(player.get("accuracy"))],14))
	var map=data.get("map",null)
	if map!=null: panel.add_child(RhythianUI.label("Map: %s" % str(map.get("title","Unknown")),16,RhythianUI.C_ACCENT,1))
	var actions=RhythianUI.hbox(10)
	panel.add_child(actions)
	if str(match_info.get("status",""))=="map_vote":
		for option in data.get("options",[]):
			var vote=_button(actions,str(option.get("title","Map")))
			vote.connect("pressed",self,"_vote_map",[str(option.get("mapId",""))])
	else:
		var score=_button(actions,"Check score",true)
		score.connect("pressed",self,"_check_battle_score")
		var reconnect=_button(actions,"Reconnect")
		reconnect.connect("pressed",self,"_reconnect_battle")
	var leave=_button(actions,"Forfeit")
	leave.connect("pressed",self,"_forfeit_battle")
	if str(match_info.get("status",""))=="finished":
		var back=_button(actions,"Return")
		back.connect("pressed",self,"_return_battles")

func _render_lobby(parent:VBoxContainer):
	var lobby=battle.lobby_data.get("lobby",battle.lobby_data)
	parent.add_child(RhythianUI.label("%s · %s · %s" % [str(lobby.get("name","Lobby")),str(lobby.get("mode","1v1")),str(lobby.get("matchType","casual"))],16))
	for member in battle.lobby_data.get("members",[]): parent.add_child(RhythianUI.label("%s · %s" % [str(member.get("displayName",member.get("username","User"))),"Ready" if bool(member.get("isReady",false)) else "Not ready"],14))
	var actions=RhythianUI.hbox(8)
	parent.add_child(actions)
	var ready=_button(actions,"Ready")
	ready.connect("pressed",self,"_lobby_action",["ready",{}])
	var leave=_button(actions,"Leave")
	leave.connect("pressed",self,"_leave_lobby")
	var start=_button(actions,"Start match",true)
	start.connect("pressed",self,"_lobby_action",["start",{}])
	var maps=_button(actions,"Vote random map")
	maps.connect("pressed",self,"_lobby_action",["vote",{"mapId":"random"}])
	var msg=_line(parent,"Lobby chat message")
	var send=_button(parent,"Send lobby message")
	send.connect("pressed",self,"_lobby_action",["message",{"content":""},msg])
	for entry in battle.lobby_data.get("messages",[]): parent.add_child(RhythianUI.label("%s: %s" % [str(entry.get("username","User")),str(entry.get("content",""))],13))

func _clips():
	title_label.text="Clips"
	var head=_panel("Community clips","Watch approved clips, search by song, and submit your own.")
	var row=RhythianUI.hbox(10)
	head.add_child(row)
	var search=_line(row,"Search by song",search_query)
	var go=_button(row,"Search",true)
	go.connect("pressed",self,"_search_clips",[search])
	var upload=_button(row,"Submit clip")
	upload.connect("pressed",self,"_open_clip_submit")
	var epoch=page_epoch
	var data=yield(_api_page("clips",{"song":search_query}),"completed")
	if not _page_is_current("clips",epoch):
		return
	if not data.get("ok",false):
		_panel("Clips unavailable",data.get("message","Could not load clips."))
		return
	for clip in data.get("clips",[]):
		var panel=_panel(str(clip.get("title","Clip")),"%s · %s · %s" % [str(clip.get("uploader",{}).get("displayName",clip.get("uploader",{}).get("username",""))),str(clip.get("songName","")),str(clip.get("cameraMode",""))])
		var watch=_button(panel,"Watch clip",true)
		watch.connect("pressed",self,"_watch_clip",[clip])
		var open_profile=_button(panel,"Creator profile")
		open_profile.connect("pressed",self,"open_profile_handle",[str(clip.get("uploader",{}).get("profileHandle",""))])
func _watch_clip(clip:Dictionary):
	var url=str(clip.get("videoUrl",""))
	if url=="":
		status.text="This clip has no playable video URL."
		return
	OS.shell_open(url)
	status.text="Opening clip video. The current Godot 3 client does not provide an embedded MP4/WebM/MOV browser codec, so the signed video is opened by the system player."

func _open_clip_submit():
	var panel=_panel("Submit a clip","Choose a local MP4, WebM or MOV and submit it for review.")
	var row=RhythianUI.hbox(8)
	panel.add_child(row)
	var title=_line(row,"Title")
	var song=_line(row,"Song / map")
	var path=_line(row,"Absolute path to video")
	var mode=RhythianUI.option_button(["lock","spin","vr"],0,100)
	row.add_child(mode)
	var submit=_button(panel,"Upload and submit",true)
	submit.connect("pressed",self,"_submit_clip_fields",[title,song,path,mode])

func _search_clips(field:LineEdit):
	search_query=field.text.strip_edges()
	_invalidate_cache("clips")
	show_page("clips",true)
func _submit_clip_fields(title:LineEdit,song:LineEdit,path:LineEdit,mode:OptionButton):
	var epoch=page_epoch
	status.text="Uploading clip..."
	var result=yield(clips.submit(path.text,title.text,song.text,"",mode.get_item_text(mode.selected)),"completed")
	if not _page_is_current("clips",epoch):
		return
	status.text=str(result.get("message","Clip submission finished."))
	if result.get("ok",false):
		_invalidate_cache("clips")
		show_page("clips",true)
func _clip_upload_finished(_success:bool,message:String):
	if visible and selected_page=="clips":
		status.text=message
func _search():
	title_label.text="Search users"
	var panel=_panel("User search","Search usernames, display names, or profile handles.")
	var row=RhythianUI.hbox(8)
	panel.add_child(row)
	var field=_line(row,"Search users",search_query)
	var go=_button(row,"Search",true)
	go.connect("pressed",self,"_run_user_search",[field])
	if search_query!="": _render_user_search(search_query)

func _run_user_search(field:LineEdit):
	search_query=field.text.strip_edges()
	_invalidate_cache("search")
	show_page("search",true)
func _render_user_search(query:String):
	var epoch=page_epoch
	var data=yield(_api_page("search",{"q":query}),"completed")
	if not _page_is_current("search",epoch):
		return
	if not data.get("ok",false):
		_panel("Search failed",data.get("message","Could not search users."))
		return
	for user in data.get("users",[]):
		var row=_panel(str(user.get("displayName",user.get("username","User"))),"@%s · %d RHP · %s" % [str(user.get("profileHandle","")),int(user.get("rhp",0)),"Online" if bool(user.get("online",false)) else "Offline"])
		var profile=_button(row,"Profile")
		profile.connect("pressed",self,"open_profile_handle",[str(user.get("profileHandle",""))])
		var msg=_button(row,"Message")
		msg.connect("pressed",self,"open_message_handle",[str(user.get("profileHandle",""))])
func _profile(handle:String):
	title_label.text="Profile"
	var epoch=page_epoch
	var data=yield(_api_page("profile",{"handle":handle}),"completed")
	if not _page_is_current("profile",epoch):
		return
	if not data.get("ok",false):
		_panel("Profile unavailable",data.get("message","Could not load profile."))
		return
	var p=data.get("profile",{})
	var main=_panel(str(p.get("displayName",p.get("username","User"))),"@%s · %s · %d RHP" % [str(p.get("profileHandle","")),str(p.get("title","Rhythian")),int(p.get("rhp",0))])
	main.add_child(RhythianUI.label("Rank: %s %s · Global #%s · Challenge Level %s · %s" % [str(p.get("rank",{}).get("name","")),str(p.get("rank",{}).get("tier","")),str(p.get("globalRank","-")),str(p.get("challengeLevel",0)),"Online" if bool(p.get("online",false)) else "Offline"],14))
	main.add_child(RhythianUI.label("RPL %d · RPS %d" % [int(p.get("modes",{}).get("rpl",0)),int(p.get("modes",{}).get("rps",0))],14))
	if str(p.get("bio",""))!="":
		main.add_child(RhythianUI.label(str(p.get("bio","")),14))
	var actions=RhythianUI.hbox(8)
	main.add_child(actions)
	if not bool(p.get("isOwnProfile",false)):
		var msg=_button(actions,"Message",true)
		msg.connect("pressed",self,"open_message_handle",[str(p.get("profileHandle",""))])
		var battle_btn=_button(actions,"Battle")
		battle_btn.connect("pressed",self,"open_page",["battles"])
	var clips_panel=_panel("Approved clips","%d clips" % p.get("clips",[]).size())
	for clip in p.get("clips",[]):
		var b=_button(clips_panel,str(clip.get("title","Clip")))
		b.connect("pressed",self,"_watch_clip",[clip])
func open_profile_handle(handle:String):
	profile_handle=handle
	show_page("profile",true)
func open_message_handle(handle:String):
	chat_handle=handle
	show_page("messages")

func _messages():
	title_label.text="Messages"
	if chat_handle==":":
		chat_handle=""
	if chat_handle=="":
		var panel=_panel("Direct messages","Choose a user from Search or Online to start a conversation.")
		var search=_button(panel,"Find a user",true)
		search.connect("pressed",self,"open_page",["search"])
		return
	var epoch=page_epoch
	var data=yield(_api_page("messages",{"user":chat_handle}),"completed")
	if not _page_is_current("messages",epoch):
		return
	if not data.get("ok",false):
		_panel("Messages unavailable",data.get("message","Could not load conversation."))
		return
	var target=data.get("target",{})
	_panel("Chat with %s" % str(target.get("displayName",target.get("username","User"))))
	var messages=data.get("messages",[])
	var start=max(0,messages.size()-50)
	for i in range(start,messages.size()):
		var m=messages[i]
		content.add_child(RhythianUI.label("%s: %s" % [str(m.get("sender",{}).get("displayName",m.get("sender",{}).get("username","User"))),str(m.get("content",""))],14))
	var row=RhythianUI.hbox(8)
	content.add_child(row)
	var input=_line(row,"Message")
	var send=_button(row,"Send",true)
	send.connect("pressed",self,"_send_direct",[target,input])
func _refresh_direct_silent():
	if chat_handle=="" or not visible or selected_page!="messages":
		return
	_invalidate_cache("messages")
	show_page("messages",true)
func _send_direct(target:Dictionary,input:LineEdit):
	if input.text.strip_edges()=="":
		return
	var epoch=page_epoch
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/rhythkit/portal",{"action":"direct-send","userId":str(target.get("id","")),"content":input.text.strip_edges()},true,25.0),"completed")
	if not _page_is_current("messages",epoch):
		return
	if not result.get("ok",false):
		status.text=Rhythian._http_error_message(result,"message send")
		return
	input.text=""
	_invalidate_cache("messages")
	show_page("messages",true)
func _global_chat():
	title_label.text="Global Chat"
	var epoch=page_epoch
	var data=yield(_api_page("global-chat"),"completed")
	if not _page_is_current("global-chat",epoch):
		return
	if not data.get("ok",false):
		_panel("Global chat unavailable",data.get("message","Could not load global chat."))
		return
	_panel("Global Rhythian Chat","All logged-in Rhythians share this channel. %d users online." % int(data.get("onlineCount",0)))
	var messages=data.get("messages",[])
	var start=max(0,messages.size()-50)
	for i in range(start,messages.size()):
		var m=messages[i]
		content.add_child(RhythianUI.label("%s: %s" % [str(m.get("sender",{}).get("displayName",m.get("sender",{}).get("username","User"))),str(m.get("content",""))],14))
	var row=RhythianUI.hbox(8)
	content.add_child(row)
	var input=_line(row,"Talk to everyone online")
	var send=_button(row,"Send",true)
	send.connect("pressed",self,"_send_global",[input])
func _refresh_global_chat_silent():
	if not visible or selected_page!="global-chat":
		return
	_invalidate_cache("global-chat")
	show_page("global-chat",true)
func _send_global(input:LineEdit):
	if input.text.strip_edges()=="":
		return
	var epoch=page_epoch
	var result=yield(Rhythian._api_request(HTTPClient.METHOD_POST,"/api/rhythkit/portal",{"action":"global-send","content":input.text.strip_edges()},true,25.0),"completed")
	if not _page_is_current("global-chat",epoch):
		return
	if not result.get("ok",false):
		status.text=Rhythian._http_error_message(result,"global chat")
		return
	input.text=""
	_invalidate_cache("global-chat")
	show_page("global-chat",true)
func _wiki():
	title_label.text="Wiki"
	var epoch=page_epoch
	var data=yield(_api_page("wiki"),"completed")
	if not _page_is_current("wiki",epoch):
		return
	if not data.get("ok",false):
		_panel("Wiki unavailable",data.get("message","Could not load wiki."))
		return
	var articles=data.get("articles",[])
	_panel("Wiki","%d published knowledge articles · summaries are rendered in-client to keep tab switching fast." % articles.size())
	for i in range(min(40,articles.size())):
		var article=articles[i]
		var box=_panel(str(article.get("title","Article")),str(article.get("description",article.get("slug",""))))
		var slug=str(article.get("slug",""))
		if slug!="":
			var open=_button(box,"Open article")
			open.connect("pressed",RhythianUI,"open_url",[BASE_URL+"/knowledge/"+slug])
func _rules():
	title_label.text="Rules"
	var epoch=page_epoch
	var data=yield(_api_page("rules"),"completed")
	if not _page_is_current("rules",epoch):
		return
	if not data.get("ok",false):
		_panel("Rules unavailable",data.get("message","Could not load rules."))
		return
	var rules=data.get("rules",[])
	for i in range(min(40,rules.size())):
		var rule=rules[i]
		var text=str(rule.get("description",""))
		var body=str(rule.get("content",""))
		if body!="" and body!=text:
			if body.length()>1400:
				body=body.substr(0,1400)+"…"
			text+=("\n" if text!="" else "")+body
		_panel(str(rule.get("title","Rule")),text)
func _community():
	title_label.text="Community Settings"
	var mode=_panel("Score mode","RPL is used when Spin is not selected. RPS is used when Spin is selected. RPV is not supported by this client.")
	var spin=RhythianUI.check_button("Spin mode",spin_enabled)
	spin.connect("toggled",self,"_spin_toggled")
	mode.add_child(spin)

func _account():
	title_label.text="Account"
	if not Rhythian.logged_in:
		var panel=_panel("Not signed in","Use the same Rhythians account as the website.")
		var login=_button(panel,"Sign in",true)
		login.connect("pressed",self,"_login")
		return
	var panel=_panel(Rhythian.username,"%d RHP · browser account connected" % int(Rhythian.profile.get("rhp",0)))
	var modes=_mode_totals()
	panel.add_child(RhythianUI.label("RPL %d · RPS %d" % [modes["rpl"],modes["rps"]],14,RhythianUI.C_MUTED))
	var row=RhythianUI.hbox(8)
	panel.add_child(row)
	var refresh=_button(row,"Refresh account")
	refresh.connect("pressed",Rhythian,"fetch_profile")
	var profile=_button(row,"Open profile",true)
	profile.connect("pressed",self,"open_profile_handle",[Rhythian.username])
	var logout=_button(row,"Log out")
	logout.connect("pressed",Rhythian,"logout")
func _login():
	if OS.has_feature("HTML5"):
		WebPortal.request_signin()
		return
	_clear()
	title_label.text="Sign in"
	var p=_panel("Waiting for authorization","The existing Rhythians device authorization flow will open the verification page.")
	var cancel=_button(p,"Cancel")
	cancel.connect("pressed",Rhythian,"cancel_login")
	Rhythian.start_login()
func _check_connection():
	status.text="Checking connection..."
	Rhythian.check_connection()

func _battle_mode(index:int): battle_mode=["1v1","2v2","3v3","15v15"][index]
func _battle_type(index:int): battle_type="ranked" if index==0 else "casual"

func _queue_battle():
	if not Rhythian.logged_in:
		status.text="Sign in before entering battles."
		return
	var epoch=page_epoch
	var result=yield(battle.queue_match(battle_mode,battle_type),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Could not queue battle."))
		return
	battle.match_id=str(result.get("matchId",""))
	status.text="Finding opponent..."
	show_page("battles",true)
func _create_lobby(name:LineEdit):
	var lobby_name=name.text.strip_edges()
	if lobby_name=="":
		status.text="Enter a lobby name."
		return
	var epoch=page_epoch
	var result=yield(battle.create_lobby(lobby_name,battle_mode,battle_type,"regular"),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Could not create lobby."))
		return
	show_page("battles",true)
func _refresh_lobbies():
	var epoch=page_epoch
	var result=yield(battle.list_lobbies(),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Could not load lobbies."))
		return
	for lobby in result.get("lobbies",[]):
		var row=_panel(str(lobby.get("name","Lobby")),"%s · %s · %d/%d · host %s" % [str(lobby.get("mode","1v1")),str(lobby.get("matchType","casual")),int(lobby.get("playerCount",0)),int(lobby.get("maxPlayers",0)),str(lobby.get("host",""))])
		var join=_button(row,"Join")
		join.connect("pressed",self,"_join_lobby",[str(lobby.get("id",""))])
func _join_lobby(id:String):
	battle.lobby_id=id
	var epoch=page_epoch
	var result=yield(battle.lobby_action("join"),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Could not join lobby."))
	show_page("battles",true)
func _lobby_action(action:String,extra:Dictionary,field=null):
	if field!=null:
		extra["content"]=field.text.strip_edges()
	var epoch=page_epoch
	var result=yield(battle.lobby_action(action,extra),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Lobby action failed."))
	show_page("battles",true)
func _leave_lobby(): _lobby_action("leave",{})

func _vote_map(map_id:String):
	var epoch=page_epoch
	var result=yield(battle.battle_action("vote-map",{"mapId":map_id}),"completed")
	if _page_is_current("battles",epoch) and not result.get("ok",false):
		status.text=str(result.get("message","Vote failed."))
func _check_battle_score():
	var epoch=page_epoch
	var result=yield(battle.battle_action("check-score"),"completed")
	if _page_is_current("battles",epoch) and not result.get("ok",false):
		status.text=str(result.get("message","Score check failed."))
func _reconnect_battle():
	var epoch=page_epoch
	var result=yield(battle.battle_action("reconnect"),"completed")
	if _page_is_current("battles",epoch) and not result.get("ok",false):
		status.text=str(result.get("message","Reconnect failed."))
func _forfeit_battle():
	var epoch=page_epoch
	var result=yield(battle.battle_action("forfeit"),"completed")
	if not _page_is_current("battles",epoch):
		return
	if not result.get("ok",false):
		status.text=str(result.get("message","Forfeit failed."))
	else:
		_return_battles()
func _return_battles():
	battle.match_id=""
	battle.match_data={}
	show_page("battles",true)
func _mode_totals():
	var modes=Rhythian.profile.get("modes",{})
	if typeof(modes)==TYPE_DICTIONARY and (modes.has("rpl") or modes.has("rps")):
		return {"rpl":int(modes.get("rpl",0)),"rps":int(modes.get("rps",0))}
	var totals={"rpl":0,"rps":0}
	for score in Rhythian.scores_cache:
		if typeof(score)!=TYPE_DICTIONARY: continue
		if score.has("passed") and not bool(score.get("passed",false)): continue
		var explicit=str(score.get("cameraMode",score.get("gameMode",score.get("mode","")))).to_lower()
		if explicit=="vr" or bool(score.get("vr",false)) or bool(score.get("isVr",false)): continue
		var points=max(0,int(score.get("points",0)))
		if explicit=="spin" or bool(score.get("spin",false)):
			totals["rps"]+=points
		else:
			totals["rpl"]+=points
	return totals

func _spin_toggled(value:bool):
	spin_enabled=value
	_save_settings()
