extends RefCounted
## セーブ・ロード（3枠＋自動保存）。user://saves/ に JSON で置く。
const G=preload("res://game/core/g.gd")
const DIR:="user://saves/"
const SETTINGS:="user://settings.json"
const AUTO:=0

static func path(slot: int) -> String:
	return DIR+("auto.json" if slot==AUTO else "slot_%d.json"%slot)

static func save(slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data: Dictionary=G.state.to_dict()
	data.saved_at=Time.get_datetime_string_from_system(false,true)
	var f:=FileAccess.open(path(slot)+".tmp",FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(path(slot)):DirAccess.remove_absolute(path(slot))
	return DirAccess.rename_absolute(path(slot)+".tmp",path(slot))==OK

static func load_slot(slot: int) -> bool:
	if not FileAccess.file_exists(path(slot)):return false
	var data=JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	if not data is Dictionary or int(data.get("version",0))<5:
		if G.main!=null:G.main.toast("古い版の保存は読めません",Color("e0605a"))
		return false
	G.state.from_dict(migrate(data))
	return true

static func migrate(data: Dictionary) -> Dictionary:
	# 版が上がったらここで順に直す。
	return data

static func info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	if not data is Dictionary:return {}
	return {"day":int(data.get("day",1)),"chapter":int(data.get("chapter",0)),"saved_at":str(data.get("saved_at","")),"women":data.get("women",[]).size(),"monsters":data.get("monsters",[]).size(),"version":int(data.get("version",0))}

static func any() -> bool:
	for s in [AUTO,1,2,3]:
		if FileAccess.file_exists(path(s)):return true
	return false

static func latest() -> int:
	var best:=-1;var best_time:=""
	for s in [AUTO,1,2,3]:
		var i: Dictionary=info(s)
		if i.is_empty():continue
		if str(i.saved_at)>best_time:best_time=str(i.saved_at);best=s
	return best

static func load_settings() -> Dictionary:
	var d: Dictionary={"master":0.8,"sfx":0.8,"ui_scale":1.0,"battle_speed":1,"follow":true,"auto_rotate":false,"fullscreen":false}
	if FileAccess.file_exists(SETTINGS):
		var data=JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if data is Dictionary:d.merge(data,true)
	return d

static func save_settings(d: Dictionary) -> void:
	var f:=FileAccess.open(SETTINGS,FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(d,"\t"));f.close()
