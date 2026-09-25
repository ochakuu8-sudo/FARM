extends Node2D
## 見下ろしの地図の共通部分（牧場と戦場）。床・壁・物は役者と同じ投影の式で2Dに描くので、8方向に回しても揃う。
const G=preload("res://game/core/g.gd")
const CELL:=1.5
const PPU:=82.0/2.45
const HEIGHT:=1.0

var yaw_deg:=0.0
var dir:=0
var pitch_deg:=40.0
var zoom:=1.2
var cam:=Vector2(8,8)
var cam_goal:=Vector2(-1,-1)
var rotating:=false
var time:=0.0
var screen_center:=Vector2(960,560)
var bounds:=Rect2(0,0,8,8)          # カメラの動ける範囲（マス）

# ───────── 投影 ─────────
func basis() -> Array:
	var t:=deg_to_rad(yaw_deg);var p:=deg_to_rad(pitch_deg)
	return [cos(t),sin(t),sin(p),cos(p)]

func project(cell: Vector2,height: float=0.0) -> Vector2:
	var b: Array=basis()
	var x: float=(cell.x-cam.x)*CELL;var z: float=(cell.y-cam.y)*CELL
	return Vector2(x*b[0]-z*b[1],b[2]*(x*b[1]+z*b[0])-height*b[3])*PPU

func unproject(p: Vector2) -> Vector2:
	var b: Array=basis()
	var a: float=p.x/PPU;var bb: float=p.y/PPU/maxf(b[2],0.01)
	var x: float=a*b[0]+bb*b[1];var z: float=-a*b[1]+bb*b[0]
	return Vector2(x/CELL+cam.x,z/CELL+cam.y)

func cell_at_screen(screen_pos: Vector2) -> Vector2:
	return unproject((screen_pos-position)/zoom)

func to_screen(cell: Vector2,height: float=0.0) -> Vector2:
	return project(cell,height)*zoom+position

## 世界の向き（0 奥、2 右、4 手前、6 左）を今の視点で見た向きへ。
func screen_facing(world_dir: int) -> int:
	return posmod(world_dir+dir,8)

## 世界の中の向き（dx, dy）を 0〜7 の向きへ。
static func dir_of(d: Vector2) -> int:
	if d.length()<0.01:return 4
	var a: float=atan2(d.x,-d.y)
	return posmod(int(round(a/(PI/4.0))),8)

func facing_camera(n: Vector2) -> bool:
	var t:=deg_to_rad(yaw_deg)
	return n.dot(Vector2(sin(t),cos(t)))>0.05

func visible_cell(c: Vector2,margin: float=160.0) -> bool:
	var p: Vector2=to_screen(c)
	return p.x>-margin and p.x<1920+margin and p.y>-margin-120 and p.y<1080+margin

func rotate_view(step: int) -> void:
	dir=posmod(dir+step,8)

func focus_on(cell: Vector2) -> void:
	cam_goal=cell

## 毎フレーム：回転と寄りを滑らかに。
func update_view(delta: float) -> void:
	time+=delta
	var goal: float=dir*45.0
	var diff: float=wrapf(goal-yaw_deg,-180,180)
	rotating=absf(diff)>0.5
	if rotating:yaw_deg+=diff*clampf(delta*9.0,0,1)
	else:yaw_deg=goal
	if cam_goal.x>=0:
		cam=cam.lerp(cam_goal,clampf(delta*6.0,0,1))
		if cam.distance_to(cam_goal)<0.02:cam_goal=Vector2(-1,-1)
	cam.x=clampf(cam.x,bounds.position.x,bounds.end.x);cam.y=clampf(cam.y,bounds.position.y,bounds.end.y)
	scale=Vector2(zoom,zoom)
	position=screen_center
	G.anim.set_pitch(deg_to_rad(pitch_deg*0.55))

