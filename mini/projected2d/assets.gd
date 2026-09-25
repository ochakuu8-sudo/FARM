extends RefCounted
## Procedural DIAGNOSTIC 2D drawings, not renders of 3D surfaces.
## Generates editable PNG views + manifest; production art can replace same template.
const TILE := 64
const TYPES := ["head", "coat", "waist", "sleeve", "trouser", "boot", "hand", "neck", "hair", "pouch"]
var atlases: Array[Image] = []
var textures: Array[ImageTexture] = []
var definitions: Array = []
var error := ""
var wardrobe_images:Dictionary={}
var wardrobe_textures:Dictionary={}
func wardrobe(base:int,costume:int)->Image:
	var key:=str(base)+":"+str(costume)
	if not wardrobe_images.has(key):
		var img:=atlases[base].duplicate()
		for kind in ["coat","waist","sleeve","trouser","boot","pouch"]:
			var row:=TYPES.find(kind)
			img.blit_rect(atlases[costume],Rect2i(0,row*TILE,640,TILE),Vector2i(0,row*TILE))
		wardrobe_images[key]=img
	return wardrobe_images[key]
func wardrobe_texture(base:int,costume:int)->ImageTexture:
	var key:=str(base)+":"+str(costume)
	if not wardrobe_textures.has(key):wardrobe_textures[key]=ImageTexture.create_from_image(wardrobe(base,costume))
	return wardrobe_textures[key]
func load_all() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://mini/projected2d/characters.json"))
	if not data is Dictionary or data.get("version") != 1: error = "characters.json の版が不正"; return false
	definitions = data.characters
	for def in definitions:
		var folder := "res://mini/projected2d/assets/" + str(def.id)
		var path := folder + "/atlas.png"
		var img:Image
		if not FileAccess.file_exists(folder+"/manifest.json") and FileAccess.file_exists(folder+"/head_00.png") and not "--regenerate-diagnostic-assets" in OS.get_cmdline_user_args():error="manifest.json がありません。既存画像を保護するため自動生成しません: "+folder;return false
		if not FileAccess.file_exists(folder+"/manifest.json") or "--regenerate-diagnostic-assets" in OS.get_cmdline_user_args():img=generate(def)
		else:
			var manifest=JSON.parse_string(FileAccess.get_file_as_string(folder+"/manifest.json"))
			if not manifest is Dictionary or manifest.get("template")!="diagnostic_cutout_v1":error="非互換な素材テンプレート: "+folder;return false
			img=Image.create(TILE*10,TILE*TYPES.size(),false,Image.FORMAT_RGBA8)
			# PNG files are authoritative. Rebuild the in-memory atlas on load.
			for row in range(TYPES.size()):
				for v in range(10):
					var source:=folder+"/"+str(TYPES[row])+"_%02d.png"%v
					if not FileAccess.file_exists(source):error="素材不足: "+source;return false
					var part:=Image.load_from_file(ProjectSettings.globalize_path(source))
					if part==null or part.get_size()!=Vector2i(TILE,TILE):error="画像寸法が不正: "+source;return false
					part.convert(Image.FORMAT_RGBA8)
					img.blit_rect(part,Rect2i(0,0,TILE,TILE),Vector2i(v*TILE,row*TILE))
		if img.get_width() != TILE * 10 or img.get_height() != TILE * TYPES.size(): error = "アトラス寸法が不正: " + path; return false
		img.convert(Image.FORMAT_RGBA8)
		atlases.append(img)
		textures.append(ImageTexture.create_from_image(img))
	return true
func generate(def: Dictionary) -> Image:
	var atlas := Image.create(TILE * 10, TILE * TYPES.size(), false, Image.FORMAT_RGBA8)
	var folder := "res://mini/projected2d/assets/" + str(def.id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var manifest := {"version": 1, "template": "diagnostic_cutout_v1", "tile_size": TILE, "views": 10, "parts": TYPES, "note": "2D診断素材。3Dレンダリング素材ではありません。格子頂点IDは共通。"}
	for row in range(TYPES.size()):
		for view in range(10):
			var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			for y in range(TILE):
				for x in range(TILE):
					img.set_pixel(x, y, paint(TYPES[row], view, Vector2((x + 0.5) / TILE, (y + 0.5) / TILE), def))
			atlas.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i(view * TILE, row * TILE))
			img.save_png(folder + "/" + str(TYPES[row]) + "_%02d.png" % view)
	atlas.save_png(folder + "/atlas.png")
	var f := FileAccess.open(folder + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	return atlas
func paint(kind: String, view: int, uv: Vector2, def: Dictionary) -> Color:
	var q := (uv - Vector2(0.5, 0.5)) * 2.0
	var radius := q.length()
	var alpha := clampf((0.94 - radius) * 40.0, 0.0, 1.0)
	if alpha == 0: return Color(0, 0, 0, 0)
	var yaw := view * PI / 4.0
	var front := maxf(cos(yaw), 0.0) if view < 8 else 0.0
	var col := Color(str(def.coat))
	if kind in ["head", "hand", "neck"]: col = Color(str(def.skin))
	if kind in ["trouser", "waist"]: col = Color(str(def.pants))
	if kind in ["boot", "pouch"]: col = Color("39404d") if kind == "boot" else Color("987651")
	if kind == "hair": col = Color(str(def.hair))
	var ink := Color("223344")
	if kind == "head":
		if q.y < -0.43 or (front < 0.1 and view != 9): col = Color(str(def.hair))
		if front > 0.1:
			# Common feature landmarks keep eye/mouth positions registered across views.
			if (q - Vector2(-0.30, -0.03)).length() < 0.075 or (q - Vector2(0.30, -0.03)).length() < 0.075: col = col.lerp(ink, front)
			if absf(q.x) < 0.15 and absf(q.y - 0.35) < 0.022: col = col.lerp(ink, front)
			if q.y < -0.20 and q.x > 0.02 and q.x < 0.30: col = Color(str(def.hair))
		if view in [2,6]:
			var side:=1.0 if view==2 else -1.0
			col=Color(str(def.skin)) if q.x*side>.05 and q.y>-.45 else Color(str(def.hair))
			if (q-Vector2(.42*side,-.03)).length()<.075:col=ink
			if q.x*side>.50 and absf(q.y-.32)<.025:col=ink
	elif kind in ["coat", "sleeve"]:
		if absf(q.y - 0.62) < 0.10: col = Color(str(def.trim))
		if kind == "coat" and front > 0.1:
			if absf(q.x) < 0.035: col = col.lerp(ink, front * 0.6)
			if (q - Vector2(0.32, -0.25)).length() < 0.16: col = col.lerp(Color(str(def.trim)), front)
		if int(def.pattern) == 1 and absf(q.y + 0.2) < 0.035: col = col.lerp(Color(str(def.trim)), 0.6)
		if kind=="sleeve" and (q-Vector2(.25,-.25)).length()<.13:col=col.lerp(Color(str(def.trim)),front)
	elif kind == "boot":
		if q.y > 0.52: col = ink
	elif kind == "hand":
		if view == 0 and absf(q.y) < 0.03: col = col.darkened(0.14)
	if radius > 0.86: col = col.lerp(ink, 0.7)
	# Flat painted highlight, identical across rigs. No 3D lighting pass.
	col = col.lightened(maxf(0.0, -q.x - q.y) * 0.035)
	col.a = alpha
	return col
