extends Node2D
const World = preload("res://mini/layered2d/runtime/world.gd")
const Plans = preload("res://mini/layered2d/render/draw_plan_cache.gd")
var plans:=Plans.new()
var store
var compiled: Dictionary={}
var track_ids: Array=[]
var rows: Array=[]
var nodes: Array[MeshInstance2D]=[]
var signature:=""
var active_runs:=0
var last_error: Dictionary={}
var phase:=0.0
var direction:=0
var free_yaw:=NAN
var pitch:=15.0
var cursor:=0
var pixels_per_unit:=100.0
## 場面全体の大きさの倍率（受け側の身長。素体規格では身長を焼き直さず、場面ごと拡大・縮小する）。
var size_factor:=1.0

## 最後に重ね順を組んだ向き・コマ（同じなら組み直さない）。
var order_key:=-1
func configure(resources, scene_track: Dictionary, ids: Array, actor_rows: Array) -> void:
	store=resources;compiled=scene_track;track_ids=ids;rows=actor_rows;order_key=-1
	build_effects()
	build_walls()

# ───────── 効果の層（汗・紅潮・記号など） ─────────
# compiled.effects = [{actor_index, part, path, offset:[x,y,z], from, to, fade, scale, pulse, rise}, ...]
#   part    部位名（Catalog.SLOTS）。offset は部位のローカル（体の倍率をかける前の単位）
#   from/to 場面の位相で出ている範囲（from>to なら周期をまたぐ）。fade は出入りのフェード幅（位相）
#   scale   画像の倍率（1で pixels_per_unit=100 のとき原寸）。pulse は大きさの脈動（0〜1）、rise は出ている間に上へ動く量（px、100px/単位のとき）
#   layer   "back" なら体より奥に描く（床に置いた桶など、体に重なっても隠さない物）
# 部位より手前に描く（隠れる判定はしない）。焼いた部位の位置を CPU で投影するので、シェーダーと同じ式を使う。
var effect_nodes: Array=[]
static var effect_textures: Dictionary={}

func build_effects() -> void:
	for node in effect_nodes:node.queue_free()
	effect_nodes=[]
	for effect in compiled.get("effects",[]):
		var sprite:=Sprite2D.new();sprite.z_index=-2 if str(effect.get("layer",""))=="back" else 200;sprite.visible=false
		var path: String=str(effect.get("path",""))
		if not effect_textures.has(path):
			var Looks=preload("res://mini/layered2d/prepare/looks.gd")
			var image: Image=null
			if Looks.enabled:image=Looks.effect(path)
			elif FileAccess.file_exists(path):image=Image.load_from_file(ProjectSettings.globalize_path(path))
			if Looks.recording and image!=null:Looks.put("common","effect",path,{"png":Looks.encode(image)})
			effect_textures[path]=ImageTexture.create_from_image(image) if image!=null else null
		sprite.texture=effect_textures[path]
		add_child(sprite);effect_nodes.append(sprite)

## 今の視点の [視線（カメラへ向かう向き）, 画面の右, 画面の上]。
func view_axes() -> Array:
	var yaw:=deg_to_rad(direction*45.0 if is_nan(free_yaw) else free_yaw)
	var tilt:=deg_to_rad(pitch)
	var view:=Vector3(sin(yaw)*cos(tilt),sin(tilt),cos(yaw)*cos(tilt))
	var right:=Vector3(cos(yaw),0,-sin(yaw))
	return [view,right,view.cross(right)]