## 画面をずらす（画面の画素で）。
func pan_screen(d: Vector2) -> void:
	var a: Vector2=unproject(Vector2.ZERO);var b: Vector2=unproject(d/zoom)
	cam-=b-a
	cam_goal=Vector2(-1,-1)

## 描く道具（床の層・手前の層が継ぐ）。
class Draw extends Node2D:
	var map
	## まとめて描く（batched）：多角形・線を三角形の配列にためて、最後に1回の描画命令で出す。
	## ブラウザ版では描画命令1回ごとに JavaScript を通るので、数百の多角形を別々に出すと重い。
	## まとめる層は paint() に描き、_draw が最後に flush する。文字や別の描き方を挟むときは先に flush() する。
	var batched:=false
	var tri_pts:=PackedVector2Array()
	var tri_cols:=PackedColorArray()
	var tri_idx:=PackedInt32Array()

	func _draw() -> void:
		paint()
		flush()

	func paint() -> void:
		pass

	func flush() -> void:
		if tri_idx.is_empty():return
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),tri_idx,tri_pts,tri_cols)
		tri_pts=PackedVector2Array();tri_cols=PackedColorArray();tri_idx=PackedInt32Array()

	## 凸の多角形（または頂点0から全部が見える形）を塗る。
	func fill(pts: PackedVector2Array,color: Color) -> void:
		if not batched:draw_colored_polygon(pts,color);return
		if pts.size()<3:return
		var base: int=tri_pts.size()
		tri_pts.append_array(pts)
		for i in pts.size():tri_cols.append(color)
		for i in range(1,pts.size()-1):
			tri_idx.append(base);tri_idx.append(base+i);tri_idx.append(base+i+1)

	func line(a: Vector2,b: Vector2,color: Color,width: float=1.0) -> void:
		if not batched:draw_line(a,b,color,width);return
		var d: Vector2=b-a
		if d.length_squared()<0.000001:return
		var n: Vector2=Vector2(-d.y,d.x).normalized()*width*0.5
		fill(PackedVector2Array([a+n,b+n,b-n,a-n]),color)

	func poly_line(pts: PackedVector2Array,color: Color,width: float=1.0,antialiased: bool=false) -> void:
		if not batched:draw_polyline(pts,color,width,antialiased);return
		for i in pts.size()-1:line(pts[i],pts[i+1],color,width)

	func dot(p: Vector2,radius: float,color: Color) -> void:
		if not batched:draw_circle(p,radius,color);return
		var pts:=PackedVector2Array()
		for i in 12:pts.append(p+Vector2(cos(TAU*i/12.0),sin(TAU*i/12.0))*radius)
		fill(pts,color)

	func facing_camera(n: Vector2) -> bool:
		return map.facing_camera(n)

	func quad(c: Vector2,g: float=0.035) -> PackedVector2Array:
		return PackedVector2Array([map.project(c+Vector2(g,g)),map.project(c+Vector2(1-g,g)),map.project(c+Vector2(1-g,1-g)),map.project(c+Vector2(g,1-g))])

	func disc(c: Vector2,radius: float,color: Color,base: float=0.0) -> void:
		var pts:=PackedVector2Array()
		for i in 28:pts.append(map.project(c+Vector2(cos(TAU*i/28),sin(TAU*i/28))*radius,base))
		fill(pts,color)

	func circle_line(c: Vector2,radius: float,color: Color,width: float,base: float=0.0) -> void:
		var pts:=PackedVector2Array()
		for i in 29:pts.append(map.project(c+Vector2(cos(TAU*i/28),sin(TAU*i/28))*radius,base))
		poly_line(pts,color,width,true)

	func cyl(c: Vector2,radius: float,height: float,color: Color,base: float=0.0) -> void:
		var n:=20
		for i in n:
			var p: Vector2=c+Vector2(cos(TAU*i/n),sin(TAU*i/n))*radius
			var q: Vector2=c+Vector2(cos(TAU*(i+1)/n),sin(TAU*(i+1)/n))*radius
			if facing_camera(((p+q)*0.5-c).normalized()):
				fill(PackedVector2Array([map.project(p,base),map.project(q,base),map.project(q,base+height),map.project(p,base+height)]),color.darkened(0.3))
		var top:=PackedVector2Array()
		for i in n:top.append(map.project(c+Vector2(cos(TAU*i/n),sin(TAU*i/n))*radius,base+height))
		fill(top,color)
		top.append(top[0]);poly_line(top,color.lightened(0.25),1)

	func box(center: Vector2,size: Vector2,height: float,color: Color,base: float=0.0) -> void:
		var a:=center-size*0.5;var b:=center+size*0.5
		var corners: Array=[Vector2(a.x,a.y),Vector2(b.x,a.y),Vector2(b.x,b.y),Vector2(a.x,b.y)]
		for i in 4:
			var p: Vector2=corners[i];var q: Vector2=corners[(i+1)%4]
			var n:=Vector2(q.y-p.y,-(q.x-p.x)).normalized()
			if facing_camera(n):
				fill(PackedVector2Array([map.project(p,base),map.project(q,base),map.project(q,base+height),map.project(p,base+height)]),color.darkened(0.3))
		var top:=PackedVector2Array()
		for p in corners:top.append(map.project(p,base+height))
		fill(top,color)
		top.append(top[0]);poly_line(top,color.lightened(0.25),1)

	func bars(c: Vector2,half: float,height: float,front_side: bool) -> void:
		var q: Array=[c+Vector2(-half,-half),c+Vector2(half,-half),c+Vector2(half,half),c+Vector2(-half,half)]
		var iron:=Color(0.44,0.38,0.36,0.9)
		for i in 4:
			var a: Vector2=q[i];var b: Vector2=q[(i+1)%4]
			var n:=Vector2(b.y-a.y,-(b.x-a.x)).normalized()
			if facing_camera(n)!=front_side:continue
			for k in 9:
				var p: Vector2=a.lerp(b,k/8.0)
				line(map.project(p),map.project(p,height),iron,2.5)
			line(map.project(a),map.project(b),iron.darkened(0.2),3)
			line(map.project(a,height),map.project(b,height),iron.lightened(0.1),3)

	func fence(c: Vector2,half: float,height: float,front_side: bool) -> void:
		var q: Array=[c+Vector2(-half,-half),c+Vector2(half,-half),c+Vector2(half,half),c+Vector2(-half,half)]
		var wood:=Color("5a4028")
		for i in 4:
			var a: Vector2=q[i];var b: Vector2=q[(i+1)%4]
			var n:=Vector2(b.y-a.y,-(b.x-a.x)).normalized()
			if facing_camera(n)!=front_side:continue
			for k in 4:
				var p: Vector2=a.lerp(b,k/3.0)
				line(map.project(p),map.project(p,height),wood.darkened(0.2),3)
			for hgt in [height*0.45,height*0.9]:line(map.project(a,hgt),map.project(b,hgt),wood,2.5)

	## 奥側の壁（床から壁へ向かう面がカメラの向こうを向くときだけ）。
	func back_wall(cf: Vector2,d: Vector2i,height: float,color: Color) -> void:
		var n:=Vector2(d)
		if map.facing_camera(n):return
		var a: Vector2;var b: Vector2
		match d:
			Vector2i(0,-1):a=cf;b=cf+Vector2(1,0)
			Vector2i(1,0):a=cf+Vector2(1,0);b=cf+Vector2(1,1)
			Vector2i(0,1):a=cf+Vector2(1,1);b=cf+Vector2(0,1)
			_:a=cf+Vector2(0,1);b=cf
		fill(PackedVector2Array([map.project(a),map.project(b),map.project(b,height),map.project(a,height)]),color)
		for k in range(1,4):line(map.project(a,height*k/4.0),map.project(b,height*k/4.0),Color(0,0,0,0.3),1)
		line(map.project(a,height),map.project(b,height),Color("4d3a30"),2)
