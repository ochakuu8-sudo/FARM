extends RefCounted
## 2体場面の置き場所。content/pair_scenes/<場面ID>.json が1場面1ファイルの正本。
## 先頭が "_" のファイル（ひな形など）は読まない。
const DIR="res://game_v2/content/pair_scenes/"
const Profiles=preload("res://game_v2/animation/profiles.gd")

static func ids() -> Array:
	var result: Array=[]
	var dir=DirAccess.open(DIR)
	if dir==null:return result
	for file in dir.get_files():
		if file.ends_with(".json") and not file.begins_with("_"):result.append(file.get_basename())
	result.sort()
	return result

static func path(id: String) -> String:
	return DIR+id+".json"

static func load_scene(id: String) -> Dictionary:
	if not FileAccess.file_exists(path(id)):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(path(id)))
	return data if data is Dictionary else {}

static func scenes() -> Dictionary:
	var result: Dictionary={}
	for id in ids():result[id]=load_scene(id)
	return result

static func stages(scene: Dictionary) -> Array:
	return ["default"]+scene.get("stages",{}).keys()

## 配役。cast.taker（受け側）と cast.partner（相手）に原型IDか役割名を書く。
## 省略時は 受け側=adventurer 全員、相手=monster 全員。
## cast.partner を空の配列 [] にすると1体だけの場面（出産など）。組み合わせは [受け側, ""]、名前は "受け側|"。
static func cast(scene: Dictionary) -> Array:
	var info: Dictionary=scene.get("cast",{})
	var result: Array=[]
	for taker in Profiles.expand(info.get("taker",["adventurer"])):
		if solo(scene):result.append([taker,""]);continue
		for partner in Profiles.expand(info.get("partner",["monster"])):
			if taker!=partner:result.append([taker,partner])
	return result

## 1体だけの場面か（cast.partner が空の配列）。
static func solo(scene: Dictionary) -> bool:
	var partner=scene.get("cast",{}).get("partner",null)
	return partner is Array and partner.is_empty()

static func key(taker: String,partner: String) -> String:
	return taker+"|"+partner

## 確認の表示に使う組み合わせの名前（1体の場面は受け側の名前だけ）。
static func cast_name(taker: String,partner: String) -> String:
	return Profiles.name(taker) if partner=="" else "%s × %s"%[Profiles.name(taker),Profiles.name(partner)]