func update_effects(t: float) -> void:
	if effect_nodes.is_empty():return
	var axes: Array=view_axes()
	var view: Vector3=axes[0];var right: Vector3=axes[1];var up: Vector3=axes[2]
	for i in range(effect_nodes.size()):
		var effect: Dictionary=compiled.effects[i]
		var sprite: Sprite2D=effect_nodes[i]
		var weight: float=effect_weight(effect,phase)
		sprite.visible=weight>0.0 and sprite.texture!=null
		if not sprite.visible:continue
		var actor: int=int(effect.actor_index)
		var part_name: String=str(effect.get("part","head"))
		var frames: Array=compiled.tracks[actor].frames
		var members: Array=compiled.tracks[actor].members
		var ma: Dictionary=members[cursor];var mb: Dictionary=members[mini(cursor+1,members.size()-1)]
		var height: float=lerpf(float(ma.height),float(mb.height),t)
		var root: Vector3=Vector3(ma.root).lerp(Vector3(mb.root),t)
		var turn:=Basis(Vector3.UP,deg_to_rad(lerpf(float(ma.yaw),float(mb.yaw),t)))
		var offset_value: Array=effect.get("offset",[0,0,0])
		if effect.has("offset_keys"):offset_value=keyed(effect.offset_keys,"offset",phase)
		var offset_vector:=Vector3(float(offset_value[0]),float(offset_value[1]),float(offset_value[2]))
		var rotation:=Quaternion.IDENTITY
		var world: Vector3
		if part_name=="root":
			# 足もと（actor の root）に付ける。offset は world 単位で、actor の向きで回る（床に置く物・投げ出す物）。
			world=turn*offset_vector+root
		else:
			var slot: int=preload("res://mini/layered2d/data/catalog.gd").SLOTS.find(part_name)
			var a: Dictionary=frames[cursor].parts[slot];var b: Dictionary=frames[mini(cursor+1,frames.size()-1)].parts[slot]
			var center: Vector3=Vector3(a.center).lerp(Vector3(b.center),t)
			rotation=Quaternion(a.rotation).slerp(Quaternion(b.rotation),t)
			world=turn*((center+rotation*offset_vector)*height)+root
		# facing="front"：部位の前（ローカル+Z）がカメラの反対を向いたら隠す（頬の赤みや吐息が後頭部に出ないように）。
		if str(effect.get("facing",""))=="front" and (turn*(rotation*Vector3(0,0,1))).dot(view)<0.0:
			sprite.visible=false;continue
		var rise: float=float(effect.get("rise",0.0))*span_progress(effect,phase)*pixels_per_unit*size_factor/100.0
		sprite.position=Vector2(world.dot(right),-world.dot(up))*pixels_per_unit*size_factor-Vector2(0,rise)
		var pulse: float=1.0+float(effect.get("pulse",0.0))*sin(phase*TAU*float(effect.get("pulse_rate",2.0)))
		var base_scale: float=float(keyed(effect.scale_keys,"scale",phase)) if effect.has("scale_keys") else float(effect.get("scale",1.0))
		sprite.scale=Vector2.ONE*base_scale*pixels_per_unit*size_factor/100.0*pulse
		sprite.rotation=deg_to_rad(float(keyed(effect.angle_keys,"angle",phase)) if effect.has("angle_keys") else float(effect.get("angle",0.0)))
		sprite.modulate.a=weight

# ───────── 壁（壁尻など） ─────────
# compiled.walls = [{actor_index, offset:[x,y,z], normal:[x,y,z], width, height, thick, hole:[y, 半径], color}, ...]
#   actor の足もとから offset（world、actor の向きで回る）に、厚み thick・幅 width・高さ height の壁を立てる。
#   normal は壁の表の向き（actor のローカル、水平）。hole は表と裏に描く穴の縁（高さ y と半径、world）。
#   カメラの側から見て壁の向こうにある部位（中心が壁の面より向こう）は描かない。壁は体より奥に描くので、
#   壁を通り抜けた体は、見ている側の半分だけが壁の前に出て見える（8方向どこから見ても合う）。
#   壁をほぼ真横から見るとき（|表の向き・視線| < WALL_EDGE）は隠さない（薄い壁の縁が見えるだけ）。
const WALL_EDGE:=0.3
var wall_layer: Node2D
var hidden_parts: Dictionary={}      # actor*32+slot → true（壁の向こうで描かない部位）
var wall_shapes: Array=[]            # 描く壁 [{center, normal, along, wall}]

# ───────── 置物（三角木馬など） ─────────
# compiled.blocks = [{actor_index, shape:"prism"|"box", offset:[x,y,z], yaw, size:[長さ, 幅, 高さ], tri, color, depth_bias}, ...]
#   actor の足もとから offset（world、actor の向きで回る）に置く。yaw は actor に対する向き（度）。長さの向きが actor の前後。
#   prism：高さ size[2] の稜（尾根）と、そこから tri だけ下の幅 size[1] の底の三角柱を、4本の脚で支える（三角木馬）。box：ただの箱。
#   体の部位の間に挟んで描く：部位の中心の奥行きが置物の中心（＋depth_bias）より手前の部位は置物の前、奥の部位は後ろ。
#   またがった脚は、見ている側の脚だけが置物の前に出る。
var block_nodes: Array=[]
var block_shapes: Array=[]
var block_depths: Array=[]
var part_depths: Dictionary={}       # actor*32+slot → 部位の中心の奥行き（大きいほど手前）

