extends "res://game/map/iso.gd"
## 戦場の盤（設計書 3.1・12章）。牧場と同じ投影で、小さな盤を斜め見下ろしに描く。
## 画面（編成・戦闘）が駒（pieces）を渡し、ここは役者を置いて滑らかに動かし、体力と溜まりの棒・痛手の数字・範囲の光・飛び道具を描く。
##   駒：{look, cell: Vector2（目標の位置。マスの左上が 0）, pos: Vector2（今の位置）, face, action, side, hp, max, charge, name, named, alive, ready}
##   follow=true の駒（戦闘）は、計算の位置へそのまま寄せ、歩いているか（walking）と向き（face）も画面から受け取る。
##   follow の無い駒（編成）は、マスの間を move_speed で歩いて移る。
const Ui=preload("res://game/ui/ui.gd")
const Look=preload("res://game/map/look.gd")

var rows: Array=[]
var bw:=8
var bh:=8
var floor_layer: BoardLayer
var actors_root: Node2D
var tags: BoardTags
var fx: BoardFx
var pieces: Dictionary={}         # 鍵 → 駒
var actors: Dictionary={}         # 鍵 → 役者ID
var marks: Dictionary={}          # マス → 色（置き場・範囲の見本）
var hover_cell:=Vector2i(-1,-1)
var flashes: Array=[]             # {cell, t, text, color, big}
var areas: Array=[]               # {cells, t, color} か {shape, center, from, r, t, color}（戦闘の丸・線の範囲。位置はマスの中心が +0.5 の座標）
var shots: Array=[]               # 飛んでいる矢・術 {pos（駒の座標）, magic, side}
var move_speed:=4.0               # マス/秒
var selected_key:=""
var arrows: Array=[]              # 矢印 [{from, to, target, side}]（マス。今は使っていない）
## 床をひと続きに描く（戦闘。マスの切れ目を見せない）。false なら置き場のマス目を見せる（編成）。
var seamless:=false

func _ready() -> void:
	floor_layer=BoardLayer.new();floor_layer.batched=true;floor_layer.map=self;floor_layer.z_index=-3500;floor_layer.z_as_relative=false;add_child(floor_layer)
	actors_root=Node2D.new();add_child(actors_root)
	fx=BoardFx.new();fx.batched=true;fx.map=self;fx.z_index=3800;fx.z_as_relative=false;add_child(fx)
	tags=BoardTags.new();tags.map=self;tags.z_index=3900;tags.z_as_relative=false;add_child(tags)
	G.anim.attach(actors_root)
	pitch_deg=42.0
	zoom=2.3
	screen_center=Vector2(960,520)

func set_board(board: Array) -> void:
	rows=board.duplicate()
	bh=rows.size();bw=str(rows[0]).length() if bh>0 else 8
	bounds=Rect2(0,0,bw,bh)
	cam=Vector2(bw*0.5,bh*0.5)
	# 盤が広いほど引いて全体を入れる（8マスで2.3）
	zoom=clampf(2.3*9.0/float(bw+1),1.25,2.3)

func tile(c: Vector2i) -> String:
	if c.x<0 or c.y<0 or c.x>=bw or c.y>=bh:return "#"
	return str(rows[c.y]).substr(c.x,1)

func cell_under(screen_pos: Vector2) -> Vector2i:
	var c: Vector2=cell_at_screen(screen_pos)
	var v:=Vector2i(int(floor(c.x)),int(floor(c.y)))
	if v.x<0 or v.y<0 or v.x>=bw or v.y>=bh:return Vector2i(-1,-1)
	return v

## 画面の位置にいる駒の鍵（体の高さも見る）。
func piece_under(screen_pos: Vector2) -> String:
	var best:="";var bd:=1e9
	for k in pieces:
		var p: Dictionary=pieces[k]
		if not p.get("alive",true):continue
		var foot: Vector2=to_screen(p.pos+Vector2(0.5,0.5))
		var body: Vector2=to_screen(p.pos+Vector2(0.5,0.5),0.9)
		var d: float=minf(screen_pos.distance_to(foot),screen_pos.distance_to(body))
		if d<70.0*zoom/2.3 and d<bd:bd=d;best=k
	return best

