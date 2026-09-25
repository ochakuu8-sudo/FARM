extends "res://game/map/iso.gd"
## 牧場の見下ろしの地図（企画書 8.1・設計書 1.3）。8方向に回せる。どの施設でも、割り当てた女と魔物の場面が同時に動いている。
##   房：ranch.room（相手役の魔物と）／搾り場：ranch.press／苗床：ranch.lay（父と）／召喚陣：ranch.altar／牢：檻で待つ／巣：休む魔物。
const Ui=preload("res://game/ui/ui.gd")
const Captive=preload("res://game/breed/captive.gd")
const Look=preload("res://game/map/look.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
const Parts=preload("res://game_v2/animation/parts.gd")
const WALL:=1.15
## 人と場面をマスに対してこの倍率で描く（1マスを広く使い、隣の家具の場面と重ならないように）。家具の絵の高さも同じ倍率。
const ACTOR:=0.7

var tile_layer: TileLayer
var floor_layer: FloorLayer
var fx_layer: FxLayer
var tile_key:=""
var fac_key:=""
var actors_root: Node2D
var front: FrontLayer
var tags: TagLayer
var actors: Dictionary={}         # 鍵 → 役者ID
var scenes: Dictionary={}         # 鍵 → {handle, a, b, room}
# 画面（screens/ranch.gd）が決めるもの
var mode:="view"                  # view / build / place_woman
var ghost: Dictionary={}          # {def, x, y, rot, ok}
var hover_cell:=Vector2i(-1,-1)
var selected:=-1                  # 選んでいる施設の uid
var highlight: Dictionary={}      # uid → Color（選んだ人を入れられる施設）
var dimmed: Dictionary={}         # uid → true（選んだ人を入れられない施設）
var hints: Dictionary={}          # uid → {text, color}（施設の上の一言）
var order_cache: Array=[]
var order_key:=-999

func _ready() -> void:
	tile_layer=TileLayer.new();tile_layer.batched=true;tile_layer.map=self;tile_layer.z_index=-3550;tile_layer.z_as_relative=false;add_child(tile_layer)
	floor_layer=FloorLayer.new();floor_layer.batched=true;floor_layer.map=self;floor_layer.z_index=-3500;floor_layer.z_as_relative=false;add_child(floor_layer)
	fx_layer=FxLayer.new();fx_layer.batched=true;fx_layer.map=self;fx_layer.z_index=-3490;fx_layer.z_as_relative=false;add_child(fx_layer)
	actors_root=Node2D.new();add_child(actors_root)
	front=FrontLayer.new();front.batched=true;front.map=self;front.z_index=3600;front.z_as_relative=false;add_child(front)
	tags=TagLayer.new();tags.map=self;tags.z_index=3900;tags.z_as_relative=false;add_child(tags)
	G.anim.attach(actors_root)
	bounds=Rect2(0,0,float(G.state.grid.w),float(G.state.grid.h))
	cam=Vector2(float(G.state.grid.w)*0.45,float(G.state.grid.h)*0.5)

func _process(delta: float) -> void:
	update_view(delta)
	sync()
	G.anim.advance(delta)
	# 床のマスは視点（向き・傾き・位置・寄り）が変わったときだけ描き直す（毎フレーム全マスを描くと重い）。
	var view_key: String="%.2f|%.2f|%.3f|%.3f|%.3f"%[yaw_deg,pitch_deg,cam.x,cam.y,zoom]
	var key: String=view_key+"|%d|%d"%[int(G.state.grid.w),int(G.state.grid.h)]+str(G.state.grid.cells)
	if key!=tile_key:tile_key=key;tile_layer.queue_redraw()
	# 施設の絵（動かない部分）と手前の格子は、視点・施設・選び方が変わったときだけ描き直す。炎・魔法陣・光る縁取りは fx_layer が毎フレーム描く。
	var fk: String=view_key+"|%d|%d|%d|%s|%s|%s|%s|%d"%[selected,hover_cell.x,hover_cell.y,mode,str(ghost),str(highlight),str(dimmed),fac_sig()]
	if fk!=fac_key:fac_key=fk;floor_layer.queue_redraw();front.queue_redraw()
	fx_layer.queue_redraw();tags.queue_redraw()

## 施設の並び・向き・場面の有無の指紋（変わったら施設の絵を描き直す）。
func fac_sig() -> int:
	var h:=0
	for f in G.state.facilities:h=hash([h,f.uid,f.x,f.y,f.get("rot",0),f.def,scenes.has("f:%d"%int(f.uid))])
	return h

# ───────── 役者と場面 ─────────
## 1フレームで新しく着せる・流し始める処理の時間の上限（マイクロ秒）。超えたら次のフレームへ回す（最低1つは進める）。
## 牧場に入った直後に全員を一度に着せると、ブラウザ版（特にスマホ）で数秒止まるため、順に現れるようにする。
const LOAD_BUDGET_US:=12000
var sync_started:=0
var loads_this_frame:=0
func over_budget() -> bool:
	return loads_this_frame>0 and Time.get_ticks_usec()-sync_started>LOAD_BUDGET_US

func ensure(key: String,look: Dictionary) -> String:
	if actors.has(key):return actors[key]
	if over_budget():return ""
	loads_this_frame+=1
	var id: String=Look.dress(look,HEIGHT*ACTOR)
	if id=="":return ""
	actors[key]=id
	return id

const SCENE_KINDS:={"house":"ranch.room","press":"ranch.press","nursery":"ranch.lay","altar":"ranch.altar"}
## 毎フレーム：見えている施設の女・相手の魔物を置き、場面を流し続ける。
## 重さを抑えるため、見た目（Look）の辞書や出来事の辞書は、役者を借りるとき・場面を流し直すときにだけ作る。
func sync() -> void:
	sync_started=Time.get_ticks_usec();loads_this_frame=0
	var st=G.state
	var wanted: Dictionary={}
	var scene_wanted: Dictionary={}
	var women_by: Dictionary={}
	for w in st.women:women_by[int(w.uid)]=w
	var monsters_by: Dictionary={}
	for m in st.monsters:monsters_by[int(m.uid)]=m
	for f in st.facilities:
		if int(f.woman)<0:continue
		var rd: Dictionary=G.db.rooms[f.def]
		var kind: String=str(rd.kind)
		if not SCENE_KINDS.has(kind):continue
		var w: Dictionary=women_by.get(int(f.woman),{})
		if w.is_empty():continue
		var c: Vector2=st.fac_center(f)
		if not visible_cell(c):continue
		var m: Dictionary=monsters_by.get(int(f.get("monster",-1)),{})
		var servant: bool=m.is_empty() and kind=="press" and int(rd.get("staff",0))>0
		var has_partner: bool=not m.is_empty() or servant
		var solo: bool=int(rd.get("staff",0))<=0 or not has_partner
		var ka: String="w:%d"%int(w.uid)
		var a: String=actors[ka] if actors.has(ka) else ensure(ka,Look.woman(w))
		wanted[ka]=true
		if a!="":dress_extra(ka,a,w,f)
		var bkey: String="p:%d"%int(f.uid)
		var bid:=""
		if has_partner:
			bid=actors[bkey] if actors.has(bkey) else ensure(bkey,Look.monster(m) if not m.is_empty() else Look.servant())
			wanted[bkey]=true
		if a=="":continue
		var key: String="f:%d"%int(f.uid)
		var in_scene: bool=scenes.has(key) and G.anim.playing(scenes[key].handle)
		# 場面の中の役者は場面が描く。置き直し（行動の引き当て）は場面が無いときだけ。
		if not in_scene:
			G.anim.place(a,project(c),screen_facing(4),"idle")
			if bid!="":G.anim.place(bid,project(c+Vector2(0.6,0.3)),screen_facing(6),"idle")
		if rd.get("scene",false):
			var b: String="" if solo else bid
			var make_ev:=func() -> Dictionary:
				var tags_arr: Array=["named" if str(w.get("woman_id","")) !="" else "mob",str(w.job)]
				if not w.get("laying",{}).is_empty():tags_arr.append("laying")
				return {"kind":SCENE_KINDS[kind],"a":a,"b":b,"room":str(f.def),"phase":Captive.PHASES[clampi(int(w.stage),0,4)],"fall":Captive.top_stat(w),
					"target_definition_id":str(w.get("woman_id","")),"target_tags":tags_arr,"source_definition_id":str(m.get("species","")),"source_tags":[] if solo else ["monster"]}
			if keep_scene(key,a,b,str(f.def),SCENE_KINDS[kind],chosen_scene(f,solo),c,f,make_ev):scene_wanted[key]=true
	# 牢の女：格子の中でひざまずく（6人まで）
	var cell: Dictionary=st.first_of("cell")
	if not cell.is_empty() and visible_cell(st.fac_center(cell)):
		var cc: Vector2=st.fac_center(cell)
		var n:=0
		for w2 in st.women:
			if str(w2.use)!="cell":continue
			var i: int=n;n+=1
			if i>=6:break
			var k: String="w:%d"%int(w2.uid)
			var id: String=actors[k] if actors.has(k) else ensure(k,Look.woman(w2))
			wanted[k]=true
			if id=="":continue
			if str(dressed.get(k,""))!="":G.anim.parts(id,outfit_parts(w2,""));dressed.erase(k)
			G.anim.force_expression(id,"")
			var off:=Vector2((i%3-1)*0.5,(i/3)*0.55-0.25)
			G.anim.place(id,project(cc+off),screen_facing(4 if i%2==0 else 3),"caged")
	# 巣：休んでいる魔物（6体まで）
	var den: Dictionary=st.first_of("den")
	if not den.is_empty() and visible_cell(st.fac_center(den)):
		var dc: Vector2=st.fac_center(den)
		var n2:=0
		for m2 in st.monsters:
			if str(m2.job)!="rest":continue
			var i2: int=n2;n2+=1
			if i2>=6:break
			var k2: String="m:%d"%int(m2.uid)
			var id2: String=actors[k2] if actors.has(k2) else ensure(k2,Look.monster(m2))
			wanted[k2]=true
			var off2:=Vector2((i2%3-1)*0.55,(i2/3)*0.6-0.3)
			if id2!="":G.anim.place(id2,project(dc+off2),screen_facing(2+(i2%3)),"rest")
	for key in actors.keys():
		if not wanted.has(key):G.anim.release(actors[key]);actors.erase(key);dressed.erase(key)
	for key in scenes.keys():
		if not scene_wanted.has(key):G.anim.stop(scenes[key].handle);scenes.erase(key)

## 施設で流す場面：選んだ場面（1体の場面か2体の場面かが、相手のいる・いないに合うときだけ）。"" なら家具の場面（割り当て）。
func chosen_scene(f: Dictionary,solo: bool) -> String:
	var id: String=str(f.get("scene",""))
	if id=="":return ""
	var table: Dictionary=scene_solo()
	if not table.has(id):return ""
	return id if table[id]==solo else ""
## 場面ID → 1体の場面か（場面ファイルを何度も読まないよう、最初に一度だけ読む）
static var solo_table: Dictionary={}
static func scene_solo() -> Dictionary:
	if solo_table.is_empty():
		for sid in Library.ids():solo_table[sid]=Library.solo(Library.load_scene(sid))
	return solo_table

## 女の表情と服（施設ごとに選んだもの）。服は、頭はそのままで胴・腰・腕・脚を選んだキャラの服にする（肌の色が合う部位だけ）。
var dressed: Dictionary={}        # 役者の鍵 → 当てた服
func dress_extra(key: String,id: String,w: Dictionary,f: Dictionary) -> void:
	G.anim.force_expression(id,str(f.get("expr","")))
	var want: String=str(f.get("outfit",""))
	if str(dressed.get(key,""))==want:return
	G.anim.parts(id,outfit_parts(w,want))
	dressed[key]=want

static func outfit_parts(w: Dictionary,outfit: String) -> Dictionary:
	var parts: Dictionary=Look.woman(w).get("parts",{}).duplicate()
	if outfit=="":return parts
	var head: String=str(parts.get("head",Parts.BASE))
	for m in ["upper_body","lower_body","arms","legs"]:
		if m in Parts.provides(outfit) and Parts.same_skin(head,outfit):parts[m]=outfit
	return parts

## 場面を流し続ける（同じ役者・同じ場面なら流しっぱなし、変わったら流し直す）。
## 出来事の辞書（make_ev）は流し直すときだけ作る。流せなかった施設は1秒おいてから試し直す（毎フレーム引き当てない）。
var scene_retry: Dictionary={}    # 鍵 → 次に試せる時刻
func keep_scene(key: String,a: String,b: String,room: String,kind: String,pick: String,at: Vector2,f: Dictionary,make_ev: Callable) -> bool:
	var sc: Dictionary=scenes.get(key,{})
	if sc.is_empty() or not G.anim.playing(sc.handle) or sc.a!=a or sc.b!=b or sc.room!=room or sc.kind!=kind or str(sc.get("scene",""))!=pick:
		if not sc.is_empty():G.anim.stop(sc.handle);scenes.erase(key)
		if float(scene_retry.get(key,-1.0))>time:return false
		if over_budget():return false
		loads_this_frame+=1
		var h: int=G.anim.play_scene(pick,a,b,project(at),true) if pick!="" else G.anim.present(make_ev.call(),project(at),true)
		if h<0:scene_retry[key]=time+1.0;return false
		scene_retry.erase(key)
		scenes[key]={"handle":h,"a":a,"b":b,"room":room,"kind":kind,"scene":pick}
	var h2: int=scenes[key].handle
	G.anim.follow(h2,project(at))
	var fy: float=fmod(yaw_deg-float(int(f.get("rot",0)))*90.0+720.0,360.0)
	G.anim.view(h2,int(round(fy/45.0))%8,fy if rotating else NAN,pitch_deg*0.7,PPU*HEIGHT*ACTOR)
	return true

func release_all() -> void:
	for k in scenes:G.anim.stop(scenes[k].handle)
	scenes.clear()
	for k in actors:G.anim.release(actors[k])
	actors.clear()

# ───────── 描く ─────────
## 床のマスを奥から手前の順に並べる（向きが変わったときだけ並べ直す）。
func draw_order() -> Array:
	var key: int=int(round(yaw_deg))
	if key==order_key and not order_cache.is_empty():return order_cache
	var st=G.state
	var list: Array=[]
	var t:=deg_to_rad(yaw_deg)
	var fwd:=Vector2(sin(t),cos(t))
	for y in int(st.grid.h):
		for x in int(st.grid.w):list.append(Vector2i(x,y))
	list.sort_custom(func(a,c):return (Vector2(a)+Vector2(0.5,0.5)).dot(fwd)<(Vector2(c)+Vector2(0.5,0.5)).dot(fwd))
	order_cache=list;order_key=key
	return list

## 床のマスと奥の壁（視点が変わったときだけ描き直す）。
class TileLayer extends "res://game/map/iso.gd".Draw:
	func paint() -> void:
		var st=G.state
		var w: int=int(st.grid.w);var h: int=int(st.grid.h)
		var outer:=PackedVector2Array([map.project(Vector2(-4,-4)),map.project(Vector2(w+4,-4)),map.project(Vector2(w+4,h+4)),map.project(Vector2(-4,h+4))])
		fill(outer,Color("0b0809"))
		for c: Vector2i in map.draw_order():
			var cf:=Vector2(c)
			if not map.visible_cell(cf+Vector2(0.5,0.5),120):continue
			if st.cell(c.x,c.y)==0:continue
			var hsh: int=(c.x*73856093)^(c.y*19349663)
			var vv: float=float(absi(hsh)%13)/13.0
			fill(quad(cf),Color("201718").lerp(Color("2b2020"),vv))
			for d: Vector2i in [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]:
				if st.cell(c.x+d.x,c.y+d.y)!=0:continue
				back_wall(cf,d,1.15,Color("171112"))

## 施設・置く場所の影・指しているマス（毎フレーム）。
class FloorLayer extends "res://game/map/iso.gd".Draw:
	func paint() -> void:
		var st=G.state
		# 施設（奥から順に）
		var facs: Array=st.facilities.duplicate()
		facs.sort_custom(func(a,c):return map.project(st.fac_center(a)).y<map.project(st.fac_center(c)).y)
		for f in facs:
			if map.visible_cell(st.fac_center(f)):draw_fac(f)
		if not map.ghost.is_empty():draw_ghost()
		if map.hover_cell.x>=0 and map.mode!="build":
			var hc:=Vector2(map.hover_cell)
			poly_line(PackedVector2Array([map.project(hc),map.project(hc+Vector2(1,0)),map.project(hc+Vector2(1,1)),map.project(hc+Vector2(0,1)),map.project(hc)]),Color(Ui.GOLD,0.35),1.5)

	func fac_color(f: Dictionary) -> Color:
		var rd: Dictionary=G.db.rooms[f.def]
		match str(rd.kind):
			"house":return Ui.STAT[str(rd.house)].color
			"nursery":return Color("c4628c")
			"altar":return Color("9c6cc4")
			"press":return Color("d8b050")
			"den":return Color("7a8a6a")
		return Color("9a8470")

	func draw_fac(f: Dictionary) -> void:
		var st=G.state
		var c: Vector2=st.fac_center(f)
		var size: Vector2=Vector2(st.fac_size(f))
		var rad: float=minf(size.x,size.y)*0.5-0.06
		var kc: Color=fac_color(f)
		if str(G.db.rooms[f.def].kind)!="deco":
			disc(c,rad,Color(Color("1c1415").lerp(kc,0.12),0.9))
			circle_line(c,rad,Color(kc,0.3),1.5)
		draw_room(f,c)
		if map.dimmed.has(int(f.uid)):disc(c,rad+0.05,Color(0,0,0,0.55),0.3)
		if int(f.uid)==map.selected:circle_line(c,rad+0.06,Ui.GOLD_HI,3.0)

	## 家具の絵。k は大きさの倍率（1マスの家具は0.5。2×2の牢・巣は1）。
	func draw_room(f: Dictionary,c: Vector2) -> void:
		var t: float=map.time
		var S: float=map.ACTOR
		var has_scene: bool=map.scenes.has("f:%d"%int(f.uid))
		var sz: Vector2=Vector2(G.state.fac_size(f))
		var k: float=clampf(minf(sz.x,sz.y)*0.5,0.5,1.0)
		var long: bool=maxf(sz.x,sz.y)>=2.0 and minf(sz.x,sz.y)<2.0
		var ax: Vector2=Vector2(0,1) if sz.y>sz.x else Vector2(1,0)
		match f.def:
			"cell":bars(c,0.9,1.9,false)
			"den":
				disc(c,0.85,Color("3a3020"))
				for i in 7:
					var an: float=i*TAU/7.0
					line(map.project(c+Vector2(cos(an),sin(an))*0.5,0.05),map.project(c+Vector2(cos(an+0.6),sin(an+0.6))*0.8,0.08),Color("8a7a4a"),2)
			"nursery":
				cyl(c,0.86*k,(0.2)*S,Color("5a4a2a"))
				disc(c,0.7*k,Color("7a3a4a"),0.2)
			"altar":pass   # 魔法陣は FxLayer（回るので毎フレーム）
			"trash":
				if not has_scene:cyl(c,0.36,(0.95)*S,Color("46504a"))
			"wall":
				if not has_scene:box(c,Vector2(0.9,0.12),(1.35)*S,Color("4a3f3c"))
			"horse":
				if not has_scene:box(c,Vector2(0.3,1.6) if ax.y>0 else Vector2(1.6,0.3),(0.7)*S,Color("5a3e26"))
			"barrel":
				if not has_scene:cyl(c,0.32,(0.9)*S,Color("7e542e"))
			"sweet":
				box(c,Vector2(0.85,0.9),(0.22)*S,Color("4a1a26"))
				box(c+Vector2(0,0.06),Vector2(0.78,0.7),(0.05)*S,Color("7a3040"),0.22)
			"torment","post":box(c+Vector2(0,-0.3),Vector2(0.14,0.14),(2.0)*S,Color("4a3222"))
			"bondage","table","stepped":box(c,Vector2(0.6,0.8),(0.3)*S,Color("3a2a2a"))
			"bridge":box(c,Vector2(0.6,1.7) if ax.y>0 else Vector2(1.7,0.6),(0.3)*S,Color("3a2a2a"))
			"pleasure":
				cyl(c,0.44,(0.22)*S,Color("2a1e22"))   # 上の揺らめく面は FxLayer
			"milking","cattle","pillory":
				for sx in [-0.34,0.34]:box(c+Vector2(sx,-0.2),Vector2(0.08,0.08),(1.0)*S,Color("5a3e26"))
				box(c+Vector2(0,-0.2),Vector2(0.8,0.08),(0.12)*S,Color("8a6a44"),0.7)
			"stand","dog_trick","hip_dance":
				cyl(c,0.42,(0.25)*S,Color("4a3a3a"))
				circle_line(c,0.36,Color(Ui.GOLD,0.4),1.5,0.25)
			"crucifix":box(c-ax*0.55,Vector2(0.9,0.1) if ax.y>0 else Vector2(0.1,0.9),(1.9)*S,Color("5a3e26"))
			"hang":
				for sx in [-0.38,0.38]:box(c+Vector2(sx,0),Vector2(0.1,0.1),(2.3)*S,Color("5a3e26"))
			"cage":fence(c,0.46,0.62,false)
			"dog_walk","pony_ride","rope_walk":
				if long:box(c,Vector2(0.12,1.7) if ax.y>0 else Vector2(1.7,0.12),(0.05)*S,Color("6a4a30"))
			# ───── 飾り ─────
			"candle":
				cyl(c,0.12,(0.5)*S,Color("d8c8a0"))
			"torch":
				box(c,Vector2(0.12,0.12),(1.5)*S,Color("4a3222"))
			"chain_post":
				box(c,Vector2(0.16,0.16),(1.8)*S,Color("3a3030"))
				for i in 5:dot(map.project(c+Vector2(0.14,0),(1.6-i*0.28)*S),2.5,Color("8a8a90"))
			"crate":box(c,Vector2(0.7,0.7),(0.6)*S,Color("7a5a36"))
			"keg":cyl(c,0.34,(0.8)*S,Color("6e4a2a"))
			"bones":
				for i in 5:
					var o:=Vector2(cos(i*1.7),sin(i*2.3))*0.25
					line(map.project(c+o,0.04),map.project(c+o+Vector2(0.18,0.06).rotated(i),0.04),Color("d8d0c0"),3)
			"rug":
				var h:=Vector2(sz)*0.5-Vector2(0.08,0.08)
				fill(PackedVector2Array([map.project(c+Vector2(-h.x,-h.y),0.01),map.project(c+Vector2(h.x,-h.y),0.01),map.project(c+Vector2(h.x,h.y),0.01),map.project(c+Vector2(-h.x,h.y),0.01)]),Color("5a1822"))
				var h2:=h-Vector2(0.15,0.15)
				poly_line(PackedVector2Array([map.project(c+Vector2(-h2.x,-h2.y),0.02),map.project(c+Vector2(h2.x,-h2.y),0.02),map.project(c+Vector2(h2.x,h2.y),0.02),map.project(c+Vector2(-h2.x,h2.y),0.02),map.project(c+Vector2(-h2.x,-h2.y),0.02)]),Color(Ui.GOLD,0.55),2.0)
			"pillar":cyl(c,0.3,(2.2)*S,Color("5a5450"))
			"brazier":
				cyl(c,0.3,(0.55)*S,Color("3a2a22"))
			"banner":
				box(c+Vector2(-0.3,0),Vector2(0.06,0.06),(2.0)*S,Color("3a2a22"))
				fill(PackedVector2Array([map.project(c+Vector2(-0.27,0),1.9*S),map.project(c+Vector2(0.3,0),1.9*S),map.project(c+Vector2(0.3,0),1.1*S),map.project(c+Vector2(0.0,0),1.25*S),map.project(c+Vector2(-0.27,0),1.1*S)]),Color("7a1826"))
			_:box(c+Vector2(0.2,-0.2)*k,Vector2(0.3,0.3),(0.4)*S,Color("4a3222"))

	## 揺れる炎。
	func flame(c: Vector2,height: float,r: float) -> void:
		var fl: float=0.8+0.2*sin(map.time*9.0+c.x*3.1)
		var p: Vector2=map.project(c,height)
		var px: float=r*map.PPU*map.zoom*0.5
		dot(p,px*2.2*fl,Color(1.0,0.5,0.15,0.15))
		dot(p,px*fl,Color("ffb040"))
		dot(p+Vector2(0,-px*0.6),px*0.55*fl,Color("fff0a0"))

	func draw_ghost() -> void:
		var g: Dictionary=map.ghost
		var s: Array=G.db.rooms[g.def].size
		var size:=Vector2i(int(s[1]),int(s[0])) if int(g.rot)%2==1 else Vector2i(int(s[0]),int(s[1]))
		var p0:=Vector2(g.x,g.y);var p2:=p0+Vector2(size)
		var poly:=PackedVector2Array([map.project(p0),map.project(Vector2(p2.x,p0.y)),map.project(p2),map.project(Vector2(p0.x,p2.y))])
		var col:=Color(0.5,0.85,0.45,0.3) if g.ok else Color(0.9,0.25,0.2,0.35)
		fill(poly,col)
		poly_line(PackedVector2Array([poly[0],poly[1],poly[2],poly[3],poly[0]]),Color(col,0.9),2)

## 施設の動く部分（炎・回る魔法陣・揺らめく面・選べる施設の光る縁取り）。これだけ毎フレーム描く。
class FxLayer extends FloorLayer:
	func paint() -> void:
		var st=G.state
		var t: float=map.time
		var S: float=map.ACTOR
		for f in st.facilities:
			var c: Vector2=st.fac_center(f)
			if not map.visible_cell(c):continue
			var sz: Vector2=Vector2(st.fac_size(f))
			var k: float=clampf(minf(sz.x,sz.y)*0.5,0.5,1.0)
			match f.def:
				"altar":flush();Ui.draw_sigil(self,map.project(c,0.02),48.0*k,Color("b07ae0"),t,0.45)
				"pleasure":disc(c,0.38,Color(Color("5e2a70").lerp(Color("2f7a5a"),0.5+0.5*sin(t*0.8)),0.92),0.22*S)
				"candle":flame(c,(0.6)*S,0.09)
				"torch":flame(c,(1.6)*S,0.14)
				"brazier":flame(c,(0.65)*S,0.2)
			var hl: Color=map.highlight.get(int(f.uid),Color.TRANSPARENT)
			if hl.a>0:
				var rad: float=minf(sz.x,sz.y)*0.5-0.06
				disc(c,rad,Color(hl,0.14+0.07*sin(t*4)))
				circle_line(c,rad,Color(hl.lightened(0.3),0.75+0.25*sin(t*4)),3.0)

## 牢の格子・囲いの手前側は役者より手前に描く。
class FrontLayer extends "res://game/map/iso.gd".Draw:
	func paint() -> void:
		var st=G.state
		var c: Dictionary=st.first_of("cell")
		if not c.is_empty() and map.visible_cell(st.fac_center(c)):bars(st.fac_center(c),0.9,1.9,true)
		for f in st.facilities:
			if f.def=="cage":fence(st.fac_center(f),0.86,0.62,true)

## 画面の画素で描く印：施設の名前（寄ったとき）、産む途中の卵、妊娠の印。
class TagLayer extends Node2D:
	var map
	func _draw() -> void:
		var z: float=maxf(map.zoom,0.01)
		draw_set_transform(Vector2.ZERO,0,Vector2(1.0/z,1.0/z))
		var st=G.state
		var font: Font=Ui.head_font if Ui.head_font!=null else ThemeDB.fallback_font
		for f in st.facilities:
			var c: Vector2=st.fac_center(f)
			if not map.visible_cell(c):continue
			var w: Dictionary=st.woman(int(f.woman))
			if not w.is_empty() and not w.get("laying",{}).is_empty():
				var p: Vector2=map.project(c,2.6)*z
				draw_circle(p,9,Color(0,0,0,0.6));draw_circle(p,7,Ui.PINK)
				draw_string(font,p+Vector2(12,6),"あと%d晩"%int(w.laying.nights),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Ui.PINK)
			if map.hints.has(int(f.uid)):
				var hn: Dictionary=map.hints[int(f.uid)]
				var ok: bool=map.highlight.has(int(f.uid))
				var hp: Vector2=map.project(c,2.9)*z
				var txt: String=str(hn.text)
				var fs: int=16
				var tw: float=font.get_string_size(txt,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
				var r:=Rect2(hp.x-tw*0.5-10,hp.y-22,tw+20,28)
				draw_rect(r,Color(0.05,0.03,0.04,0.9))
				draw_rect(r,Color("78c27a") if ok else Color(0.4,0.3,0.3),false,2.0 if ok else 1.0)
				draw_string(font,Vector2(r.position.x+10,r.position.y+20),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,(hn.color as Color).lightened(0.2) if ok else Ui.FAINT)
				continue
			if map.zoom>=1.6 and int(f.uid)!=map.selected:
				var p2: Vector2=map.project(c,0.0)*z+Vector2(0,26)
				draw_string_outline(font,p2+Vector2(-80,0),str(G.db.rooms[f.def].name),HORIZONTAL_ALIGNMENT_CENTER,160,14,4,Color(0,0,0,0.8))
				draw_string(font,p2+Vector2(-80,0),str(G.db.rooms[f.def].name),HORIZONTAL_ALIGNMENT_CENTER,160,14,Color(Ui.DIM,0.9))
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