# ───────── 線（首輪の鎖・吊り縄など） ─────────
# compiled.lines = [{from_actor, from_slot, to_actor, to_slot, to_point:[x,y,z], color, width, sag}, ...]
#   from の部位の中心から、to の部位の中心（to_slot<0 なら to_actor の足もとから to_point、actor の向きで回る）へ線を引く。
#   width は world 単位の太さ、sag はたるみ（中央の下がり、world）。体より手前に描く。
var line_layer: Node2D
var line_points: Array=[]            # 描く線 [{a:Vector3, b:Vector3, line}]

func build_walls() -> void:
	line_points=[]
	if not compiled.get("lines",[]).is_empty() and line_layer==null:
		line_layer=LineLayer.new();line_layer.group=self;line_layer.z_index=199;add_child(line_layer)
	if line_layer!=null:line_layer.visible=not compiled.get("lines",[]).is_empty()
	for node in block_nodes:node.queue_free()
	block_nodes=[];block_shapes=[];block_depths=[];part_depths={}
	for i in compiled.get("blocks",[]).size():
		var node:=BlockLayer.new();node.group=self;node.index=i;add_child(node);block_nodes.append(node)
	hidden_parts={};wall_shapes=[]
	if compiled.get("walls",[]).is_empty():
		if wall_layer!=null:wall_layer.visible=false
		return
	if wall_layer==null:
		wall_layer=WallLayer.new();wall_layer.group=self;wall_layer.z_index=-1;add_child(wall_layer)
	wall_layer.visible=true

## 役者ごとの {root, turn, height, centers}（部位の中心の world 位置）から、壁の形と隠す部位を決める。
func update_walls(actors: Array) -> void:
	if not compiled.get("blocks",[]).is_empty():update_blocks(actors)
	if not compiled.get("lines",[]).is_empty():update_lines(actors)
	if compiled.get("walls",[]).is_empty():return
	hidden_parts={};wall_shapes=[]
	var view: Vector3=view_axes()[0]
	for wall in compiled.walls:
		var i: int=int(wall.get("actor_index",0))
		if i<0 or i>=actors.size():continue
		var a: Dictionary=actors[i]
		var o: Array=wall.get("offset",[0,0,0]);var nl: Array=wall.get("normal",[0,0,1])
		var center: Vector3=a.turn*Vector3(float(o[0]),float(o[1]),float(o[2]))+a.root
		var normal: Vector3=a.turn*Vector3(float(nl[0]),0.0,float(nl[2]))
		normal=normal.normalized() if normal.length()>0.001 else Vector3.BACK
		wall_shapes.append({"center":center,"normal":normal,"along":normal.cross(Vector3.UP).normalized(),"wall":wall})
		var facing: float=normal.dot(view)
		if absf(facing)<WALL_EDGE:continue
		var side: float=signf(facing)
		for j in actors.size():
			var centers: Array=actors[j].centers
			for slot in centers.size():
				if (Vector3(centers[slot])-center).dot(normal)*side<0.0:hidden_parts[j*32+slot]=true
	if wall_layer!=null:wall_layer.queue_redraw()

func update_blocks(actors: Array) -> void:
	block_shapes=[];block_depths=[];part_depths={}
	var view: Vector3=view_axes()[0]
	for j in actors.size():
		var centers: Array=actors[j].centers
		for slot in centers.size():part_depths[j*32+slot]=Vector3(centers[slot]).dot(view)
	for block in compiled.blocks:
		var i: int=clampi(int(block.get("actor_index",0)),0,maxi(actors.size()-1,0))
		if actors.is_empty():break
		var a: Dictionary=actors[i]
		var o: Array=block.get("offset",[0,0,0])
		var turn: Basis=a.turn*Basis(Vector3.UP,deg_to_rad(float(block.get("yaw",0.0))))
		var center: Vector3=a.turn*Vector3(float(o[0]),float(o[1]),float(o[2]))+a.root
		var size: Array=block.get("size",[1.0,0.3,0.8])
		var fwd: Vector3=turn*Vector3(0,0,1)
		block_shapes.append({"center":center,"fwd":fwd,"side":fwd.cross(Vector3.UP).normalized(),"block":block})
		block_depths.append((center+Vector3.UP*float(size[2])*0.85).dot(view)+float(block.get("depth_bias",-0.05)))
	for node in block_nodes:node.queue_redraw()