func set_piece(key: String,data: Dictionary) -> void:
	var p: Dictionary=pieces.get(key,{})
	if p.is_empty():
		p=data.duplicate()
		p.pos=Vector2(data.cell)
		pieces[key]=p
	else:
		for k in data:p[k]=data[k]

func remove_piece(key: String) -> void:
	pieces.erase(key)
	if actors.has(key):G.anim.release(actors[key]);actors.erase(key)

func clear_pieces() -> void:
	for k in actors:G.anim.release(actors[k])
	actors.clear();pieces.clear()

func flash(cell: Vector2,text: String,color: Color,big: bool=false) -> void:
	flashes.append({"cell":cell,"t":0.0,"text":text,"color":color,"big":big})

func flash_area(cells: Array,color: Color) -> void:
	areas.append({"cells":cells,"t":0.0,"color":color})

## 戦闘のスキルの範囲を光らせる（shape：square は丸、line は帯、all は盤全体、single は的の足もと）。
func flash_shape(shape: String,center: Vector2,from: Vector2,r: float,color: Color) -> void:
	areas.append({"shape":shape,"center":center,"from":from,"r":r,"t":0.0,"color":color})

func _process(delta: float) -> void:
	update_view(delta)
	for k in pieces:
		var p: Dictionary=pieces[k]
		var goal:=Vector2(p.cell)
		var d: Vector2=goal-p.pos
		if p.get("follow",false):
			# 計算の位置へ寄せる（刻みの間を埋める。跳ぶ技のような大きな移動も一瞬で追いつく）
			p.pos=p.pos.lerp(goal,1.0-exp(-delta*22.0)) if d.length()<1.5 else goal
			p.moving=bool(p.get("walking",false))
		else:
			p.moving=d.length()>0.02
			if p.moving:
				var step: float=move_speed*delta*(2.5 if d.length()>1.6 else 1.0)
				p.pos=goal if d.length()<=step else p.pos+d.normalized()*step
				p.face=dir_of(d)
		var id: String=actors.get(k,"")
		if id=="":
			id=Look.dress(p.look,HEIGHT)
			if id=="":continue
			actors[k]=id
			p.last_action=""
		var act: String="walk" if p.moving and p.get("alive",true) else str(p.get("action","idle"))
		if p.has("hidden") or p.has("flash_t"):
			var base_tint: Color=p.look.get("tint",Color.WHITE) if p.look.get("tint",Color.WHITE) is Color else Color.WHITE
			var ft: float=float(p.get("flash_t",0.0))
			if ft>0:p.flash_t=ft-delta;base_tint=base_tint.lerp(Color(1.0,0.35,0.3),clampf(ft/0.18,0,1)*0.7)
			G.anim.tint(id,Color(base_tint,0.35) if p.get("hidden",false) else base_tint)
		G.anim.place(id,project(p.pos+Vector2(0.5,0.5)),screen_facing(int(p.get("face",4))),act)
		if act!=str(p.get("last_action","")) and act in ["attack","attack_heavy","cast","hit","heal","guard"]:G.anim.act(id,act,true)
		p.last_action=act
	G.anim.advance(delta)
	for f in flashes:f.t+=delta
	flashes=flashes.filter(func(f):return f.t<1.3)
	for a in areas:a.t+=delta
	areas=areas.filter(func(a):return a.t<0.8)
	floor_layer.queue_redraw();tags.queue_redraw();fx.queue_redraw()

func release_all() -> void:
	clear_pieces()

