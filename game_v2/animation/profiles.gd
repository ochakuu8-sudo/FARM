extends RefCounted
## 原型（体型）の登録簿。content/animation_profiles.json が正本。
## キャラ・魔物を増やすときはJSONに足すだけで、ベイク・2体場面・ツールの一覧に反映される。
##
## 骨格（rig）と見た目：焼き込み（動作・2体場面）は骨格ごと。"rig": "0" と書いた原型は、骨格 "0" の焼いた動作を
## そのまま使う見た目だけの原型（素体規格の女キャラなど。骨格・切り出しが同じなので動きは完全に同じ）。
## 見た目だけの原型は焼かない。登録（図集を作る）だけで、ゲーム・ツールですぐ使える。rig を書かない原型は自分が骨格。
const PATH="res://game_v2/content/animation_profiles.json"
const Recipes=preload("res://game_v2/animation/recipes.gd")
const ROLES=["adventurer","monster"]
static var cached: Dictionary={}

## ファイルを編集した後に読み直す（ツール用）。
static func reload() -> void:
	cached={}

static func read() -> Dictionary:
	if not cached.is_empty():return cached
	var data=JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not data is Dictionary or not data.get("profiles") is Dictionary:
		push_error("原型の登録簿を読めません: "+PATH)
		return {"version":1,"bundles":{},"profiles":{"0":{"name":"冒険者","role":"adventurer","make":0,"family":"0"},"1":{"name":"ゴブリン","role":"monster","make":1,"family":"1"}}}
	cached=data
	return data

static func ids(role: String="") -> Array:
	var result: Array=[]
	var data: Dictionary=read()
	for id in data.profiles:
		if role=="" or data.profiles[id].get("role","")==role:result.append(str(id))
	return result

static func info(id: String) -> Dictionary:
	return read().profiles.get(id,{})

static func name(id: String) -> String:
	return str(info(id).get("name",id))

static func role(id: String) -> String:
	return str(info(id).get("role",""))

## 行動割り当ての継承先。未登録の原型は自分自身。
static func family(id: String) -> String:
	return str(info(id).get("family",id))

## 動作を借りる骨格の原型（rig）。書いていなければ自分。
static func rig(id: String) -> String:
	var r: String=str(info(id).get("rig",id))
	return r if r!="" and read().profiles.has(r) else id

## 骨格の原型か（焼き込みの対象になるか）。
static func is_rig(id: String) -> bool:
	return rig(id)==id

## 組み込み番号から作る骨格の原型（pc.bin に単体動作を焼く対象）。見た目だけの原型（rig が別）は焼かない。
static func built_in() -> Array:
	var result: Array=[]
	var data: Dictionary=read()
	for id in data.profiles:
		if data.profiles[id].has("make") and is_rig(str(id)):result.append(str(id))
	return result

static func bundle_paths() -> Array:
	var result: Array=[]
	for path in read().get("bundles",{}).values():
		if not str(path) in result:result.append(str(path))
	return result

## 焼き込み用のレシピ。追加素材の原型は束ファイルから読む（無ければ空）。
static func recipe(id: String,cache: Dictionary={}) -> Dictionary:
	var entry: Dictionary=info(id)
	if entry.has("make"):
		var made: Dictionary=Recipes.make(int(entry.make))
		# 頭の大きさの倍率（原型ごと。素体規格の頭の枠に対する見た目の調整）。
		if entry.has("head_scale"):made.head_scale=float(entry.head_scale)
		return with_soft(id,made)
	var path: String=str(read().get("bundles",{}).get(str(entry.get("bundle","")),""))
	if path=="":return {}
	if not cache.has(path):
		cache[path]={}
		if FileAccess.file_exists(path):
			var bundle=FileAccess.open(path,FileAccess.READ).get_var()
			if bundle is Dictionary:cache[path]=bundle.get("recipes",{})
	var found: Dictionary=cache[path].get(id,{}).duplicate(true)
	return {} if found.is_empty() else with_soft(id,found)

## 登録簿の soft（胸などの揺れと変形領域）をレシピへ写す。登録簿が正本で、束ファイル側の値より優先。
## あわせて、表情差分（expressions.json）を一枚絵の顔の expression_atlases に足す。
static func with_soft(id: String,recipe: Dictionary) -> Dictionary:
	var soft: Dictionary=info(id).get("soft",{})
	if soft.is_empty():recipe.erase("soft")
	else:recipe.soft=soft.duplicate(true)
	var extra: Dictionary=expressions(id)
	if not extra.is_empty() and recipe.get("asset_face",{}).get("mode","")=="baked":
		var atlases: Dictionary=recipe.asset_face.get("expression_atlases",{}).duplicate()
		atlases.merge(extra,true)
		recipe.asset_face.expression_atlases=atlases
	return recipe

## 衣装差分 {衣装名: {部位グループ: {"0".."8": 画像パス}}}。game_v2/tools/outfit_parts.gd が登録する。
const OUTFITS="res://game_v2/content/outfits.json"
static func outfits(id: String) -> Dictionary:
	if not FileAccess.file_exists(OUTFITS):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(OUTFITS))
	return data.get(id,{}) if data is Dictionary and data.get(id) is Dictionary else {}

## 一枚絵の顔の表情差分 {名前: 頭の帯画像のパス}。game_v2/tools/expression_heads.gd が登録する。
const EXPRESSIONS="res://game_v2/content/expressions.json"
static func expressions(id: String) -> Dictionary:
	if not FileAccess.file_exists(EXPRESSIONS):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(EXPRESSIONS))
	return data.get(id,{}) if data is Dictionary and data.get(id) is Dictionary else {}

## 場面の配役指定（原型IDまたは役割名の配列）を骨格の原型IDの配列に展開する（2体場面は骨格ごとに焼く）。
## 見た目だけの原型を名指ししても、その骨格になる。
static func expand(entries: Array) -> Array:
	var result: Array=[]
	for entry in entries:
		var list: Array=ids(str(entry)) if str(entry) in ROLES else [str(entry)]
		for id in list:
			var r: String=rig(str(id))
			if not r in result:result.append(r)
	return result
