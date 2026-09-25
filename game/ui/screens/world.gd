extends Control
## 大陸の地図（企画書 4.1・設計書 8.1）。開いている地方に、今日の狩場と次のストーリー戦を並べる。
## 選んだ出撃先の一行（職・★・能力）、地形、報酬、スタミナを出し、編成へ進む。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const TopBar=preload("res://game/ui/parts/top_bar.gd")
const Help=preload("res://game/ui/parts/help.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Sites=preload("res://game/world/sites.gd")
const MAP_RECT:=Rect2(24,78,1400,866)
const INFO_RECT:=Rect2(1440,78,466,866)
var canvas: MapCanvas
var info_box: VBoxContainer
var selected:=""
var go_button: Button

func open(p: Dictionary) -> void:
	var frame:=Ui.placed_panel(self,MAP_RECT,10,Color("120d0b"))
	canvas=MapCanvas.new();canvas.screen=self;canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL;canvas.clip_contents=true
	frame.add_child(canvas)
	var top:=TopBar.new();top.help_topic="world";add_child(top)
	var right:=Ui.placed_panel(self,INFO_RECT,20)
	info_box=Ui.scroll_box(right,10)
	var bottom:=Ui.hbox(12);bottom.position=Vector2(28,958);bottom.custom_minimum_size=Vector2(1878,96);add_child(bottom)
	bottom.add_child(legend())
	bottom.add_child(Ui.spacer())
	var back:=Ui.icon_button("back","牧場へ戻る",func():G.main.goto("ranch",{}),19);back.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bottom.add_child(back)
	go_button=Ui.icon_button("group","編成へ",go,22);Ui.primary_style(go_button);go_button.custom_minimum_size=Vector2(260,64);go_button.size_flags_vertical=Control.SIZE_SHRINK_CENTER;go_button.disabled=true;bottom.add_child(go_button)
	var first:=""
	for s in G.state.world.sites_today:
		if str(s.kind)=="story":first=str(s.id)
	if first=="":
		for s in G.state.world.sites_today:
			if not Sites.done(s):first=str(s.id);break
	select(str(p.get("site",first)))
	Ui.rise_in(frame,0.0);Ui.rise_in(right,0.08)
	Help.first("world")

func legend() -> Control:
	var h:=Ui.hbox(10)
	for item in [["ストーリー戦","crown",Ui.GOLD],["狩場（日替わり）","flag",Ui.GOOD],["まだ行けない地方","lock",Ui.FAINT]]:
		var c:=Ui.chip(item[0],item[2],14,item[1]);c.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(c)
	return h

func select(id: String) -> void:
	selected=id
	canvas.queue_redraw()
	for c in info_box.get_children():c.queue_free()
	var site: Dictionary=Sites.find(id)
	go_button.disabled=true
	if site.is_empty():return
	var st=G.state
	var r: Dictionary=G.db.regions[G.db.region_index(str(site.region))]
	var h:=Ui.hbox(12);info_box.add_child(h)
	h.add_child(Ui.icon_disc(str(site.icon),50,Ui.GOLD if str(site.kind)=="story" else Ui.GOOD))
	var v:=Ui.vbox(2);h.add_child(v)
	v.add_child(Ui.title(str(site.name),30))
	v.add_child(Ui.label("%s　%s"%[r.name,"ストーリー戦" if str(site.kind)=="story" else "狩場"],15,Ui.DIM,true))
	info_box.add_child(Ui.rule())
	var k0: int=Sites.start_k(site)
	var cost0: int=Sites.cost_of(site,k0)
	var cost_line: String="スタミナ %d"%cost0
	if site.chain.size()>1:cost_line+="（%d連戦。2戦目から %d ずつ）"%[site.chain.size(),Sites.cost_of(site,1)]
	var ch:=Ui.chip(cost_line,Ui.INFO if int(st.stamina.now)>=cost0 else Ui.DANGER,14,"bolt");info_box.add_child(ch)
	if k0>0:info_box.add_child(Ui.label("%d戦目まで勝ってある。%d戦目から挑む。"%[k0,k0+1],15,Ui.GOOD))
	if str(site.kind)=="story":info_box.add_child(Ui.wrap_label(str(r.get("intro","")),14,Ui.DIM,420))
	for k in range(k0,site.chain.size()):
		var f: Dictionary=site.chain[k]
		info_box.add_child(Ui.section("%d戦目"%(k+1) if site.chain.size()>1 else "一行","報酬 金 %d"%int(f.reward)))
		for m in f.party:info_box.add_child(member_row(m))
	info_box.add_child(Ui.section("地形"))
	var bp:=BoardPreview.new();bp.rows=site.board;bp.custom_minimum_size=Vector2(200,200);bp.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;info_box.add_child(bp)
	info_box.add_child(Ui.label("森：離れた所からの攻撃が半分　川：入ると次の番は動けない　崖：通れない",12,Ui.FAINT))
	go_button.disabled=int(st.stamina.now)<cost0 or Sites.done(site)
	go_button.tooltip_text="今日はもう勝った（明日は別の一行が来る）" if Sites.done(site) else ("スタミナが足りない" if go_button.disabled else "")
	if Sites.done(site):info_box.add_child(Ui.label("今日はもう勝った。明日は別の一行が来る。",15,Ui.GOOD))

func member_row(m: Dictionary) -> Control:
	var jd: Dictionary=G.db.jobs[str(m.job)]
	var row:=Ui.list_row(false,Color(str(jd.color)),8)
	var v:=Ui.vbox(2);row.add_child(v)
	var h:=Ui.hbox(6);v.add_child(h)
	h.add_child(Cards.job_chip(str(m.job),12))
	h.add_child(Ui.label(str(m.name),16,Ui.GOLD_HI if str(m.get("named",""))!="" else Ui.TEXT,true))
	h.add_child(Ui.stars(int(m.star),12))
	if bool(m.get("gifted",false)):h.add_child(Ui.chip("逸材",Ui.GOLD,11))
	var s:=Ui.hbox(6);v.add_child(s)
	for k in Ui.STATS:s.add_child(Ui.label("%s%d"%[Ui.STAT[k].glyph,int(m.stats[k])],13,Ui.STAT[k].color))
	var sk: String=str(G.db.women[str(m.named)].unique) if str(m.get("named",""))!="" else str(jd.get("skill",""))
	if sk!="":s.add_child(Ui.label("　"+G.db.skill_name(sk),13,Ui.GOLD if str(m.get("named",""))!="" else Ui.DIM))
	row.tooltip_text=str(G.db.skill(sk).get("desc","")) if sk!="" else ""
	return row

func go() -> void:
	var site: Dictionary=Sites.find(selected)
	if site.is_empty():return
	G.main.goto("prep",{"site":selected,"k":Sites.start_k(site)})

class BoardPreview extends Control:
	var rows: Array=[]
	func _draw() -> void:
		var n: int=rows.size()
		if n==0:return
		var c: float=size.x/float(n)
		for y in n:
			var row: String=str(rows[y])
			for x in row.length():
				var t: String=row.substr(x,1)
				var col: Color={"#":Color("5a4a40"),"~":Color("28506a"),"\"":Color("2f4a28")}.get(t,Color("2a2320"))
				if x<2 and t!="#":col=col.lerp(Color("7299bf"),0.25)
				draw_rect(Rect2(x*c+1,y*c+1,c-2,c-2),col)

class MapCanvas extends Control:
	var screen
	var time:=0.0
	var hits: Array=[]              # [{rect, id}]
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_STOP
	func _process(delta: float) -> void:
		time+=delta;queue_redraw()
	func at(p: Array) -> Vector2:
		return Vector2(float(p[0])*size.x,float(p[1])*size.y)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_LEFT:
			for h in hits:
				if h.rect.has_point(e.position):screen.select(str(h.id));G.main.sfx("click");return

	func medal(c: Vector2,r: float,icon: String,color: Color,sel: bool) -> void:
		var U=preload("res://game/ui/ui.gd")
		var I=preload("res://game/ui/icons.gd")
		if sel:draw_arc(c,r+6+sin(time*5)*2,0,TAU,40,U.GOLD_HI,3,true)
		draw_circle(c+Vector2(0,2),r,Color(0,0,0,0.5))
		draw_circle(c,r,Color("140d10"))
		draw_circle(c,r*0.84,color.darkened(0.65))
		draw_arc(c,r-1,0,TAU,40,U.GOLD.darkened(0.2),2,true)
		draw_arc(c,r*0.84,0,TAU,40,Color(color,0.8),1.5,true)
		var t: Texture2D=I.tex(icon,int(r*1.2))
		if t!=null:draw_texture_rect(t,Rect2(c-Vector2(r,r)*0.6,Vector2(r,r)*1.2),false,color.lightened(0.25))

	func plate(c: Vector2,text: String,color: Color) -> void:
		var U=preload("res://game/ui/ui.gd")
		var f: Font=U.head_font
		var fs:=16
		var tw: float=f.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		var r:=Rect2(c.x-tw*0.5-10,c.y,tw+20,24)
		draw_rect(r,Color("140d0c",0.9))
		draw_rect(r,Color(U.GOLD,0.5),false,1.0)
		draw_string(f,Vector2(r.position.x+10,r.position.y+18),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)

	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var st=G.state;var db=G.db
		hits=[]
		draw_rect(Rect2(Vector2.ZERO,size),Color("1b1410"))
		for i in 60:
			var y: float=i*size.y/60.0
			draw_line(Vector2(0,y),Vector2(size.x,y+6),Color(0.35,0.26,0.18,0.035),1)
		U.draw_sigil(self,Vector2(size.x-110,size.y-100),62,Color(U.GOLD,0.5),time*0.2,1.0,false)
		# 地方の領地と道
		for i in db.regions.size():
			var r: Dictionary=db.regions[i]
			if i>0:draw_dashed_line(at(db.regions[i-1].pos),at(r.pos),Color(U.GOLD,0.35),2,10)
		for i in db.regions.size():
			var r: Dictionary=db.regions[i]
			var c: Vector2=at(r.pos)
			var open: bool=str(r.id) in st.unlocked.regions
			var done: bool=i<st.chapter
			var col: Color=U.CRIMSON.darkened(0.2) if done else (Color(str(r.color)).darkened(0.5) if open else Color("2a2018"))
			var rng:=RandomNumberGenerator.new();rng.seed=hash(str(r.id))
			var pts:=PackedVector2Array()
			for k in 22:
				var a:=k*TAU/22
				var rr:=rng.randf_range(80,110)
				pts.append(c+Vector2(cos(a)*rr*1.25,sin(a)*rr*0.85))
			draw_colored_polygon(pts,Color(col,0.9))
			var closed:=pts+PackedVector2Array([pts[0]])
			draw_polyline(closed,Color("0c0807"),4,true)
			draw_polyline(closed,Color(U.GOLD,0.6 if open else 0.2),1.5,true)
			plate(c+Vector2(0,78),str(r.name)+("（落とした）" if done else ""),U.TEXT if open else U.FAINT)
			if not open:medal(c,22,"lock",U.FAINT,false)
		# 魔王城
		var castle: Vector2=at([0.06,0.86])
		medal(castle,26,"castle",U.CRIMSON.lightened(0.35),false)
		# 出撃先
		var per: Dictionary={}
		for s in st.world.sites_today:
			var ri: int=db.region_index(str(s.region))
			var idx: int=int(per.get(ri,0));per[ri]=idx+1
			var c2: Vector2=at(db.regions[ri].pos)
			var off: Vector2=Vector2(0,-6) if str(s.kind)=="story" else Vector2(cos(-PI*0.5+PI*0.55*(idx)),sin(-PI*0.5+PI*0.55*(idx)))*62.0+Vector2(0,10)
			if str(s.kind)=="story":off=Vector2(0,-10)
			var p: Vector2=c2+off
			var sel: bool=str(s.id)==str(screen.selected)
			var col2: Color=U.GOLD if str(s.kind)=="story" else U.GOOD
			if int(st.stamina.now)<int(s.cost) or Sites.done(s):col2=col2.darkened(0.55)
			medal(p,20 if str(s.kind)=="story" else 16,str(s.icon),col2,sel)
			hits.append({"rect":Rect2(p-Vector2(24,24),Vector2(48,48)),"id":str(s.id)})
			var f: Font=U.body_font
			draw_string_outline(f,p+Vector2(-60,34),str(s.name),HORIZONTAL_ALIGNMENT_CENTER,120,13,4,Color(0,0,0,0.9))
			draw_string(f,p+Vector2(-60,34),str(s.name),HORIZONTAL_ALIGNMENT_CENTER,120,13,U.GOLD_HI if sel else U.TEXT)