class BoardLayer extends "res://game/map/iso.gd".Draw:
	func paint() -> void:
		var outer:=PackedVector2Array([map.project(Vector2(-3,-3)),map.project(Vector2(map.bw+3,-3)),map.project(Vector2(map.bw+3,map.bh+3)),map.project(Vector2(-3,map.bh+3))])
		fill(outer,Color("0d0a0b"))
		var t:=deg_to_rad(map.yaw_deg)
		var fwd:=Vector2(sin(t),cos(t))
		var cells: Array=[]
		for y in map.bh:
			for x in map.bw:cells.append(Vector2i(x,y))
		cells.sort_custom(func(a,c):return (Vector2(a)+Vector2(0.5,0.5)).dot(fwd)<(Vector2(c)+Vector2(0.5,0.5)).dot(fwd))
		for c: Vector2i in cells:
			var cf:=Vector2(c)
			var tl: String=map.tile(c)
			var hsh: int=(c.x*73856093)^(c.y*19349663)
			var vv: float=float(absi(hsh)%13)/13.0
			var base: Color=Color("2a2320").lerp(Color("332a24"),vv)
			if (c.x+c.y)%2==0 and not map.seamless:base=base.lightened(0.03)
			if map.seamless:base=Color("2c2521").lerp(Color("2f2723"),vv*0.5)
			match tl:
				"#":
					box(cf+Vector2(0.5,0.5),Vector2(0.92,0.92),0.9,Color("1e1716"))
					continue
				"~":base=Color("1f3a4a").lerp(Color("28506a"),0.5+0.5*sin(map.time*1.5+c.x+c.y))
				"\"":base=Color("20301e").lerp(Color("2a3a24"),vv)
			fill(quad(cf,0.0 if map.seamless else 0.035),base)
			if map.marks.has(c):fill(quad(cf,0.06),Color(map.marks[c],0.28+0.08*sin(map.time*4)))
			if tl=="\"":
				for k in 3:
					var p: Vector2=cf+Vector2(0.25+0.25*k,0.3+0.2*((k+c.x)%2))
					cyl(p,0.09,0.35,Color("2f4a28"))
			if c==map.hover_cell:
				var q: PackedVector2Array=quad(cf,0.04);q.append(q[0])
				poly_line(q,Color(Ui.GOLD,0.7),2)
		# 盤の縁
		var e:=PackedVector2Array([map.project(Vector2(0,0)),map.project(Vector2(map.bw,0)),map.project(Vector2(map.bw,map.bh)),map.project(Vector2(0,map.bh)),map.project(Vector2(0,0))])
		poly_line(e,Color(Ui.GOLD,0.35),2)
		# 選んでいる駒の足もと
		if map.selected_key!="" and map.pieces.has(map.selected_key):
			var sp: Dictionary=map.pieces[map.selected_key]
			circle_line(sp.pos+Vector2(0.5,0.5),0.42,Ui.GOLD_HI,3.0)
		for k in map.pieces:
			var p2: Dictionary=map.pieces[k]
			if not p2.get("alive",true):continue
			var col: Color=Color("c4628c") if p2.side=="w" else Color("7299bf")
			circle_line(p2.pos+Vector2(0.5,0.5),0.36,Color(col,0.6),2.0)

## 範囲の光と、痛手・回復の数字。
class BoardFx extends "res://game/map/iso.gd".Draw:
	func paint() -> void:
		for a in map.arrows:
			var col: Color=Color("c4628c") if a.side=="w" else Color("7299bf")
			if a.from!=a.to:
				var p0: Vector2=map.project(Vector2(a.from)+Vector2(0.5,0.5),0.05);var p1: Vector2=map.project(Vector2(a.to)+Vector2(0.5,0.5),0.05)
				line(p0,p1,Color(col,0.55),3.0)
				var d: Vector2=(p1-p0).normalized()
				fill(PackedVector2Array([p1,p1-d*9+d.orthogonal()*5,p1-d*9-d.orthogonal()*5]),Color(col,0.75))
			if a.target.x>=0:
				var q0: Vector2=map.project(Vector2(a.to)+Vector2(0.5,0.5),0.6);var q1: Vector2=map.project(Vector2(a.target)+Vector2(0.5,0.5),0.6)
				flush();draw_dashed_line(q0,q1,Color(Ui.DANGER if a.side=="w" else Ui.GOLD,0.6),2.0,5.0)
		for a in map.areas:
			var al: float=clampf(1.0-a.t/0.8,0,1)
			if a.has("cells"):
				for c in a.cells:
					fill(quad(Vector2(c),0.08),Color(a.color,0.35*al))
				continue
			var col: Color=Color(a.color,0.32*al)
			match str(a.shape):
				"all":
					fill(PackedVector2Array([map.project(Vector2(0,0)),map.project(Vector2(map.bw,0)),map.project(Vector2(map.bw,map.bh)),map.project(Vector2(0,map.bh))]),Color(a.color,0.18*al))
				"line":
					var dv: Vector2=(a.center-a.from)
					if dv.length()<1e-4:dv=Vector2(1,0)
					dv=dv.normalized()
					var side: Vector2=dv.orthogonal()*0.45
					var e0: Vector2=a.from;var e1: Vector2=a.from+dv*float(a.r)
					fill(PackedVector2Array([map.project(e0+side),map.project(e1+side),map.project(e1-side),map.project(e0-side)]),col)
				_:
					var ring:=PackedVector2Array()
					for i in 32:ring.append(map.project(a.center+Vector2(float(a.r),0).rotated(TAU*i/32.0)))
					fill(ring,col)
					ring.append(ring[0]);poly_line(ring,Color(a.color,0.7*al),2.0,true)
		# 飛び道具（矢・術の玉）
		for sh in map.shots:
			var at: Vector2=map.project(sh.pos+Vector2(0.5,0.5),0.75)
			var c2: Color=Color("b48cff") if sh.magic else Color("f0e0b0")
			if sh.side=="w":c2=Color("ff9ab8") if sh.magic else Color("f4f0e0")
			dot(at,7.0,Color(c2,0.25));dot(at,3.5,c2)