func update_lines(actors: Array) -> void:
	line_points=[]
	for line in compiled.lines:
		var fa: int=int(line.get("from_actor",0));var fs: int=int(line.get("from_slot",0))
		if fa<0 or fa>=actors.size() or fs>=actors[fa].centers.size():continue
		var a: Vector3=actors[fa].centers[fs]
		var ta: int=int(line.get("to_actor",fa));var ts: int=int(line.get("to_slot",-1))
		var b: Vector3
		if ts>=0 and ta<actors.size() and ts<actors[ta].centers.size():b=actors[ta].centers[ts]
		else:
			var o: Array=line.get("to_point",[0,2.5,0]);var t2: int=clampi(ta,0,actors.size()-1)
			b=actors[t2].turn*Vector3(float(o[0]),float(o[1]),float(o[2]))+actors[t2].root
		line_points.append({"a":a,"b":b,"line":line})
	if line_layer!=null:line_layer.queue_redraw()

class LineLayer extends Node2D:
	var group
	func _draw() -> void:
		var axes: Array=group.view_axes()
		var right: Vector3=axes[1];var up: Vector3=axes[2]
		var k: float=group.pixels_per_unit*group.size_factor
		for entry in group.line_points:
			var line: Dictionary=entry.line
			var col:=Color(str(line.get("color","#8a8580")))
			var w: float=maxf(1.5,float(line.get("width",0.015))*k)
			var sag: float=float(line.get("sag",0.0))
			var pts:=PackedVector2Array()
			for i in 13:
				var t: float=i/12.0
				var w3: Vector3=Vector3(entry.a).lerp(Vector3(entry.b),t)+Vector3.DOWN*sag*4.0*t*(1.0-t)
				pts.append(Vector2(w3.dot(right),-w3.dot(up))*k)
			draw_polyline(pts,col.darkened(0.45),w+2.0,true)
			draw_polyline(pts,col,w,true)
			# 鎖なら輪の目印
			if str(line.get("style",""))=="chain":
				for i in range(1,12,2):draw_circle(pts[i],w*0.9,col.lightened(0.2))

## 部位の並び（奥→手前）に置物を差し込む印。runs に {"block": 番号} を入れると、その位置の重ね順で置物を描く。
func block_queue() -> Array:
	var pending: Array=range(block_depths.size())
	pending.sort_custom(func(x,y):return block_depths[x]<block_depths[y])
	return pending

func push_blocks(runs: Array,pending: Array,key: int) -> void:
	while not pending.is_empty() and float(part_depths.get(key,INF))>float(block_depths[pending[0]]):
		runs.append({"actor":-1,"block":pending.pop_front(),"slots":PackedInt32Array()})

