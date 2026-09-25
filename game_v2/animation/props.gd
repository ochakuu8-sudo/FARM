extends RefCounted
## 付属物（武器・盾・獣の耳・尻尾・男性器）の登録。正本は content/props.json。
## 仕様は docs/素材制作テンプレート/付属物の規格.md。描画側（resource_store.bind_props）へは、ID を解いた定義を recipe.props に入れて渡す。
const PATH="res://game_v2/content/props.json"
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
## 種類ごとの既定値（素材の規格）。定義に書けば上書きできる。
const KIND_DEFAULTS:={
	"weapon":{"canvas":[128,512],"anchor":[64,384],"views":3},
	"shield":{"canvas":[256,256],"anchor":[128,128],"views":3},
	"ears":{"canvas":[256,384],"anchor":[128,128],"views":5},
	"tail":{"canvas":[256,256],"anchor":[128,16],"views":5,"sway":{"amount":0.06,"rate":0.45}},
	"groin":{"canvas":[128,256],"anchor":[64,16],"views":3,"states":["rest","erect"]},
}
## 種類ごとの既定の枠。
const KIND_SLOT:={"weapon":"weapon_r","shield":"weapon_l","ears":"ears","tail":"tail","groin":"groin"}
## 武器を隠す動作（捕まった・倒れた・牧場の姿勢）。
const WEAPON_HIDE_CLIPS:=["captured","defeated","down","down_struggle","kneel","caged","rest","pregnant_idle","work_craft","work_study"]
static var cache: Dictionary={}

static func read() -> Dictionary:
	if not cache.is_empty():return cache
	if not FileAccess.file_exists(PATH):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	cache=data if data is Dictionary else {}
	return cache

static func reload() -> void:
	cache={}

static func ids(kind: String="") -> Array:
	var out: Array=[]
	for id in read():
		if str(id).begins_with("_"):continue
		if kind=="" or str(read()[id].get("kind",""))==kind:out.append(id)
	out.sort()
	return out

## ID から描画用の定義（既定値を足したもの）。無い ID は空。
static func resolve(id: String) -> Dictionary:
	var entry=read().get(id,null)
	if not entry is Dictionary:return {}
	var def: Dictionary=KIND_DEFAULTS.get(str(entry.get("kind","")),{}).duplicate(true)
	def.merge(entry.duplicate(true),true)
	def.id=id
	return def

## {枠名: ID} → {枠名: 定義}。枠名を省いた書き方（["sword_iron", "ears_cat"]）は種類の既定の枠へ入れる。
static func resolve_all(assigned: Variant) -> Dictionary:
	var out: Dictionary={}
	var pairs: Dictionary={}
	if assigned is Array:
		for id in assigned:
			var d: Dictionary=resolve(str(id))
			if not d.is_empty():pairs[str(d.get("slot",KIND_SLOT.get(str(d.kind),"")))]=str(id)
	elif assigned is Dictionary:pairs=assigned
	for slot in pairs:
		if not str(slot) in Catalog.PROP_SLOTS or str(pairs[slot])=="":continue
		var def: Dictionary=resolve(str(pairs[slot]))
		if not def.is_empty():out[str(slot)]=def
	return out

## 見せるかどうかの印（役者の状態の5列目）。assigned は {枠名: ID}、states は {枠名: "show"|"hide"|"rest"|"erect"}（場面・ゲームの指定）。
## 既定：武器は WEAPON_HIDE_CLIPS の動作で隠す、耳と尻尾は見せる、男性器は隠す。
## ERECT_LIFT：場面の外で勃起させたとき、付け根を軸に起こす角度（ラジアン。−で腰の前へ）。場面の中（in_scene）は焼いた向きのまま。
const ERECT_LIFT:=-1.22
static func state(assigned: Dictionary,states: Dictionary,clip: String,in_scene: bool=false) -> Vector4:
	var mask:=0;var erect:=0.0
	for i in range(Catalog.PROP_SLOTS.size()):
		var slot: String=Catalog.PROP_SLOTS[i]
		if str(assigned.get(slot,""))=="":continue
		var fallback:="show"
		if slot=="groin":fallback="hide"
		elif slot.begins_with("weapon") and clip in WEAPON_HIDE_CLIPS:fallback="hide"
		var s: String=str(states.get(slot,fallback))
		if s in ["show","rest","erect"]:mask|=1<<i
		if slot=="groin" and s=="erect":erect=1.0
	return Vector4(mask,erect,ERECT_LIFT if erect>0.0 and not in_scene else 0.0,0)