## 画面の画素で描く印：体力と溜まりの棒、名前、飛ぶ数字。
class BoardTags extends Node2D:
	var map
	func _draw() -> void:
		var z: float=maxf(map.zoom,0.01)
		draw_set_transform(Vector2.ZERO,0,Vector2(1.0/z,1.0/z))
		var font: Font=Ui.head_font if Ui.head_font!=null else ThemeDB.fallback_font
		for k in map.pieces:
			var p: Dictionary=map.pieces[k]
			if not p.get("alive",true):continue
			var at: Vector2=map.project(p.pos+Vector2(0.5,0.5),2.25)*z
			var f: float=clampf(float(p.hp)/maxf(1.0,float(p.max)),0,1)
			var col: Color=Ui.PINK if p.side=="w" else Ui.GOOD
			draw_rect(Rect2(at+Vector2(-26,0),Vector2(52,7)),Color(0,0,0,0.75))
			draw_rect(Rect2(at+Vector2(-26,0),Vector2(52*f,7)),col)
			draw_rect(Rect2(at+Vector2(-26,0),Vector2(52,7)),Color(0,0,0,0.9),false,1.0)
			if p.has("charge"):
				var cf: float=clampf(float(p.charge)/100.0,0,1)
				var cc: Color=Ui.GOLD_HI if p.get("ready",false) else Ui.GOLD.darkened(0.3)
				draw_rect(Rect2(at+Vector2(-26,9),Vector2(52,4)),Color(0,0,0,0.75))
				draw_rect(Rect2(at+Vector2(-26,9),Vector2(52*cf,4)),cc)
				if p.get("ready",false):
					var pulse: float=0.5+0.5*sin(map.time*6.0)
					draw_circle(at+Vector2(34,6),6+pulse*2,Color(Ui.GOLD_HI,0.5+0.4*pulse))
			if p.get("order",false):draw_string(font,at+Vector2(-40,-6),"◆撃つ",HORIZONTAL_ALIGNMENT_CENTER,80,14,Ui.GOLD_HI)
			if str(p.get("named",""))!="" or p.side=="m":
				draw_string_outline(font,at+Vector2(-70,-8 if not p.get("order",false) else -22),str(p.name),HORIZONTAL_ALIGNMENT_CENTER,140,14,4,Color(0,0,0,0.8))
				draw_string(font,at+Vector2(-70,-8 if not p.get("order",false) else -22),str(p.name),HORIZONTAL_ALIGNMENT_CENTER,140,14,Ui.GOLD_HI if str(p.get("named",""))!="" else Ui.TEXT)
		for fl in map.flashes:
			var a: float=clampf(1.0-fl.t/1.3,0,1)
			var p3: Vector2=map.project(fl.cell+Vector2(0.5,0.5),2.4+fl.t*1.0)*z
			var fs: int=26 if fl.big else 20
			draw_string_outline(font,p3+Vector2(-100,0),str(fl.text),HORIZONTAL_ALIGNMENT_CENTER,200,fs,5,Color(0,0,0,0.8*a))
			draw_string(font,p3+Vector2(-100,0),str(fl.text),HORIZONTAL_ALIGNMENT_CENTER,200,fs,Color(fl.color,a))
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