class BlockLayer extends Node2D:
	var group
	var index:=0
	func _draw() -> void:
		if index>=group.block_shapes.size():return
		var shape: Dictionary=group.block_shapes[index]
		var block: Dictionary=shape.block
		var axes: Array=group.view_axes()
		var view: Vector3=axes[0];var right: Vector3=axes[1];var up: Vector3=axes[2]
		var k: float=group.pixels_per_unit*group.size_factor
		var P:=func(w: Vector3) -> Vector2:return Vector2(w.dot(right),-w.dot(up))*k
		var c: Vector3=shape.center;var f: Vector3=shape.fwd;var s2: Vector3=shape.side
		var size: Array=block.get("size",[1.0,0.3,0.8])
		var L: float=float(size[0])*0.5;var W: float=float(size[1])*0.5;var H: float=float(size[2])
		var base:=Color(str(block.get("color","#6b4a2e")))
		var U:=Vector3.UP
		var faces: Array=[]
		if str(block.get("shape","prism"))=="prism":
			var T: float=float(block.get("tri",0.28))
			# 脚（A字の支え）を先に描く
			for e in [-1.0,1.0]:
				for sd in [-1.0,1.0]:
					var top: Vector3=c+f*(L*0.85*e)+s2*(W*0.6*sd)+U*(H-T)
					var foot: Vector3=c+f*(L*0.85*e)+s2*((W+0.16)*sd)
					draw_line(P.call(top),P.call(foot),base.darkened(0.35),maxf(2.0,0.045*k))
				draw_line(P.call(c+f*(L*0.85*e)+s2*(-W-0.1)+U*0.18),P.call(c+f*(L*0.85*e)+s2*(W+0.1)+U*0.18),base.darkened(0.4),maxf(1.5,0.03*k))
			var rf: Vector3=c+f*L+U*H;var rb: Vector3=c-f*L+U*H
			var pf: Vector3=c+f*L+s2*W+U*(H-T);var pb: Vector3=c-f*L+s2*W+U*(H-T)
			var mf: Vector3=c+f*L-s2*W+U*(H-T);var mb: Vector3=c-f*L-s2*W+U*(H-T)
			faces=[[(s2*T+U*W).normalized(),[pf,pb,rb,rf],1.0],[(-s2*T+U*W).normalized(),[mb,mf,rf,rb],0.85],
				[f,[pf,rf,mf],0.7],[-f,[pb,mb,rb],0.7],[-U,[pf,mf,mb,pb],0.5]]
		else:
			var h0: Vector3=U*H
			faces=[[f,[c+f*L-s2*W,c+f*L+s2*W,c+f*L+s2*W+h0,c+f*L-s2*W+h0],0.8],[-f,[c-f*L+s2*W,c-f*L-s2*W,c-f*L-s2*W+h0,c-f*L+s2*W+h0],0.8],
				[s2,[c+s2*W+f*L,c+s2*W-f*L,c+s2*W-f*L+h0,c+s2*W+f*L+h0],0.7],[-s2,[c-s2*W-f*L,c-s2*W+f*L,c-s2*W+f*L+h0,c-s2*W-f*L+h0],0.7],
				[U,[c-s2*W-f*L+h0,c+s2*W-f*L+h0,c+s2*W+f*L+h0,c-s2*W+f*L+h0],1.2]]
		for face in faces:
			var fn: Vector3=face[0]
			if fn.dot(view)<=0.0:continue
			var pts:=PackedVector2Array()
			for q in face[1]:pts.append(P.call(q))
			var col: Color=base*float(face[2]);col.a=1.0
			draw_colored_polygon(pts,col)
			var outline:=pts.duplicate();outline.append(pts[0])
			draw_polyline(outline,col.darkened(0.45),1.2)
		if str(block.get("shape","prism"))=="prism":
			# 稜（尾根）を明るく
			draw_line(P.call(c+f*L+U*H),P.call(c-f*L+U*H),base.lightened(0.35),maxf(1.5,0.02*k))

## 焼いた軌跡から役者の位置と部位の中心を出す（update_frame から）。
func track_actors(t: float) -> Array:
	var out: Array=[]
	for i in range(track_ids.size()):
		var track: Dictionary=compiled.tracks[i]
		var ma: Dictionary=track.members[cursor];var mb: Dictionary=track.members[mini(cursor+1,track.members.size()-1)]
		var height: float=lerpf(float(ma.height),float(mb.height),t)
		var root: Vector3=Vector3(ma.root).lerp(Vector3(mb.root),t)
		var turn:=Basis(Vector3.UP,deg_to_rad(lerpf(float(ma.yaw),float(mb.yaw),t)))
		var centers: Array=[]
		if track.has("frames"):
			var fa: Array=track.frames[cursor].parts;var fb: Array=track.frames[mini(cursor+1,track.frames.size()-1)].parts
			for slot in fa.size():centers.append(turn*(Vector3(fa[slot].center).lerp(Vector3(fb[slot].center),t)*height)+root)
		out.append({"root":root,"turn":turn,"height":height,"centers":centers})
	return out

