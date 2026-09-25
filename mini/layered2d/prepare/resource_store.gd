extends RefCounted
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const Surface = preload("res://mini/projected2d/b_cutout/head_surface.gd")
const FaceComposer = preload("res://mini/layered2d/prepare/face_composer.gd")
const Neck=preload("res://mini/layered2d/data/neck_attachment.gd")
const Looks=preload("res://mini/layered2d/prepare/looks.gd")
const VIEW_CAPACITY = 4096
var catalog := Catalog.new()
var joint_template:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/joint_template.json"))
var body_images: Array[Image] = []
var face_images: Array[Image] = []
var motion_images: Array[Image] = []
var source_images: Dictionary = {}
var face_cache: Dictionary = {}
var track_cache: Dictionary = {}
var tracks: Array = []
var views: Array = []
var body_views: Dictionary = {}
var body_cell := 0
var face_cell := 0
var motion_cursor := 0
## GPU に載せるテクスチャの上限（MiB）。ゲームは必要な分だけ読むので既定の 256。
## 全原型・全場面を一度に読む道具（アニメーション管理ツールなど）は Bridge.prepare で引き上げる。
var texture_budget_mib := 256
## 動作データのページ（1枚 1MiB）の上限。ゲームは必要な分だけ読むので 64。全部を一度に読む道具は Bridge.prepare で引き上げる。
var motion_page_limit := 64
## 軽くする設定（2026-09-24）。
## body_tile：身体の升目の画素数。元の絵は 256 だが、ゲームでの表示は大きくても 100 画素前後なので 128 に縮めて詰める（1ページ 64 升 → 256 升）。
## motion_half：動作データを GPU には 16bit の浮動小数で送る（元のデータは 32bit のまま持つ）。位置の誤差は 0.002 程度で見た目は変わらない。
var body_tile := 128
var motion_half := true
## 束縛表の列：0〜91 部位、96〜105 首、106〜122 胸の揺れ、124〜140 尻の揺れ、141〜148 骨盤画像の下への延長（向きごと）、
## 149 胸・尻の大きさ、160〜179 付属物（枠23〜27、1枠4列。PROP_COLUMN）。
const PROP_COLUMN:=160
var binding := Image.create(PROP_COLUMN+Catalog.PROP_SLOTS.size()*4,Catalog.CAPACITY,false,Image.FORMAT_RGBAF)
var shape_edges := Image.create(Catalog.STRIDE,Catalog.CAPACITY,false,Image.FORMAT_RGBAF)
var shape_texture:ImageTexture
var chart := Image.create(49,18,false,Image.FORMAT_RGBAF)
var binding_texture: ImageTexture
var motion_texture: Texture2DArray
var face_texture: Texture2DArray
var body_texture: Texture2DArray
var chart_texture: ImageTexture
## 前の commit から書き換えた絵のページ（commit はそのページだけ GPU へ送る。ページが増えたときだけ作り直す）
var dirty_body: Dictionary={}
var dirty_face: Dictionary={}
var view_written:=0            # 表示表を GPU の表へ書いたところまで
var view_texture: ImageTexture
var view_image: Image
var state_data := PackedFloat32Array()
var state_texture: ImageTexture
var material := ShaderMaterial.new()
## 役者の行ごとの材質（actor_row を持つ）。描画ノードはこれを使う。行の数（役者の上限）だけ作る。
## GLES3 のインスタンス変数は全体で256ノード分しか枠がないため、行は材質で渡す（ノードがいくつあっても枠を使わない）。
var row_materials: Dictionary={}
var dirty := true
var last_error := ""
var memory_bytes := 0
var uploads := 0
var face_overrides:Dictionary={}

func _init(load_all_bodies:bool=true) -> void:
	shape_edges.fill(Color(1,1,1,1))
	state_data.resize(8*Catalog.CAPACITY*4)
	state_texture = ImageTexture.create_from_image(gpu_bytes(8,Catalog.CAPACITY,state_data.to_byte_array()))
	material.shader = load("res://mini/layered2d/render/cutout.gdshader")
	set_param("actor_state",state_texture)
	chart=Image.create(49,catalog.configs.size()*9,false,Image.FORMAT_RGBAF)
	for c in range(catalog.configs.size()):
		var config: Dictionary = catalog.configs[c]
		var image:Image = load_image(config.atlas_path) if load_all_bodies else null
		var head := Surface.new(config.head_landmarks,config.get("source_directions",[]))
		for view in range(9):
			for p in range(49):
				var uv: Vector2 = head.grids[view][p]
				chart.set_pixel(p,c*9+view,Color(uv.x,uv.y,0,0))
		for group in config.surface:
			if group == "head": continue
			if not load_all_bodies:continue
			var cells: Array=[]
			for view in range(9):cells.append(image.get_region(Rect2i(view*256,int(config.surface[group].row)*256,256,256)))
			body_views[str(c)+"/"+group] = append_cells(cells)
	# Keep sampler arrays valid even before the first actor is prepared.
	face_images.append(Image.create(512,512,false,Image.FORMAT_RGBA8))
	motion_images.append(Image.create(256,256,false,Image.FORMAT_RGBAF))

