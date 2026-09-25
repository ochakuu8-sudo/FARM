extends RefCounted
## 部品棚（部位ごとの着せ替え）。素体規格で作った女キャラは骨格・切り出しが同じなので、
## 頭・上半身・腰・腕・脚を別々のキャラから取って組み合わせられる（描画のレシピの modules を部位ごとに差し替える）。
## 動作は土台の原型（既定は女冒険者 "0"。全部の2体場面が焼けている）のものをそのまま使い、焼き直しは要らない。
##
## 部品になる原型：content/animation_profiles.json の役割 adventurer で、組み込み番号（make）があり、系統が "0" のもの。
## 原型の "parts": ["head", "arms"] は、その原型が部品として出す部位（書かなければ5部位すべて）。
## 1部位だけ登録した原型（頭だけ等）は、ほかの部位の絵が素体のものなので、その部位の部品にしか並ばない。
## 肌の色（首の値 neck_defaults.json の skin）が近いものどうしだけ組める（首・手首で色がずれないように）。
const Profiles=preload("res://game_v2/animation/profiles.gd")
const MODULES:=["head","upper_body","lower_body","arms","legs"]
const NAMES:={"head":"頭","upper_body":"上半身","lower_body":"腰","arms":"腕","legs":"脚"}
## 顔の部品。顔を部位で描く頭（顔の登録が registered。今は女冒険者 "0"）なら、目・眉・口を別のキャラの顔から取れる。
## 顔が頭の絵に描き込まれている頭（baked。素体規格の試し取り込み）は顔の部品を着けられない（頭ごとの固定の顔）。
const FACE_MODULES:={"eyes":["eye_l","eye_r"],"brows":["brow_l","brow_r"],"mouth":["mouth"]}
const FACE_NAMES:={"eyes":"目","brows":"眉","mouth":"口"}
const CATALOG:="res://mini/layered2d/data/catalog.json"
static var face_modes: Dictionary={}
## 組み合わせの土台（動作と2体場面はこの原型のもの）。
const BASE:="0"
## 肌の色の近さの目安（RGB 0〜1 の距離）。これ以下なら同じ肌の色とみなす。
const SKIN_NEAR:=0.15
static var necks: Dictionary={}

## 部品になる原型の一覧（登録簿の順）。module を渡すと、その部位を出す原型だけ。
static func ids(module: String="") -> Array:
	var out: Array=[]
	for id in Profiles.ids("adventurer"):
		var info: Dictionary=Profiles.info(id)
		if info.has("make") and Profiles.family(id)=="0" and (module=="" or module in provides(id)):out.append(id)
	return out

## その原型が部品として出す部位。
static func provides(profile: String) -> Array:
	var listed=Profiles.info(profile).get("parts",null)
	if not listed is Array:return MODULES.duplicate()
	return MODULES.filter(func(m):return m in listed)

static func index_of(profile: String) -> int:
	return int(Profiles.info(profile).get("make",-1))

## 肌の色（頭の首の値）。
static func skin(profile: String) -> Color:
	if necks.is_empty():
		var d=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/neck_defaults.json"))
		necks=d if d is Dictionary else {}
	var s: Array=necks.get(str(index_of(profile)),{}).get("skin",[1,0.8,0.7])
	return Color(float(s[0]),float(s[1]),float(s[2]))

## 顔を部位で描く頭か（顔の部品を着けられる・出せる）。
static func face_parts_ok(profile: String) -> bool:
	if face_modes.is_empty():
		var c=JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		var list: Array=c.get("templates",[]) if c is Dictionary else []
		for i in list.size():
			var t=JSON.parse_string(FileAccess.get_file_as_string(str(list[i])))
			face_modes[i]=str(t.get("face",{}).get("mode","registered")) if t is Dictionary else "baked"
	return str(face_modes.get(index_of(profile),"baked"))=="registered"

## 顔の部品を出せる原型。
static func face_ids() -> Array:
	return ids("head").filter(func(p):return face_parts_ok(p))

## 髪の色（登録簿の hair。一覧の丸などの目印に使う）。
static func hair(profile: String) -> String:
	return str(Profiles.info(profile).get("hair","#604030"))

static func same_skin(a: String,b: String) -> bool:
	var x:=skin(a);var y:=skin(b)
	return Vector3(x.r-y.r,x.g-y.g,x.b-y.b).length()<=SKIN_NEAR

## 肌の色の組（同じ組の中なら混ぜられる）。返り値は組ごとの原型の配列。
static func skin_groups() -> Array:
	var groups: Array=[]
	for id in ids():
		var placed:=false
		for g in groups:
			if same_skin(g[0],id):g.append(id);placed=true;break
		if not placed:groups.append([id])
	return groups

## 組み合わせの確かめ。{部位: 原型}。書かない部位は土台のまま。
static func validate(parts: Dictionary) -> String:
	var all: Array=ids()
	for m in parts:
		if FACE_MODULES.has(m):
			if not str(parts[m]) in face_ids():return "%sは顔の部品（%s）を持っていない"%[Profiles.name(str(parts[m])),FACE_NAMES[m]]
			if not face_parts_ok(str(parts.get("head",BASE))):return "頭（%s）は顔が絵に描き込まれていて、%sを替えられない"%[Profiles.name(str(parts.get("head",BASE))),FACE_NAMES[m]]
			continue
		if not m in MODULES:return "部位の名前が違う: "+str(m)
		if not str(parts[m]) in all:return "部品にない原型: "+str(parts[m])
		if not m in provides(str(parts[m])):return "%sは%sの部品を持っていない"%[Profiles.name(str(parts[m])),NAMES[m]]
	var head: String=str(parts.get("head",BASE))
	for m in parts:
		if FACE_MODULES.has(m):continue
		if not same_skin(head,str(parts[m])):return "%sの肌の色が頭と合わない（%s）"%[NAMES[m],Profiles.name(str(parts[m]))]
	return ""

## ランダムな組み合わせ。頭を先に選び、ほかの部位は頭と同じ肌の色の中から選ぶ。
## same_chance：ほかの部位を頭と同じキャラにそろえる割合（0〜1。服がちぐはぐになりすぎないように）。
static func random(rng: RandomNumberGenerator,same_chance: float=0.35,pool: Array=[]) -> Dictionary:
	var all: Array=pool if not pool.is_empty() else ids()
	var heads: Array=all.filter(func(p):return "head" in provides(p))
	if heads.is_empty():return {}
	var head: String=heads[rng.randi()%heads.size()]
	var out: Dictionary={"head":head}
	for m in MODULES:
		if m=="head":continue
		var near: Array=all.filter(func(p):return same_skin(head,p) and m in provides(p))
		if m in provides(head) and (rng.randf()<same_chance or near.is_empty()):out[m]=head
		elif not near.is_empty():out[m]=near[rng.randi()%near.size()]
	return out