class WallLayer extends Node2D:
	var group
	func _draw() -> void:
		var axes: Array=group.view_axes()
		var view: Vector3=axes[0];var right: Vector3=axes[1];var up: Vector3=axes[2]
		var k: float=group.pixels_per_unit*group.size_factor
		var P:=func(w: Vector3) -> Vector2:return Vector2(w.dot(right),-w.dot(up))*k
		for shape in group.wall_shapes:
			var wall: Dictionary=shape.wall
			var c: Vector3=shape.center;var n: Vector3=shape.normal;var u: Vector3=shape.along
			var w: float=float(wall.get("width",1.6))*0.5;var h: float=float(wall.get("height",1.3));var d: float=float(wall.get("thick",0.14))*0.5
			var base:=Color(str(wall.get("color","#4a3f3c")))
			var faces: Array=[
				[n,[c+n*d-u*w,c+n*d+u*w,c+n*d+u*w+Vector3.UP*h,c+n*d-u*w+Vector3.UP*h],1.0],
				[-n,[c-n*d+u*w,c-n*d-u*w,c-n*d-u*w+Vector3.UP*h,c-n*d+u*w+Vector3.UP*h],1.0],
				[u,[c+u*w+n*d,c+u*w-n*d,c+u*w-n*d+Vector3.UP*h,c+u*w+n*d+Vector3.UP*h],0.7],
				[-u,[c-u*w-n*d,c-u*w+n*d,c-u*w+n*d+Vector3.UP*h,c-u*w-n*d+Vector3.UP*h],0.7],
				[Vector3.UP,[c-u*w-n*d+Vector3.UP*h,c+u*w-n*d+Vector3.UP*h,c+u*w+n*d+Vector3.UP*h,c-u*w+n*d+Vector3.UP*h],1.25]]
			for f in faces:
				var fn: Vector3=f[0]
				if fn.dot(view)<=0.0:continue
				var pts:=PackedVector2Array()
				for q in f[1]:pts.append(P.call(q))
				var col: Color=base*float(f[2]);col.a=1.0
				draw_colored_polygon(pts,col)
				draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[3],pts[0]]),col.darkened(0.45),1.2)
				if absf(fn.y)<0.5 and absf(fn.dot(n))>0.5:
					# 石積みの目地と、穴の縁
					var face_c: Vector3=c+fn*d
					var rows_n: int=int(h/0.16)
					var step: float=h/float(rows_n+1)
					for r in range(1,rows_n+2):
						var y: float=r*step
						if r<=rows_n:draw_line(P.call(face_c-u*w+Vector3.UP*y),P.call(face_c+u*w+Vector3.UP*y),col.darkened(0.3),1.0)
						var x: float=-w+(0.0 if r%2==0 else 0.14)+0.28
						while x<w:
							draw_line(P.call(face_c+u*x+Vector3.UP*minf(y,h)),P.call(face_c+u*x+Vector3.UP*(y-step)),col.darkened(0.3),1.0)
							x+=0.28
					var hole: Array=wall.get("hole",[])
					if hole.size()>=2:
						var hy: float=float(hole[0]);var hr: float=float(hole[1])
						var ring:=PackedVector2Array();var inner:=PackedVector2Array()
						for i in 28:
							var a2: float=TAU*i/28.0
							ring.append(P.call(face_c+u*cos(a2)*hr*1.18+Vector3.UP*(hy+sin(a2)*hr*1.18)))
							inner.append(P.call(face_c+u*cos(a2)*hr+Vector3.UP*(hy+sin(a2)*hr)))
						draw_colored_polygon(ring,col.lightened(0.18))
						draw_colored_polygon(inner,Color(0.05,0.04,0.04))

## 効果の時間キー（offset_keys / scale_keys / angle_keys）。[{t: 場面の位相, <field>: 値, ease?}] を t の昇順で。
## ease は次のキーまでの進み方（linear / smooth（既定）/ in / out / sharp / soft）。
static func keyed(keys: Array,field: String,p: float) -> Variant:
	if keys.is_empty():return null
	if p<=float(keys[0].t):return keys[0][field]
	for i in range(keys.size()-1):
		var k0: Dictionary=keys[i];var k1: Dictionary=keys[i+1]
		if p>float(k1.t):continue
		var span: float=maxf(float(k1.t)-float(k0.t),0.000001)
		var u: float=ease_value(clampf((p-float(k0.t))/span,0.0,1.0),str(k0.get("ease","smooth")))
		var v0=k0[field];var v1=k1[field]
		if v0 is Array:
			var out: Array=[]
			for j in v0.size():out.append(lerpf(float(v0[j]),float(v1[j]),u))
			return out
		return lerpf(float(v0),float(v1),u)
	return keys[-1][field]

static func ease_value(u: float,kind: String) -> float:
	match kind:
		"linear":return u
		"in":return u*u
		"out":return 1.0-(1.0-u)*(1.0-u)
		"sharp":return u*u*u
		"soft":return u*u*u*(u*(u*6.0-15.0)+10.0)
	return u*u*(3.0-2.0*u)