func load_image(path: String) -> Image:
	if not source_images.has(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		image.convert(Image.FORMAT_RGBA8)
		source_images[path] = image
	return source_images[path]

func pack(image: Image, face: bool) -> Dictionary:
	var size := 512 if face else 2048
	var tile := 128 if face else body_tile
	var per_side := size/tile
	var cell := face_cell if face else body_cell
	var layer := cell/(per_side*per_side)
	var local := cell%(per_side*per_side)
	var pos := Vector2i((local%per_side)*tile,(local/per_side)*tile)
	var pages: Array[Image] = face_images if face else body_images
	while pages.size() <= layer: pages.append(Image.create(size,size,false,Image.FORMAT_RGBA8))
	var copy: Image = image.duplicate()
	if copy.get_width()!=tile or copy.get_height()!=tile: copy.resize(tile,tile,Image.INTERPOLATE_LANCZOS)
	pages[layer].blit_rect(copy,Rect2i(0,0,tile,tile),pos)
	if face:dirty_face[layer]=true
	else:dirty_body[layer]=true
	if face: face_cell+=1
	else: body_cell+=1
	return {"rect":Vector4(float(pos.x)/size,float(pos.y)/size,float(tile)/size,float(tile)/size),"layer":layer,"mirror":false}

static func face_key(recipe: Dictionary) -> String:
	return Catalog.fingerprint([recipe.modules.head,FaceComposer.donors(recipe),recipe.get("expression",{}),recipe.get("asset_face",{}),recipe.get("asset_head_atlas","")])

func module_view_base(recipe:Dictionary,slot:int)->int:
	var neck:=Neck.for_recipe(recipe)
	var source:=catalog.source_for(recipe,slot)
	var group:String=Catalog.GROUPS[slot]
	var override:Dictionary=recipe.get("asset_modules",{}).get(Catalog.MODULES[slot],{})
	var paths:Dictionary=override.get("groups",{}).get(group,{})
	# 焼いた見た目（書き出した版）：縮めた後の升目を読んで詰めるだけ。首は肌色で塗るだけなので原画は要らない。
	var look_key:String=Looks.body_key(source,group,paths,neck.get("collar_cut",[]))
	if Looks.enabled:
		var lkey:String="L:"+look_key+("/"+str(hash(str(neck.get("skin",[])))) if group=="neck" else "")
		if body_views.has(lkey):return body_views[lkey]
		if group=="neck":
			body_views[lkey]=append_cells(skin_cells(neck,body_tile));return body_views[lkey]
		var baked:Dictionary=Looks.body(source,look_key)
		if not baked.is_empty():
			body_views[lkey]=append_baked(baked);return body_views[lkey]
	var repair:String=preload("res://mini/layered2d/data/chest_art_repair.gd").directory(source,paths) if group=="chest" else ""
	var key:=str(source)+"/"+group+"/"+repair+ ("/"+Catalog.fingerprint(paths) if not paths.is_empty() else "")
	if group in ["neck","chest"]:key+="/neck3/"+Catalog.fingerprint(neck)
	if body_views.has(key):return body_views[key]
	var config:Dictionary=catalog.configs[source]
	var image:=load_image(config.atlas_path)
	var base:=views.size()
	var cells: Array=[]
	for view in range(9):
		var cell:Image=load_image(paths[str(view)]) if paths.has(str(view)) else image.get_region(Rect2i(view*256,int(config.surface[group].row)*256,256,256))
		if group=="neck":
			cell=Image.create(256,256,false,Image.FORMAT_RGBA8)
			var skin:Array=neck.skin
			cell.fill(Color(skin[0],skin[1],skin[2],1))
		if group=="chest":
			if not repair.is_empty():cell=load_image(repair+"/chest_"+str(view)+".png")
			cell=cell.duplicate();Neck.cut_tile(cell,neck.get("collar_cut",[]),view)
		cells.append(cell)
	append_cells(cells)
	body_views[key]=base
	if Looks.recording and group!="neck":Looks.put(Looks.file_of(source),"body",look_key,bake_cells(cells))
	return base

## 首の升目（肌色で塗りつぶすだけ）。
static func skin_cells(neck:Dictionary,size:int)->Array:
	var cells:Array=[]
	var skin:Array=neck.skin
	for view in range(9):
		var cell:=Image.create(size,size,false,Image.FORMAT_RGBA8)
		cell.fill(Color(skin[0],skin[1],skin[2],1))
		cells.append(cell)
	return cells

## 焼くとき：9向きの升目を append_cells と同じ判断で共有し、残った升目を pack と同じ縮め方で縮めて保存する形にする。
func bake_cells(cells: Array) -> Dictionary:
	var uniques: Array=[];var map: Array=[]
	for view in range(9):
		var partner: int=MIRROR_PARTNER.get(view,-1)
		if partner>=0 and similar_cell(cells[view],cells[partner],view!=8):
			var m: Array=map[partner].duplicate()
			if view!=8:m[1]=not bool(m[1])
			map.append(m)
		else:
			map.append([uniques.size(),false]);uniques.append(Looks.encode(shrink(cells[view])))
	return {"cells":uniques,"map":map}

## pack と同じ縮め方（升目の大きさへ Lanczos）。
func shrink(image: Image) -> Image:
	var copy: Image=image.duplicate()
	if copy.get_width()!=body_tile or copy.get_height()!=body_tile:copy.resize(body_tile,body_tile,Image.INTERPOLATE_LANCZOS)
	return copy

## 焼いた部位を詰める（append_cells の結果と同じ表示表になる）。
func append_baked(entry: Dictionary) -> int:
	var base:=views.size()
	var packed: Array=[]
	for bytes in entry.cells:packed.append(pack_shared(Looks.decode(bytes)))
	for m in entry.map:
		var e: Dictionary=packed[int(m[0])].duplicate();e.mirror=bool(m[1])
		views.append(e)
	return base

## 9向きの升目を詰めて、表示表（views）の先頭の番号を返す。
## 画像の容量を抑える：右向き（5〜7）は左向き（3〜1）の左右反転、8は4と同じ絵なので、
## 絵が同じなら升目を共有して向きの印（mirror）だけ変える。まったく同じ絵の升目（首の肌色など）も共有する。
func append_cells(cells: Array) -> int:
	var base:=views.size()
	var entries: Array=[]
	for view in range(9):
		var partner: int=MIRROR_PARTNER.get(view,-1)
		if partner>=0 and similar_cell(cells[view],cells[partner],view!=8):
			var shared: Dictionary=entries[partner].duplicate()
			if view!=8:shared.mirror=not bool(shared.mirror)
			entries.append(shared)
		else:entries.append(pack_shared(cells[view]))
	for entry in entries:views.append(entry)
	return base

## 右向きの升目 → 同じ絵の左向きの升目（5→3、6→2、7→1）。8 は 4 と同じ絵。
const MIRROR_PARTNER:={5:3,6:2,7:1,8:4}
var tile_cache: Dictionary={}          # 升目の絵の hash → 詰めた場所（同じ絵は1回だけ詰める）

## 2つの升目がほぼ同じ絵か（mirror なら b を左右反転して比べる）。32×32 に縮めて平均の差で見る（取り込みの再標本化の誤差は 0.2 程度）。
func similar_cell(a: Image,b: Image,mirror: bool) -> bool:
	var x: Image=a.duplicate();var y: Image=b.duplicate()
	if x.get_format()!=Image.FORMAT_RGBA8:x.convert(Image.FORMAT_RGBA8)
	if y.get_format()!=Image.FORMAT_RGBA8:y.convert(Image.FORMAT_RGBA8)
	if mirror:y.flip_x()
	x.resize(32,32,Image.INTERPOLATE_BILINEAR);y.resize(32,32,Image.INTERPOLATE_BILINEAR)
	var da: PackedByteArray=x.get_data();var db: PackedByteArray=y.get_data()
	var total:=0
	for i in da.size():total+=absi(int(da[i])-int(db[i]))
	return float(total)/float(da.size())<1.5

## まったく同じ絵の升目は1回だけ詰める。
## GPU に送る動作のページ。motion_half なら 16bit に変換した写しを返す。
func gpu_motion(image: Image) -> Image:
	if not motion_half:return image
	var copy: Image=image.duplicate()
	copy.convert(Image.FORMAT_RGBAH)
	return copy

func motion_texel_bytes() -> int:
	return 8 if motion_half else 16

func pack_shared(cell: Image) -> Dictionary:
	var key:=hash(cell.get_data())
	if tile_cache.has(key):return tile_cache[key].duplicate()
	var entry: Dictionary=pack(cell,false)
	tile_cache[key]=entry
	return entry.duplicate()

func face_view_base(recipe: Dictionary) -> int:
	var key:=face_key(recipe)
	if face_cache.has(key):return face_cache[key]
	if Looks.enabled:
		var head:int=int(recipe.modules.head)
		var baked:Dictionary=Looks.face(head,key)
		# 焼いていない表情は、その頭の通常の顔で代える。
		if baked.is_empty() and not recipe.get("expression",{}).is_empty():
			var plain:Dictionary=recipe.duplicate();plain.erase("expression")
			baked=Looks.face(head,face_key(plain))
		if not baked.is_empty():
			var tiles:Dictionary={}
			for v in baked.tiles:tiles[int(v)]=Looks.decode(baked.tiles[v])
			return append_face(recipe,{"ok":true,"tiles":tiles})
	var result:=FaceComposer.compose(recipe,catalog.configs,source_images)
	if not result.ok:last_error=str(result);return -1
	if Looks.recording:
		var saved:Dictionary={}
		for v in result.tiles:saved[int(v)]=Looks.encode(result.tiles[v])
		Looks.put(Looks.file_of(int(recipe.modules.head)),"face",key,{"tiles":saved})
	return append_face(recipe,result)

func append_face(recipe: Dictionary, result: Dictionary) -> int:
	var tiles: Dictionary={}
	for v in result.tiles:tiles[v]=pack(result.tiles[v],true)
	var base:=views.size()
	for v in range(9):
		var source: int=2 if v==6 else (1 if v==7 else (3 if v==5 else v))
		var entry: Dictionary=tiles[source].duplicate()
		entry.mirror=v in [5,6,7];views.append(entry)
	face_cache[face_key(recipe)]=base;dirty=true
	return base

func publish_face(recipe: Dictionary, result: Dictionary) -> Dictionary:
	if face_cache.has(face_key(recipe)):return {"ok":true,"base":face_cache[face_key(recipe)]}
	if not result.get("ok",false):return result
	# Check capacity before mutation. Resident arrays never reallocate in gameplay.
	if face_cell+result.tiles.size()>face_images.size()*16 or views.size()+9>VIEW_CAPACITY:
		return {"ok":false,"code":"FACE_RESERVE_EXHAUSTED","message":"Re-prepare outside gameplay to reserve more pages."}
	var first_layer: int=face_cell/16
	var base:=append_face(recipe,result)
	for layer in range(first_layer,(face_cell-1)/16+1):face_texture.update_layer(face_images[layer],layer)
	write_view_table(base)
	view_texture.update(gpu_table(view_image))
	view_written=views.size()
	return {"ok":true,"base":base}

func write_view_table(start: int=0) -> void:
	for i in range(start,views.size()):
		var v: Dictionary=views[i]
		view_image.set_pixel(0,i,Color(v.rect.x,v.rect.y,v.rect.z,v.rect.w))
		view_image.set_pixel(1,i,Color(v.layer,1 if v.mirror else 0,0,0))

func bind_actor(row: int, recipe: Dictionary, rest: Array) -> void:
	face_overrides.erase(row);set_state(row,4,Vector4.ZERO)
	var attachment:Dictionary=Neck.for_recipe(recipe)
	for v in range(9):
		var socket:=Color(0,0,0,0)
		if not attachment.is_empty():socket=Color(attachment.head[v][0],attachment.head[v][1],attachment.collar[v][0],attachment.collar[v][1])
		binding.set_pixel(96+v,row,socket)
	binding.set_pixel(105,row,Color(float(attachment.get("length",.035)),0,0,0))
	var extension:=pelvis_extension(recipe)
	for d in range(8):binding.set_pixel(EXTENSION_COLUMN+d,row,Color(extension[d],0,0,0))
	bind_soft(row,recipe,extension)
	bind_props(row,recipe)
	var face_base := face_view_base(recipe)
	assert(face_base>=0,last_error)
	for slot in range(Catalog.SLOTS.size()):
		var source := catalog.source_for(recipe,slot)
		var config: Dictionary = catalog.configs[source]
		var group:String=Catalog.GROUPS[slot]
		var shape:Dictionary=recipe.get("resolved_shape",{})
		var s: Dictionary = shape.get("surface",{}).get(group,config.surface[group])
		var raw: Vector3 = rest[slot]
		var fixed: bool = s.has("radii")
		var r := Vector3(s.radii[0],s.radii[1],s.radii[2]) if fixed else raw*Vector3(s.scale[0],s.scale[1],s.scale[2])
		# Sprite dimensions follow the chosen skeleton, including random body proportions.
		var body: Dictionary=recipe.profile
		var reference: Dictionary=shape.get("reference",{}).get(group,config.profile)
		if slot in [1,2]:r.y*=float(body.torso)/float(reference.torso)
		if slot==2:r.x*=float(body.shoulder)/float(reference.shoulder)
		if slot in [0,1,21,22]:r.x*=float(body.hip_width)/float(reference.hip_width)
		var mult:Array=s.get("multiplier",[1,1,1])
		r*=Vector3(mult[0],mult[1],mult[2])
		if slot==4: r*=recipe.head_scale
		else: r*=Vector3(recipe.thickness,1,recipe.thickness)
		var off: Array = s.get("offset",[0,0,0])
		var offset := Vector3(off[0],off[1],off[2])
		var registration_slot:String="pelvis" if slot in [21,22] else Catalog.SLOTS[slot]
		var adjustment: Array = recipe.registration.get(registration_slot,[0,0,0,1,1])
		offset += Vector3(adjustment[0],adjustment[1],adjustment[2])
		r *= Vector3(adjustment[3],adjustment[4],adjustment[3])
		if slot==3 and attachment.has("width"):r.x=float(attachment.width)*recipe.thickness
		shape_edges.set_pixel(slot,row,Color(1,1,1,1))
		if s.has("proximal_radii"):
			var proximal:Array=s.proximal_radii
			shape_edges.set_pixel(slot,row,Color(float(proximal[0])*recipe.thickness/r.x,float(proximal[1])*recipe.thickness/r.z,1,1))
		if not shape.is_empty() and slot in [0,1,21,22]:
			var target:Vector2=Vector2(shape.waist[0],shape.waist[1])*float(recipe.thickness)
			var ratio:Vector2=target/Vector2(r.x,r.z)
			shape_edges.set_pixel(slot,row,Color(1,1,ratio.x,ratio.y) if slot==1 else Color(ratio.x,ratio.y,1,1))
		binding.set_pixel(slot*4,row,Color(r.x,r.y,r.z,0 if fixed else 1))
		binding.set_pixel(slot*4+1,row,Color(offset.x,offset.y,offset.z,1 if slot in [0,1,21,22] else 0))
		var base: int = face_base if slot==4 else module_view_base(recipe,slot)
		binding.set_pixel(slot*4+2,row,Color(base,source*9,0,0))
		if slot==4 and not attachment.is_empty():binding.set_pixel(slot*4+2,row,Color(base,source*9,1,0))
		var warp: Dictionary = config.head_pitch_warp
		binding.set_pixel(slot*4+3,row,Color(0,warp.reference,warp.strength,warp.maximum))
		if slot!=4:
			var join:Dictionary=s.get("joint_anchor",config.get("joint_anchors",{}).get(Catalog.GROUPS[slot],joint_template.parts.get(Catalog.GROUPS[slot],{})))
			if not join.is_empty():
				binding.set_pixel(slot*4+2,row,Color(base,source*9,join.proximal[0],join.proximal[1]))
				binding.set_pixel(slot*4+3,row,Color(join.distal[0],join.distal[1],join.strength,join.mode))
			else:binding.set_pixel(slot*4+3,row,Color(0,0,0,0))
	dirty = true

func add_track(track: Dictionary) -> int:
	if not track.get("ok",false): last_error=str(track);return -1
	if track_cache.has(track.key): return track_cache[track.key]
	var required: int = track.frames.size()*128
	if required > 65536: last_error="CAPACITY_EXCEEDED: track >512 frames";return -1
	if motion_cursor+required > 65536:
		if motion_images.size()>=motion_page_limit: last_error="CAPACITY_EXCEEDED: Motion%dMiB"%motion_page_limit;return -1
		motion_images.append(Image.create(256,256,false,Image.FORMAT_RGBAF))
		motion_cursor=0
	var layer := motion_images.size()-1
	track = track.duplicate(false)
	# Older baked clips predate the independent neck's occlusion rules.
	if track.has("orders"):
		track.orders=track.orders.duplicate(true)
		for direction in range(track.orders.size()):
			for frame in range(track.orders[direction].size()):track.orders[direction][frame]=Neck.order_slots(track.orders[direction][frame])
	# All expression images are composed before commit. The renderer only selects
	# an existing ViewTable base; no image allocation or blending at a face key.
	track.face_events=[]
	for event in track.get("face_timeline",[]):
		var face_base:=face_view_base(event.recipe)
		if face_base<0:return -1
		track.face_events.append({"t":float(event.t),"base":face_base})
	var capacity_error:=validate_capacity()
	if not capacity_error.is_empty():last_error=capacity_error;return -1
	track.base=motion_cursor
	track.layer=layer
	for f in range(track.frames.size()):
		for slot in range(track.frames[f].parts.size()):
			var part: Dictionary = track.frames[f].parts[slot]
			var pos: Vector3 = part.center
			var q: Quaternion = part.rotation
			var d: Vector3 = part.radii/track.rest_radii[slot]
			var anchor:Vector3=part.get("anchor",pos)
			var soft:Vector3=soft_value(track.frames[f].parts,slot)
			var fields := [Color(pos.x,pos.y,pos.z,soft.x),Color(q.x,q.y,q.z,q.w),Color(d.x,d.y,d.z,soft.y),Color(anchor.x,anchor.y,anchor.z,soft.z)]
			for field in range(4):
				var address: int = motion_cursor+f*128+slot*4+field
				motion_images[layer].set_pixel(address%256,address/256,fields[field])
	motion_cursor+=required
	track.erase("frames")
	var index := tracks.size()
	tracks.append(track)
	track_cache[track.key]=index
	dirty=true
	return index

## 32bit 浮動小数の表（RGBAF）を、同じバイト列のまま 8bit×4 の画素（RGBA8、横4倍）として GPU へ送る形にする。
## iPhone など 32bit 浮動小数のテクスチャを使えない端末でも値が変わらない（シェーダーの fetch32 が元に戻す）。
static func gpu_table(image: Image) -> Image:
	assert(image.get_format()==Image.FORMAT_RGBAF)
	return Image.create_from_data(image.get_width()*4,image.get_height(),false,Image.FORMAT_RGBA8,image.get_data())

static func gpu_bytes(width: int,height: int,bytes: PackedByteArray) -> Image:
	return Image.create_from_data(width*4,height,false,Image.FORMAT_RGBA8,bytes)

func material_for(row: int) -> ShaderMaterial:
	var m: ShaderMaterial=row_materials.get(row)
	if m==null:
		m=material.duplicate();m.set_shader_parameter("actor_row",row);row_materials[row]=m
	return m

## 材質の値を、元と行ごとの材質の全部へ入れる。
func set_param(name: String,value: Variant) -> void:
	material.set_shader_parameter(name,value)
	for row in row_materials:row_materials[row].set_shader_parameter(name,value)

## 絵・表を GPU へ送る。前に作ったテクスチャは作り直さず、書き換えたところだけ送る
## （ページが増えたときだけ作り直す）。ブラウザ版では毎回 48MB の絵を送り直すと重いため。
func commit() -> void:
	if not dirty:return
	if shape_texture==null:
		shape_texture=ImageTexture.create_from_image(gpu_table(shape_edges));set_param("shape_edges",shape_texture)
	else:shape_texture.update(gpu_table(shape_edges))
	var reserved:=mini(64,ceili(float(face_cell)/16.0)+4)
	while face_images.size()<reserved:face_images.append(Image.create(512,512,false,Image.FORMAT_RGBA8))
	var motion := Texture2DArray.new()
	# 分けて読む動作（stream）では、まだ誰も結び付けていないうちに作ることがある。
	if body_images.is_empty():body_images.append(Image.create(2048,2048,false,Image.FORMAT_RGBA8))
	# assert の中に書くと書き出した版（リリース版）では実行されないので、作ってから確かめる。
	if body_texture==null or body_texture.get_layers()!=body_images.size():
		body_texture=Texture2DArray.new()
		var made_body:=body_texture.create_from_images(body_images);assert(made_body==OK)
		set_param("body_pages",body_texture)
	else:
		for l in dirty_body:body_texture.update_layer(body_images[l],l)
	dirty_body.clear()
	if face_texture==null or face_texture.get_layers()!=face_images.size():
		face_texture=Texture2DArray.new()
		var made_face:=face_texture.create_from_images(face_images);assert(made_face==OK)
		set_param("face_pages",face_texture)
	else:
		for l in dirty_face:face_texture.update_layer(face_images[l],l)
	dirty_face.clear()
	var new_motion:=true
	if stream_mode:
		# 動作のページは最初に一度だけ作り、あとは書き換えたページだけ送る（flush_uploads）。
		if motion_texture==null:
			var pages: Array[Image]=[]
			for b in page_bytes:pages.append(gpu_motion(Image.create_from_data(256,256,false,Image.FORMAT_RGBAF,b)))
			var made_motion:=motion.create_from_images(pages);assert(made_motion==OK)
			dirty_layers.clear()
		else:motion=motion_texture;new_motion=false
	else:
		var gpu_pages: Array[Image]=[]
		for image in motion_images:gpu_pages.append(gpu_motion(image))
		var made_pages:=motion.create_from_images(gpu_pages);assert(made_pages==OK)
	if view_texture==null or view_written>views.size():
		view_image=Image.create(2,VIEW_CAPACITY,false,Image.FORMAT_RGBAF)
		write_view_table()
		view_texture=ImageTexture.create_from_image(gpu_table(view_image));set_param("view_table",view_texture)
	else:
		write_view_table(view_written);view_texture.update(gpu_table(view_image))
	view_written=views.size()
	if new_motion:set_param("motion_pages",motion)
	motion_texture=motion
	if binding_texture==null:
		binding_texture=ImageTexture.create_from_image(gpu_table(binding));set_param("binding_table",binding_texture)
	else:binding_texture.update(gpu_table(binding))
	if chart_texture==null:
		chart_texture=ImageTexture.create_from_image(gpu_table(chart));set_param("chart_table",chart_texture)
	memory_bytes=body_images.size()*2048*2048*4+face_images.size()*512*512*4+maxi(motion_images.size(),page_bytes.size())*256*256*motion_texel_bytes()+binding.get_data_size()+shape_edges.get_data_size()+chart.get_data_size()+view_image.get_data_size()+16384
	dirty=false
	# Raw legacy atlases are reloadable preparation data, not runtime dependencies.
	source_images.clear()

# ───────── 分けて読む動作（game_v2/animation/pack.gd の packs） ─────────
# 動作テクスチャを決まった枚数のページで持ち、トラックを空いている場所へ写す。使わなくなったら場所を返す。
# 起動時に全部を載せないので、起動時間と上限がキャラ・場面の総数に左右されない。
const PAGE_TEXELS:=65536
var stream_mode:=false
var page_bytes: Array=[]        # ページごとの生のバイト列（1ページ 1MiB）
var page_free: Array=[]         # ページごとの空き [[始まり, 終わり], …]（テクセル）
var dirty_layers: Dictionary={} # 送り直すページ
var resident: Dictionary={}     # 載っているトラック

func begin_stream(pages: int) -> void:
	stream_mode=true
	motion_images=[];page_bytes=[];page_free=[]
	for i in pages:
		var b:=PackedByteArray();b.resize(PAGE_TEXELS*16)
		page_bytes.append(b);page_free.append([[0,PAGE_TEXELS]])

func allocate(need: int) -> Vector2i:
	for l in page_free.size():
		var ranges: Array=page_free[l]
		for i in ranges.size():
			var r: Array=ranges[i]
			if int(r[1])-int(r[0])>=need:
				var start: int=int(r[0])
				if int(r[1])-start==need:ranges.remove_at(i)
				else:r[0]=start+need
				return Vector2i(l,start)
	return Vector2i(-1,-1)

func release_range(layer: int,start: int,length: int) -> void:
	var ranges: Array=page_free[layer]
	ranges.append([start,start+length])
	ranges.sort_custom(func(a,b):return int(a[0])<int(b[0]))
	var merged: Array=[]
	for r in ranges:
		if not merged.is_empty() and int(merged[-1][1])>=int(r[0]):merged[-1][1]=maxi(int(merged[-1][1]),int(r[1]))
		else:merged.append([int(r[0]),int(r[1])])
	page_free[layer]=merged

## packs のトラックを載せる。返り値はトラック番号（同じ key なら前と同じ番号）。-2 は空きがない（呼び出し側が外してから呼び直す）。
func add_track_packed(meta: Dictionary,raw: PackedByteArray) -> int:
	var key: String=str(meta.get("key",""))
	var id: int=int(track_cache.get(key,-1))
	if id>=0 and resident.has(id):return id
	var need: int=raw.size()/16
	if need>PAGE_TEXELS:last_error="CAPACITY_EXCEEDED: track >512 frames";return -1
	var at:=allocate(need)
	if at.x<0:last_error="MOTION_FULL";return -2
	var pb: PackedByteArray=page_bytes[at.x]
	var off: int=at.y*16
	page_bytes[at.x]=pb.slice(0,off)+raw+pb.slice(off+raw.size())
	dirty_layers[at.x]=true
	var track: Dictionary=meta.duplicate(false)
	track.face_events=[]
	for event in track.get("face_timeline",[]):
		var face_base:=face_view_base(event.recipe)
		if face_base<0:release_range(at.x,at.y,need);return -1
		track.face_events.append({"t":float(event.t),"base":face_base})
	track.base=at.y;track.layer=at.x;track.texels=need
	if id<0:
		id=tracks.size();tracks.append(track);track_cache[key]=id
	else:tracks[id]=track
	resident[id]=true
	return id

## 載せたトラックを外す（番号は残る。もう一度 add_track_packed で同じ番号に載る）。
func release_track(id: int) -> void:
	if not resident.has(id):return
	var t: Dictionary=tracks[id]
	release_range(int(t.layer),int(t.base),int(t.texels))
	resident.erase(id)

## 書き換えた動作のページだけを GPU へ送る（毎フレーム呼んでよい）。
func flush_uploads() -> void:
	if dirty_layers.is_empty() or motion_texture==null:return
	for l in dirty_layers:
		motion_texture.update_layer(gpu_motion(Image.create_from_data(256,256,false,Image.FORMAT_RGBAF,page_bytes[l])),l)
	dirty_layers.clear()

func free_texels() -> int:
	var n:=0
	for ranges in page_free:
		for r in ranges:n+=int(r[1])-int(r[0])
	return n

func update_binding() -> void:
	if binding_texture!=null:binding_texture.update(gpu_table(binding))
	if shape_texture!=null:shape_texture.update(gpu_table(shape_edges))
	dirty=false

func validate_capacity() -> String:
	var bytes:=body_images.size()*2048*2048*4+maxi(face_images.size(),mini(64,ceili(float(face_cell)/16.0)+4))*512*512*4+motion_images.size()*256*256*motion_texel_bytes()+binding.get_data_size()+shape_edges.get_data_size()+chart.get_data_size()+VIEW_CAPACITY*32+16384
	if bytes>texture_budget_mib*1048576:return "CAPACITY_EXCEEDED: texture data >%dMiB"%texture_budget_mib
	if views.size()>VIEW_CAPACITY:return "CAPACITY_EXCEEDED: ViewTable"
	if face_images.size()>64:return "CAPACITY_EXCEEDED: face pages >64MiB"
	return ""

func write_live(track_id: int, parts: Array) -> void:
	var track: Dictionary=tracks[track_id]
	for slot in range(parts.size()):
		var part: Dictionary=parts[slot]
		var p: Vector3=part.center
		var q: Quaternion=part.rotation
		var r: Vector3=part.radii/track.rest_radii[slot]
		for k in range(2):
			var address: int=track.base+k*128+slot*4
			var anchor:Vector3=part.get("anchor",p)
			var soft:Vector3=soft_value(parts,slot)
			var fields: Array=[Color(p.x,p.y,p.z,soft.x),Color(q.x,q.y,q.z,q.w),Color(r.x,r.y,r.z,soft.y),Color(anchor.x,anchor.y,anchor.z,soft.z)]
			for f in range(4):motion_images[track.layer].set_pixel((address+f)%256,(address+f)/256,fields[f])
	motion_texture.update_layer(gpu_motion(motion_images[track.layer]),track.layer)

## 胸・尻の左右の遅れ（親ローカル）。w成分の置き場所：胸の左=胸(2)、胸の右=腹(1)、尻の左=pelvis_l(21)、尻の右=pelvis_r(22)。
## 動作テクスチャの配置（1フレーム128texel）は変えない。以前はw成分に定数が入っていたが、描画側は読んでいない。
static func soft_value(parts:Array,slot:int)->Vector3:
	var source:Dictionary={2:[2,"soft",0],1:[2,"soft",1],21:[0,"soft_butt",0],22:[0,"soft_butt",1]}
	if not source.has(slot) or parts.size()<=source[slot][0]:return Vector3.ZERO
	var soft=parts[source[slot][0]].get(source[slot][1],null)
	if soft==null or not soft is Array or soft.size()<2:return Vector3.ZERO
	return soft[source[slot][2]]

## 変形領域。束縛表の列 開始列+向き*2+(0=左,1=右) に (u,v,半径u,半径v)、開始列+16 に (潰れの強さ,揺れの倍率,確認用の色,0)。
## soft.<種類>.regions は向き "0"〜"4" に [[左の領域],[右の領域]]（左右は体の左右、u,v は親の画像の0〜1）。
## 向き 5〜7 は 3〜1 を左右反転して作る。
const SOFT_COLUMNS:={"breast":106,"butt":124}
const EXTENSION_COLUMN:=141
## 骨盤画像の下への延長量（表示の向き0〜7）。recipe.part_extension.pelvis は元画像の向き（STANDARD の番号）ごと。
## 延長 e の向きでは、画像の上から 1/(1+e) が以前の範囲で、その下に尻の下側と裾が続く。
func pelvis_extension(recipe:Dictionary)->Array:
	var result:Array=[0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
	var table:Dictionary=recipe.get("part_extension",{}).get("pelvis",{})
	if table.is_empty():return result
	var config:Dictionary=catalog.configs[catalog.source_for(recipe,0)]
	for d in range(8):result[d]=float(table.get(str(preload("res://mini/layered2d/data/source_views.gd").source(config,d)),0.0))
	return result

## 胸・尻の大きさの倍率（素体規格の体型の値。1が標準）。領域の中の網目を広げ縮めする。
const SOFT_SIZE_COLUMN:=149
func bind_soft(row:int,recipe:Dictionary,extension:Array=[])->void:
	for kind in SOFT_COLUMNS:bind_soft_kind(row,recipe.get("soft",{}).get(kind,{}),SOFT_COLUMNS[kind],extension if kind=="butt" else [])
	binding.set_pixel(SOFT_SIZE_COLUMN,row,Color(float(recipe.get("breast",1.0)),float(recipe.get("butt",1.0)),0,0))

func bind_soft_kind(row:int,soft:Dictionary,column:int,extension:Array=[])->void:
	for c in range(column,column+17):binding.set_pixel(c,row,Color(0,0,0,0))
	var regions:Dictionary=soft.get("regions",{})
	if regions.is_empty():return
	for d in range(8):
		var source:int=d if d<=4 else 8-d
		var mirror:bool=d>4
		var entry:Array=regions.get(str(source),[])
		for side in range(2):
			var index:int=(1-side) if mirror else side
			if index>=entry.size() or not entry[index] is Array or entry[index].size()<3:continue
			var r:Array=entry[index]
			var u:float=float(r[0]);var ry:float=float(r[3]) if r.size()>3 else float(r[2])
			# 尻の領域は延長前の画像で登録している。延長した向きでは縦を縮めて同じ場所を指す。
			var scale:float=1.0/(1.0+float(extension[d])) if extension.size()==8 else 1.0
			binding.set_pixel(column+d*2+side,row,Color(1.0-u if mirror else u,float(r[1])*scale,float(r[2]),ry*scale))
	binding.set_pixel(column+16,row,Color(float(soft.get("squash",1.0)),float(soft.get("gain",1.0)),float(soft.get("debug",0.0)),float(soft.get("pin_bottom",0.0))))

# ───────── 付属物（docs/素材制作テンプレート/付属物の規格.md） ─────────
## recipe.props = {枠名: 定義}。定義は game_v2 の props.json を解決したもの：
##   {kind: weapon|shield|ears|tail|groin, dir: 画像のフォルダ, views: 3|5, canvas:[w,h], anchor:[x,y]（付け根のピクセル）,
##    scale: 1ピクセルの world 長さ, states: ["rest","erect"]（groin。2つ目は <dir>/erect/ に置く）, sway: {amount, rate}（tail）}
## 列（PROP_COLUMN+(枠-23)*4）：0 半径（固定）、1 絵の中心のずらし（親ローカル）、2 (向きの表の先頭, 状態の数, 0, 0)、3 (揺れ幅, 揺れの速さ, 耳の上への広がり, 0)。
## 付けていない枠は半径0（描かれない）。耳は頭の半径・位置・首の補正を使い、2 と 3 だけを使う。
const EARS_EXTENSION:=0.5
const PROP_DEFAULT_SCALE:=0.003
func bind_props(row:int,recipe:Dictionary)->void:
	var props:Dictionary=recipe.get("props",{})
	for i in range(Catalog.PROP_SLOTS.size()):
		var slot_name:String=Catalog.PROP_SLOTS[i]
		var column:int=PROP_COLUMN+i*4
		for c in range(4):binding.set_pixel(column+c,row,Color(0,0,0,0))
		shape_edges.set_pixel(Catalog.PROP_BASE+i,row,Color(1,1,1,1))
		var def=props.get(slot_name,null)
		if not def is Dictionary or def.is_empty():continue
		var base:=prop_view_base(recipe,def)
		if base<0:continue
		var states:int=maxi(1,def.get("states",[]).size())
		binding.set_pixel(column+2,row,Color(base,states,0,0))
		if str(def.kind)=="ears":
			binding.set_pixel(column+3,row,Color(0,0,EARS_EXTENSION,0))
			binding.set_pixel(column,row,Color(1,1,1,0)) # 付けている印（半径は頭のものを使う）
			continue
		var canvas:Array=def.get("canvas",[256,256]);var anchor:Array=def.get("anchor",[128,16])
		var px:float=float(def.get("scale",PROP_DEFAULT_SCALE))
		var w:float=float(canvas[0])*px;var h:float=float(canvas[1])*px
		# 奥行きの半径：尻尾・男性器は丸い（横から見ても同じ太さ）、武器・盾は薄い。
		var depth:float=w*0.5 if str(def.kind) in ["tail","groin"] else w*0.15
		binding.set_pixel(column,row,Color(w*0.5,h*0.5,depth,0))
		# 絵の中心は付け根から見て (幅の中心 − 付け根x, 付け根y − 高さの中心)。画像の下向きは親ローカルの −Y。
		var dx:float=(float(canvas[0])*0.5-float(anchor[0]))*px
		var dy:float=(float(anchor[1])-float(canvas[1])*0.5)*px
		binding.set_pixel(column+1,row,Color(dx,dy,0,1))
		var sway:Dictionary=def.get("sway",{})
		binding.set_pixel(column+3,row,Color(float(sway.get("amount",0.0)),float(sway.get("rate",0.0)),0,0))

## 付属物の絵を向きの表（9方向）に積む。状態が2つなら続けて9つ。同じ定義はまとめて使い回す。
## 5枚：素材の番号は正面・斜め前・横・背面・斜め後ろ（体と同じ）。3枚：面・斜め・縁（背面側は反転で使う）。
func prop_view_base(recipe:Dictionary,def:Dictionary)->int:
	var key:="prop/"+Catalog.fingerprint([def,recipe.get("modules",{}).get("head",0) if str(def.kind)=="ears" else 0])
	if body_views.has(key):return body_views[key]
	if Looks.enabled:
		var baked:Dictionary=Looks.prop(key)
		if not baked.is_empty():
			var base_l:=views.size()
			for st in baked.states:
				var packed:Array=[]
				for bytes in st.cells:packed.append(pack(Looks.decode(bytes),false))
				for m in st.map:
					var e:Dictionary=packed[int(m[0])].duplicate();e.mirror=bool(m[1]);views.append(e)
			body_views[key]=base_l;dirty=true
			return base_l
	var states:Array=def.get("states",[""])
	if states.is_empty():states=[""]
	var base:=views.size()
	var baking:Array=[]
	for s in range(states.size()):
		var folder:String=str(def.dir)+("" if s==0 else "/"+str(states[s]))
		var sources:Array=[]
		for i in range(int(def.get("views",5))):
			var path:String=folder+"/single-%d.png"%(i+1)
			if not FileAccess.file_exists(path):last_error="付属物の絵がない: "+path;return -1
			sources.append(load_image(path))
		if str(def.kind)=="ears":sources=ears_tiles(recipe,sources)
		if Looks.recording:
			var cells:Array=[];var map:Array=[]
			for image in sources:cells.append(Looks.encode(shrink(image)))
			for v in range(9):map.append(prop_source(v,sources.size()))
			baking.append({"cells":cells,"map":map})
		for v in range(9):
			var pick:Array=prop_source(v,sources.size())
			var entry:Dictionary=pack(sources[pick[0]],false)
			entry.mirror=pick[1]
			views.append(entry)
	body_views[key]=base;dirty=true
	if Looks.recording:Looks.put("common","prop",key,{"states":baking})
	return base

## 表示の向き（0〜8）→ [素材の番号, 反転]。
static func prop_source(v:int,count:int)->Array:
	if count>=5:
		# 体と同じ（source_views.gd の RUNTIME）：0正面 1斜め前 2横 3斜め後ろ 4背面 5〜7は3〜1の反転 8真上は背面
		return [[0,false],[1,false],[2,false],[4,false],[3,false],[4,true],[2,true],[1,true],[3,false]][v]
	# 面・斜め・縁の3枚。背面側は面と斜めの反転。
	return [[0,false],[1,false],[2,false],[1,true],[0,true],[1,false],[2,true],[1,true],[2,false]][v]

## 耳の絵（頭と同じ横幅、頭の上に128px足した 256×384）を、頭の図集と同じ切り出しで 256×256 に直す。
## 頭の図集は登録枠を余白8pxの枠いっぱいに広げている。耳はそれを上へ EARS_EXTENSION（頭の枠の高さの割合）だけ広げた範囲。
func ears_tiles(recipe:Dictionary,sources:Array)->Array:
	var config:Dictionary=catalog.configs[catalog.source_for(recipe,4)]
	var registration=JSON.parse_string(FileAccess.get_file_as_string(str(config.get("layered2d_registration",""))))
	var refs:Array=registration.get("references",{}).get("heads",[]) if registration is Dictionary else []
	var out:Array=[]
	for i in range(sources.size()):
		var image:Image=sources[i]
		var rect:Array=refs[i].rect if i<refs.size() else [8,8,240,240]
		var mx:float=float(rect[2])*8.0/240.0;var my:float=float(rect[3])*8.0/240.0
		var th:float=float(rect[3])+2.0*my
		var region:=Rect2(float(rect[0])-mx,float(rect[1])-my-th*EARS_EXTENSION+128.0,float(rect[2])+2.0*mx,th*(1.0+EARS_EXTENSION))
		var tile:=Image.create(256,256,false,Image.FORMAT_RGBA8)
		var src_rect:=Rect2i(region.position.round(),region.size.round()).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		if src_rect.size.x>0 and src_rect.size.y>0:
			var part:Image=image.get_region(src_rect)
			var scale:=Vector2(256.0/region.size.x,256.0/region.size.y)
			part.resize(maxi(1,int(round(src_rect.size.x*scale.x))),maxi(1,int(round(src_rect.size.y*scale.y))),Image.INTERPOLATE_LANCZOS)
			tile.blit_rect(part,Rect2i(Vector2i.ZERO,part.get_size()),Vector2i(((Vector2(src_rect.position)-region.position)*scale).round()))
		out.append(tile)
	return out

## 衣装差分。bind_actor の後、commit の前に呼ぶ。
## outfits = {衣装名: {部位グループ(chest/abdomen/pelvis/thigh/…): {"0".."8": 画像パス}}}
## 差分の画像を ViewTable に登録し、行ごとに「どの部位をどの画像にするか」を持つ。切り替えは apply_outfit。
var outfit_bases:Dictionary={}   # row -> {衣装名: {slot: base}}
var default_bases:Dictionary={}  # row -> {slot: base}
var row_outfit:Dictionary={}     # row -> 今の衣装名（"" は元の服）
func bind_outfits(row:int,recipe:Dictionary,outfits:Dictionary)->void:
	var defaults:Dictionary={}
	for slot in range(Catalog.SLOTS.size()):
		if slot!=4:defaults[slot]=int(binding.get_pixel(slot*4+2,row).r)
	default_bases[row]=defaults;outfit_bases[row]={};row_outfit[row]=""
	for name in outfits:
		var variant:Dictionary=recipe.duplicate(true)
		var modules:Dictionary=variant.get("asset_modules",{}).duplicate(true)
		for group in outfits[name]:
			var index:int=Catalog.GROUPS.find(str(group))
			if index<0:continue
			var module:String=Catalog.MODULES[index]
			if not modules.get(module) is Dictionary:modules[module]={}
			if not modules[module].get("groups") is Dictionary:modules[module].groups={}
			modules[module].groups[str(group)]=outfits[name][group]
		variant.asset_modules=modules
		var bases:Dictionary={}
		for slot in range(Catalog.SLOTS.size()):
			if slot!=4 and outfits[name].has(Catalog.GROUPS[slot]):bases[slot]=module_view_base(variant,slot)
		outfit_bases[row][str(name)]=bases
	dirty=true

## 行の衣装を切り替える。"" で元の服。その原型に無い衣装名なら何もしない。変わったら true（update_binding が要る）。
func apply_outfit(row:int,name:String)->bool:
	if row_outfit.get(row,"")==name:return false
	if name!="" and not outfit_bases.get(row,{}).has(name):return false
	for slot in default_bases.get(row,{}):set_binding_base(row,slot,default_bases[row][slot])
	if name!="":
		for slot in outfit_bases[row][name]:set_binding_base(row,slot,outfit_bases[row][name][slot])
	row_outfit[row]=name
	return true

func set_binding_base(row:int,slot:int,base:int)->void:
	var pixel:Color=binding.get_pixel(slot*4+2,row)
	pixel.r=float(base)
	binding.set_pixel(slot*4+2,row,pixel)

## 焼いた場面の衣装の時間切り替え（track.outfit_timeline = [{t, outfit}]、場面の位相）。変わったら true。
func apply_outfit_track(row:int,track_id:int,phase:float)->bool:
	var events:Array=tracks[track_id].get("outfit_timeline",[])
	if events.is_empty():return false
	var chosen:String=""
	for event in events:
		if float(event.t)<=clampf(phase,0,1):chosen=str(event.outfit)
	return apply_outfit(row,chosen)

func set_state(row: int, field: int, value: Vector4) -> void:
	var start := (row*8+field)*4
	state_data[start]=value.x;state_data[start+1]=value.y;state_data[start+2]=value.z;state_data[start+3]=value.w

## 行ごとの顔の読み替え {row: {"map": {元の顔の番号: 新しい顔の番号}, "neutral": 新しい頭の素の顔}}（部品の着せ替え、game_v2/animation/parts.gd）。
var face_remap:Dictionary={}

func apply_face_track(row:int,track_id:int,phase:float)->void:
	var track:Dictionary=tracks[track_id]
	var events:Array=track.get("face_events",[])
	if events.is_empty():
		if face_overrides.has(row):face_overrides.erase(row);set_state(row,4,Vector4.ZERO)
		return
	var offset:float=track.get("face_phase_offset",0.0)
	var p:=clampf(phase,0,1) if offset==0 or offset==1 else fposmod(clampf(phase,0,1)-offset,1.0)
	var low:=0;var high:=events.size()
	while low+1<high:
		var mid:int=(low+high)/2
		if events[mid].t<=p:low=mid
		else:high=mid
	var base:int=events[low].base
	# 頭を別のキャラの部品に替えた行：焼いた顔の番号を、その頭の同じ表情へ読み替える（無ければその頭の素の顔）。
	if face_remap.has(row):base=int(face_remap[row].map.get(base,face_remap[row].neutral))
	if face_overrides.get(row,-1)!=base:
		face_overrides[row]=base;set_state(row,4,Vector4(base,1,0,0))

func upload_state() -> void:
	state_texture.update(gpu_bytes(8,Catalog.CAPACITY,state_data.to_byte_array()))
	uploads+=1
