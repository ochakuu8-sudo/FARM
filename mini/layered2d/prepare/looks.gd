extends RefCounted
## 見た目の焼き込み（ブラウザ版・書き出した版で使う）。
## 開発中のゲームは原画（2560×3840 のアトラス）を読んで、その場で128画素の升目に縮めて描画の置き場へ詰める。
## 書き出した版はその「縮めた後の升目」を前もって焼いたものを読む。原画を持たないのでダウンロードが小さく、
## 読み込みで大きな画像を展開・縮小しない（スマホのブラウザで重い処理をしない）。詰め方は同じなので見た目は同じ。
##   焼く：   Godot_console --headless --path . --script res://game_v2/tools/looks_bake.gd
##   使う：   書き出した版は自動。デスクトップで試すときは -- --baked-looks
## ファイル：looks/s<原型の番号>.looks（その原型の体の部位と、その頭の顔）、looks/common.looks（付属物・効果の画像）。
const DIR:="res://game_v2/assets/looks/"
const VERSION:=2

static var enabled: bool=OS.has_feature("template") or "--baked-looks" in OS.get_cmdline_user_args()
## 焼くとき true：実行中に作った升目をためる（looks_bake.gd）。
static var recording:=false
static var files: Dictionary={}      # ファイル名 → {kind → {key → entry}}（読んだもの・焼いているもの）
static var missing: Dictionary={}    # 見つからなかった鍵（一度だけ知らせる）

## 体の部位の鍵：原型の番号・部位・差し替え画像・襟の切り取り（胸だけ）。首は肌色で塗るだけなので焼かない。
static func body_key(source: int,group: String,paths: Dictionary,collar_cut: Variant) -> String:
	var key: String="%d/%s"%[source,group]
	if not paths.is_empty():key+="/"+str(hash(JSON.stringify(paths)))
	if group=="chest":key+="/"+str(hash(JSON.stringify(collar_cut)))
	return key

static func file_of(source: int) -> String:
	return "s%d"%source

static func data(file: String) -> Dictionary:
	if files.has(file):return files[file]
	var d: Dictionary={"body":{},"face":{},"prop":{},"effect":{}}
	var path: String=DIR+file+".looks"
	if not recording and FileAccess.file_exists(path):
		var f:=FileAccess.open(path,FileAccess.READ)
		var v=f.get_var() if f!=null else null
		if v is Dictionary and int(v.get("version",0))==VERSION:d=v
	files[file]=d
	return d

## 保存の画質。負なら可逆（画素がまったく同じ）。0〜1 なら非可逆の WebP（透明度は可逆のまま。小さくなる）。
static var quality:=-1.0
static func encode(image: Image) -> PackedByteArray:
	return image.save_webp_to_buffer(quality>=0.0,maxf(quality,0.0))

static func decode(bytes: PackedByteArray) -> Image:
	var image:=Image.new()
	image.load_webp_from_buffer(bytes)
	if image.get_format()!=Image.FORMAT_RGBA8:image.convert(Image.FORMAT_RGBA8)
	return image

static func find(file: String,kind: String,key: String) -> Dictionary:
	var entry: Dictionary=data(file)[kind].get(key,{})
	if entry.is_empty() and not missing.has(kind+":"+key):
		missing[kind+":"+key]=true
		push_warning("Looks: 焼いていない見た目 %s %s（looks_bake.gd で焼き直す）"%[kind,key])
	return entry

## 体の部位：{cells: [PNG], map: [[升目の番号, 反転], …9向き]}
static func body(source: int,key: String) -> Dictionary:
	return find(file_of(source),"body",key)

## 顔：{tiles: {向き: PNG}}（向き 0,1,2,3,4,8。128画素）
static func face(head: int,key: String) -> Dictionary:
	return find(file_of(head),"face",key)

## 付属物：{states: [{cells: [PNG], map: [[番号, 反転], …9]}]}
static func prop(key: String) -> Dictionary:
	return find("common","prop",key)

## 場面の効果の画像（汗・紅潮など。原寸）。
static func effect(path: String) -> Image:
	var entry: Dictionary=find("common","effect",path)
	return decode(entry.png) if entry.has("png") else null

# ───────── 焼くとき（recording） ─────────
static func put(file: String,kind: String,key: String,entry: Dictionary) -> void:
	data(file)[kind][key]=entry

static func save_all() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var total:=0
	for file in files:
		var d: Dictionary=files[file]
		d.version=VERSION
		var f:=FileAccess.open(DIR+file+".looks",FileAccess.WRITE)
		f.store_var(d);total+=f.get_length();f.close()
	return total