## 出ている範囲の中での重み（0〜1）。端の fade の幅で出入りする。
static func effect_weight(effect: Dictionary,p: float) -> float:
	var start: float=float(effect.get("from",0.0));var finish: float=float(effect.get("to",1.0))
	var length: float=fposmod(finish-start,1.0) if finish!=start else 1.0
	if finish-start>=1.0:length=1.0
	# to が 1 なら周期をまたがない（位相0では出さない。1回だけの段階の途中から最後まで出す物）。
	if finish>=1.0 and start>0.0 and p<start:return 0.0
	var inside: float=fposmod(p-start,1.0)
	if length<1.0 and inside>length:return 0.0
	var fade: float=float(effect.get("fade",0.0))
	if fade<=0.0 or length>=1.0:return 1.0
	return clampf(minf(inside,length-inside)/fade,0.0,1.0)

static func span_progress(effect: Dictionary,p: float) -> float:
	var start: float=float(effect.get("from",0.0));var finish: float=float(effect.get("to",1.0))
	var length: float=fposmod(finish-start,1.0) if finish!=start else 1.0
	if finish-start>=1.0:length=1.0
	return clampf(fposmod(p-start,1.0)/maxf(length,0.0001),0.0,1.0)

func update_frame(at: float, upload: bool=true) -> void:
	phase=clampf(at,0,0.999999)
	cursor=World.locate(compiled.times,phase,cursor)
	var t:=inverse_lerp(compiled.times[cursor],compiled.times[cursor+1],phase)
	var outfit_changed:=false
	for i in range(track_ids.size()):
		var track: Dictionary=store.tracks[track_ids[i]]
		if store.has_method("apply_outfit_track") and store.apply_outfit_track(rows[i],track_ids[i],at):outfit_changed=true
		store.set_state(rows[i],0,Vector4(track.base+cursor*128,track.base+(cursor+1)*128,t,track.layer))
		store.set_state(rows[i],2,Vector4(0,pixels_per_unit*size_factor,deg_to_rad(direction*45.0 if is_nan(free_yaw) else free_yaw),deg_to_rad(pitch)))
		store.set_state(rows[i],3,Vector4(rows[i],0,0,1))
		store.apply_face_track(rows[i],track_ids[i],at)
		var a: Dictionary=track.members[cursor];var b: Dictionary=track.members[cursor+1]
		var q:=Basis(Vector3.UP,deg_to_rad(lerp_angle(deg_to_rad(a.yaw),deg_to_rad(b.yaw),t)*180/PI)).get_rotation_quaternion()
		var p: Vector3=a.root.lerp(b.root,t)
		store.set_state(rows[i],6,Vector4(q.x,q.y,q.z,q.w))
		store.set_state(rows[i],7,Vector4(p.x,p.y,p.z,lerpf(a.height,b.height,t)))
	if not compiled.get("walls",[]).is_empty() or not compiled.get("blocks",[]).is_empty() or not compiled.get("lines",[]).is_empty():update_walls(track_actors(t))
	# 分けて保存した場面（packs）は重ね順を数字の並び（actor*32+slot、首の順は並べ替え済み）で持つ。
	if compiled.has("orders_packed"):
		var k: int=direction*1000000+cursor
		if k!=order_key or signature=="" or not hidden_parts.is_empty() or not block_depths.is_empty():
			order_key=k;apply_packed(compiled.orders_packed[direction][cursor])
	else:apply_order(compiled.orders[direction][cursor])
	update_effects(t)
	if outfit_changed:store.update_binding()
	if upload:store.upload_state()

func apply_order(order: Array) -> void:
	order=preload("res://mini/layered2d/data/neck_attachment.gd").order_members(order)
	var runs: Array=[]
	var pending: Array=block_queue() if not block_depths.is_empty() else []
	for part in order:
		var key: int=int(part.actor)*32+int(part.slot)
		if not hidden_parts.is_empty() and hidden_parts.has(key):continue
		if not pending.is_empty():push_blocks(runs,pending,key)
		if runs.is_empty() or runs[-1].actor!=part.actor:runs.append({"actor":part.actor,"slots":PackedInt32Array()})
		runs[-1].slots.append(part.slot)
	for b in pending:runs.append({"actor":-1,"block":b,"slots":PackedInt32Array()})
	apply_runs(runs)

func apply_packed(order: PackedInt32Array) -> void:
	var runs: Array=[]
	var pending: Array=block_queue() if not block_depths.is_empty() else []
	for v in order:
		if not hidden_parts.is_empty() and hidden_parts.has(v):continue
		if not pending.is_empty():push_blocks(runs,pending,v)
		var actor: int=v>>5
		if runs.is_empty() or runs[-1].actor!=actor:runs.append({"actor":actor,"slots":PackedInt32Array()})
		runs[-1].slots.append(v&31)
	for b in pending:runs.append({"actor":-1,"block":b,"slots":PackedInt32Array()})
	apply_runs(runs)

func apply_runs(runs: Array) -> void:
	var mesh_runs:=0
	for run in runs:
		if not run.has("block"):mesh_runs+=1
	active_runs=mesh_runs
	var key:=str(runs)+str(rows)
	if key!=signature:
		while nodes.size()<mesh_runs:
			var node:=MeshInstance2D.new();add_child(node);nodes.append(node)
			RenderingServer.canvas_item_set_custom_rect(node.get_canvas_item(),true,Rect2(-800,-900,1600,1500))
		# 置物の印（{"block": 番号}）は描画ノードを使わず、その位置の重ね順を置物に渡す。
		var m:=0
		for i in range(runs.size()):
			if runs[i].has("block"):
				var b: int=int(runs[i].block)
				if b<block_nodes.size():block_nodes[b].z_index=i
				continue
			nodes[m].visible=true
			nodes[m].mesh=plans.get_mesh(runs[i].slots)
			nodes[m].material=store.material_for(int(rows[runs[i].actor]))
			nodes[m].z_index=i
			m+=1
		for j in range(m,nodes.size()):nodes[j].visible=false
		signature=key

func apply_live(value: Dictionary, live_tracks: Array) -> void:
	var order: Array=[]
	var yaw:=deg_to_rad(direction*45.0 if is_nan(free_yaw) else free_yaw)
	var view:=Vector3(sin(yaw)*cos(deg_to_rad(pitch)),sin(deg_to_rad(pitch)),cos(yaw)*cos(deg_to_rad(pitch)))
	for i in range(live_tracks.size()):
		store.apply_face_track(rows[i],track_ids[i],value.phase)
		store.write_live(live_tracks[i],value.snapshots[i].parts)
		var track: Dictionary=store.tracks[live_tracks[i]]
		store.set_state(rows[i],0,Vector4(track.base,track.base,0,track.layer))
		var member: Dictionary=value.members[i]
		var rotation:=Basis(Vector3.UP,deg_to_rad(member.yaw))
		var q:=rotation.get_rotation_quaternion()
		store.set_state(rows[i],6,Vector4(q.x,q.y,q.z,q.w))
		store.set_state(rows[i],7,Vector4(member.root.x,member.root.y,member.root.z,member.height))
		for slot in range(value.snapshots[i].parts.size()):
			var point: Vector3=rotation*value.snapshots[i].parts[slot].center*member.height+member.root
			var depth_value:float=preload("res://mini/layered2d/prepare/layer_compiler.gd").depth(slot,value.snapshots[i].parts,rotation.transposed()*view)*member.height+Vector3(member.root).dot(view)
			order.append({"actor":i,"slot":slot,"depth":depth_value})
	if not compiled.get("walls",[]).is_empty() or not compiled.get("blocks",[]).is_empty() or not compiled.get("lines",[]).is_empty():
		var live_actors: Array=[]
		for i in range(live_tracks.size()):
			var mem: Dictionary=value.members[i]
			var turn:=Basis(Vector3.UP,deg_to_rad(mem.yaw))
			var centers: Array=[]
			for part in value.snapshots[i].parts:centers.append(turn*part.center*mem.height+mem.root)
			live_actors.append({"root":mem.root,"turn":turn,"height":mem.height,"centers":centers})
		update_walls(live_actors)
	order.sort_custom(func(a,b):return a.depth<b.depth if absf(a.depth-b.depth)>0.000001 else a.actor*32+a.slot<b.actor*32+b.slot)
	if not order.is_empty():
		var names: Array=[];var base: Array=[];var indexed: Dictionary={}
		for id in value.actor_ids:
			for slot in preload("res://mini/layered2d/data/catalog.gd").ALL_SLOTS:names.append(str(id)+"."+slot)
		for part in order:
			var index: int=part.actor*preload("res://mini/layered2d/data/catalog.gd").ALL_SLOTS.size()+part.slot
			base.append(index);indexed[index]=part
		var resolved: Dictionary=preload("res://mini/layered2d/prepare/layer_compiler.gd").resolve(base,names,value.get("layer_rules",[]),value.phase,direction)
		if not resolved.ok:last_error=resolved;return
		order=[]
		for index in resolved.order:order.append(indexed[index])
	last_error={}
	apply_order(order)
	store.upload_state()
