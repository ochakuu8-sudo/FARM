extends RefCounted
## 女・魔物を並べて見せる共通の部品（一覧の行、4つの能力の棒、詳しい中身）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Sk=preload("res://game/battle/skills.gd")
const Look=preload("res://game/map/look.gd")
const JOB_NAMES:={"rest":"巣で休む","partner":"相手役","father":"父","none":"待機"}
const GRADES:=["並","良","稀","伝説"]

## 4つの能力の棒。ghost は予測（同じ辞書の形）、caps は素質（上限の目盛り）。
static func stat_bars(values: Dictionary,maximum: float=100.0,width: float=220,ghost: Dictionary={},caps: Dictionary={}) -> VBoxContainer:
	var v:=Ui.vbox(3)
	for k in Ui.STATS:
		var h:=Ui.hbox(8);v.add_child(h)
		var l:=Ui.label(Ui.STAT[k].name,15,Ui.STAT[k].color,true);l.custom_minimum_size=Vector2(22,0);h.add_child(l)
		var m=Ui.meter(float(values.get(k,0)),maximum,Ui.STAT[k].color,width,12)
		if ghost.has(k):m.ghost=float(ghost[k])
		m.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		if caps.has(k):
			var tick:=CapTick.new();tick.maximum=maximum;tick.cap=float(caps[k]);Ui.full(tick);tick.mouse_filter=Control.MOUSE_FILTER_IGNORE;m.add_child(tick)
		h.add_child(m)
		var txt: String="%d"%int(round(float(values.get(k,0))))
		if caps.has(k):txt+=" / %d"%int(round(float(caps[k])))
		h.add_child(Ui.num(txt,15,Ui.TEXT))
	return v

class CapTick extends Control:
	var maximum:=100.0
	var cap:=100.0
	func _draw() -> void:
		var x: float=size.x*clampf(cap/maximum,0,1)
		draw_rect(Rect2(x,0,size.x-x,size.y),Color(0,0,0,0.55))
		draw_line(Vector2(x,-3),Vector2(x,size.y+3),Color(1,0.9,0.6,0.9),2.0)

## 予想の幅の棒（卵の画面）。
static func range_bars(pred: Dictionary,width: float=260) -> VBoxContainer:
	var v:=Ui.vbox(4)
	for k in Ui.STATS:
		var lo: float=float(pred[k][0]);var hi: float=float(pred[k][1])
		var h:=Ui.hbox(8);v.add_child(h)
		var l:=Ui.label(Ui.STAT[k].name,15,Ui.STAT[k].color,true);l.custom_minimum_size=Vector2(22,0);h.add_child(l)
		var bar:=RangeBar.new();bar.lo=lo;bar.hi=hi;bar.color=Ui.STAT[k].color;bar.custom_minimum_size=Vector2(width,14);bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(bar)
		h.add_child(Ui.num("%d〜%d"%[int(lo),int(hi)] if int(lo)!=int(hi) else "%d"%int(lo),15,Ui.TEXT))
	return v

class RangeBar extends Control:
	var lo:=0.0
	var hi:=0.0
	var color:=Color.WHITE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("0c0809"))
		var a: float=size.x*clampf(lo/100.0,0,1);var b: float=size.x*clampf(hi/100.0,0,1)
		draw_rect(Rect2(0,0,a,size.y),color.darkened(0.3))
		draw_rect(Rect2(a,0,maxf(2,b-a),size.y),Color(color.lightened(0.2),0.9))
		draw_rect(Rect2(Vector2.ZERO,size),Color("3a2a26"),false,1.0)

# ───────── 見分けのつく記号と札 ─────────
## 女の記号：角丸の額縁に、髪の色の頭と肩（人の姿）。職の記号を右下に小さく。名前付きは金の額縁。
## 魔物は丸い金属の円盤なので、形でどちらか分かる。
static func woman_icon(w: Dictionary,px: int=36) -> Control:
	var jd: Dictionary=G.db.jobs.get(str(w.job),{})
	var c:=Cameo.new()
	c.hair=Color(str(w.get("hair","#a06040")))
	c.skin=Color(str(w.get("tint",""))) if str(w.get("tint",""))!="" else Color("e8c8b0")
	c.named=str(w.get("woman_id",""))!=""
	c.job_icon=Icons.tex(str(jd.get("icon","heart")),int(px*0.42))
	c.job_color=Color(str(jd.get("color","#a89070")))
	c.custom_minimum_size=Vector2(px,px)
	c.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	c.tooltip_text="%s（%s）"%[w.name,jd.get("name","")]
	return c

class Cameo extends Control:
	var hair:=Color("a06040")
	var skin:=Color("e8c8b0")
	var named:=false
	var job_icon: Texture2D
	var job_color:=Color.WHITE
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var w: float=size.x;var h: float=size.y
		var r:=Rect2(1,1,w-2,h-2)
		var frame: Color=U.GOLD if named else U.PINK
		var sb:=StyleBoxFlat.new()
		sb.bg_color=Color("2a1420");sb.border_color=frame;sb.set_border_width_all(2);sb.set_corner_radius_all(int(w*0.22));sb.anti_aliasing=true
		draw_style_box(sb,r)
		# 肩と胸（衣の色は職の色）
		var cx: float=w*0.5
		var sh:=PackedVector2Array()
		for i in 13:
			var t: float=PI+PI*float(i)/12.0
			sh.append(Vector2(cx+cos(t)*w*0.34,h*0.98+sin(t)*h*0.30))
		draw_colored_polygon(sh,job_color.darkened(0.25))
		# 髪（後ろ）と顔と前髪
		draw_circle(Vector2(cx,h*0.44),w*0.23,hair.darkened(0.1))
		draw_circle(Vector2(cx,h*0.47),w*0.16,skin)
		draw_arc(Vector2(cx,h*0.44),w*0.20,PI*1.05,PI*1.95,16,hair,w*0.09,true)
		# 職の記号（右下の小さな円）
		if job_icon!=null:
			var bc:=Vector2(w*0.78,h*0.78);var br: float=w*0.2
			draw_circle(bc,br+1.5,Color("140d10"))
			draw_circle(bc,br,job_color.darkened(0.55))
			draw_texture_rect(job_icon,Rect2(bc-Vector2(br,br)*0.75,Vector2(br,br)*1.5),false,job_color.lightened(0.3))

static func monster_color(m: Dictionary) -> Color:
	var c: Color=Look.monster(m).get("tint",Color.WHITE)
	return c

## 魔物の記号：種族の記号を、その個体の色（母の面影）の円盤に載せる。
static func monster_icon(m: Dictionary,px: int=36) -> Control:
	var d: Control=Ui.icon_disc(species_icon(str(m.species)),px,monster_color(m).lightened(0.1))
	d.tooltip_text="%s（%s）"%[m.name,G.db.species_name(str(m.species))]
	return d

## 札：記号と名前と一言。押して離すと on_click。dim は選べないとき（理由は note に出す）。
## drag を渡すと引きずれる：{"move": Callable(画面の位置), "drop": Callable(画面の位置)}。
static func tile(icon: Control,name: String,note: String,note_color: Color,selected: bool,on_click: Callable,dim: bool=false,accent: Color=Ui.GOLD,drag: Dictionary={}) -> PanelContainer:
	var p:=Ui.list_row(selected,accent,8)
	p.custom_minimum_size=Vector2(0,54)
	p.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var h:=Ui.hbox(8);p.add_child(h)
	h.add_child(icon)
	var v:=Ui.vbox(0);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;v.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(v)
	var nl:=Ui.label(name,16,Ui.GOLD_HI if selected else Ui.TEXT,true);nl.clip_text=true;nl.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;v.add_child(nl)
	if note!="":
		var l:=Ui.label(note,12,note_color);l.clip_text=true;l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;v.add_child(l)
	if dim:p.modulate=Color(1,1,1,0.5)
	var st:={"down":false,"from":Vector2.ZERO,"moved":false}
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT:
			if e.pressed:st.down=true;st.from=e.global_position;st.moved=false
			elif st.down:
				st.down=false
				if st.moved and drag.has("drop"):drag.drop.call(e.global_position)
				else:on_click.call()
		elif e is InputEventMouseMotion and st.down and not drag.is_empty():
			if e.global_position.distance_to(st.from)>12:st.moved=true
			if st.moved and drag.has("move"):drag.move.call(e.global_position))
	return p

static func woman_tile(w: Dictionary,selected: bool,on_click: Callable,note: String="",note_color: Color=Ui.DIM,dim: bool=false,drag: Dictionary={}) -> PanelContainer:
	var t: PanelContainer=tile(woman_icon(w),"%s %s"%[str(w.name),"★".repeat(clampi(int(w.star),1,5))],note,note_color,selected,on_click,dim,Ui.PINK,drag)
	t.tooltip_text=woman_title(w)
	return t

static func monster_tile(m: Dictionary,selected: bool,on_click: Callable,note: String="",note_color: Color=Ui.DIM,dim: bool=false,drag: Dictionary={}) -> PanelContainer:
	var t: PanelContainer=tile(monster_icon(m),str(m.name),note,note_color,selected,on_click,dim,monster_color(m),drag)
	t.tooltip_text="%s　%s%s"%[m.name,G.db.species_name(str(m.species)),"　"+str(m.get("kin","")) if str(m.get("kin",""))!="" else ""]
	return t

## 札を並べる格子（cols 列）。
static func tile_grid(cols: int=2) -> GridContainer:
	var g:=GridContainer.new();g.columns=cols
	g.add_theme_constant_override("h_separation",6);g.add_theme_constant_override("v_separation",6)
	g.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return g

## 女の札の一言（今の様子）。
static func woman_note(w: Dictionary) -> String:
	var parts: Array=[G.db.jobs[str(w.job)].name,Ui.STAGES[int(w.stage)],Captive.USE_NAMES.get(str(w.use),"")]
	if not w.get("laying",{}).is_empty():parts.append("産む あと%d晩"%int(w.laying.nights))
	return "・".join(parts)

## 魔物の札の一言（種族・体力・今夜の務め）。
static func monster_note(m: Dictionary) -> String:
	var mx: int=Stats.hp_max(m)
	return "%s〔%s〕・体力%d/%d・%s"%[G.db.species_name(str(m.species)),role_of(str(m.species)),int(m.hp),mx,JOB_NAMES.get(str(m.job),"待機") if not Stats.ko(m) else "倒れている"]

## 種族の役割（盾・近接・暗殺・遠距離・術・妨害・回復・支援）と、その色。
const ROLE_COLORS:={"盾":"7a8aa0","近接":"c07050","暗殺":"a070c0","遠距離":"80a050","術":"e07040","妨害":"c05080","回復":"60b090","支援":"d0b050"}
static func role_of(species: String) -> String:
	return str(G.db.species.get(species,{}).get("role",""))

static func role_chip(species: String,size: int=12) -> Control:
	var r: String=role_of(species)
	return Ui.chip(r if r!="" else "―",Color(str(ROLE_COLORS.get(r,"888888"))),size)

static func job_chip(job: String,size: int=13) -> Control:
	var d: Dictionary=G.db.jobs[job]
	return Ui.chip(str(d.name),Color(str(d.color)),size)

static func woman_title(w: Dictionary) -> String:
	return "%s%s"%[w.name,"（%s）"%G.db.women[w.woman_id].title if str(w.get("woman_id",""))!="" else ""]

## 女の一覧の1行。
static func woman_row(w: Dictionary,selected: bool,on_click: Callable) -> Control:
	var row:=Ui.list_row(selected,Ui.PINK,10)
	var h:=Ui.hbox(10);row.add_child(h)
	h.add_child(woman_icon(w,34))
	var v:=Ui.vbox(2);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;h.add_child(v)
	var top:=Ui.hbox(6);v.add_child(top)
	top.add_child(Ui.label(woman_title(w),17,Ui.GOLD_HI if str(w.get("woman_id",""))!="" else Ui.TEXT,true))
	top.add_child(Ui.stars(int(w.star),13))
	if bool(w.get("gifted",false)):top.add_child(Ui.chip("逸材",Ui.GOLD,11))
	var sub:=Ui.hbox(6);v.add_child(sub)
	sub.add_child(job_chip(str(w.job),12))
	sub.add_child(Ui.chip(Ui.STAGES[int(w.stage)],Ui.STAGE_COLORS[int(w.stage)],12))
	sub.add_child(Ui.chip(Captive.USE_NAMES.get(str(w.use),"?"),Ui.DIM,12))
	sub.add_child(Ui.chip("卵 残り%d"%int(w.eggs_left),Ui.PINK if int(w.eggs_left)>0 else Ui.FAINT,12,"egg"))
	if not w.get("laying",{}).is_empty():sub.add_child(Ui.chip("産む あと%d晩"%maxi(0,int(w.laying.nights)),Ui.PINK,12))
	var s:=Ui.hbox(4);v.add_child(s)
	for k in Ui.STATS:s.add_child(Ui.label("%s%d"%[Ui.STAT[k].glyph,int(w.stats[k])],13,Ui.STAT[k].color))
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_LEFT:on_click.call())
	return row

## 女の詳しい中身（使い道の窓・施設の詳細）。
static func woman_detail(w: Dictionary,width: float=380) -> VBoxContainer:
	var v:=Ui.vbox(8)
	var head:=Ui.hbox(10);v.add_child(head)
	head.add_child(woman_icon(w,46))
	var hv:=Ui.vbox(2);head.add_child(hv)
	hv.add_child(Ui.title(woman_title(w),24))
	var sub:=Ui.hbox(6);hv.add_child(sub)
	sub.add_child(job_chip(str(w.job)));sub.add_child(Ui.stars(int(w.star),15))
	sub.add_child(Ui.chip("卵を産める数 残り %d"%int(w.eggs_left),Ui.PINK,13,"egg"))
	v.add_child(Ui.stage_track(int(w.stage),15))
	var info:=HFlowContainer.new();info.add_theme_constant_override("h_separation",8);v.add_child(info)
	var weak_txt: String=("弱点：%s"%Ui.STAT[str(w.weak)].house) if w.weak_known else "弱点：？（見回りで分かる）"
	info.add_child(Ui.chip(weak_txt,Ui.STAT[str(w.weak)].color if w.weak_known else Ui.FAINT,13,"eye"))
	var left: int=Captive.nights_left(w)
	if left>0:info.add_child(Ui.chip("次の段階まで %d 晩"%left,Ui.GOLD,13,"moon"))
	if str(w.use)=="press":info.add_child(Ui.chip("毎晩 精気 %d"%int(round(Captive.press_amount(w))),Ui.RES.essence.color,13,"drop"))
	v.add_child(Ui.label("能力（子の素質の土台）",14,Ui.DIM))
	v.add_child(stat_bars(w.stats,100.0,width-150))
	var cap_total:=0.0
	for k in Ui.STATS:cap_total+=float(w.shikomi[k])
	v.add_child(Ui.label("仕込み %d / %d（子の素質に足される）"%[int(cap_total),int(Captive.stage_cap(int(w.stage)))],14,Ui.DIM))
	var h: String=Captive.house_of(w)
	v.add_child(stat_bars(w.shikomi,60.0,width-150,Captive.shikomi_after(w,h) if h!="" else {}))
	if str(w.get("woman_id",""))!="":
		var d: Dictionary=G.db.women[w.woman_id]
		v.add_child(Ui.wrap_label("固有：%s ─ %s\n召喚陣の卵からまれに：%s"%[G.db.skill_name(str(d.unique)),str(G.db.skill(str(d.unique)).get("desc","")),G.db.species_name(str(d.species))],13,Ui.GOLD_HI,width))
	return v

# ───────── 魔物 ─────────
static func species_icon(id: String) -> String:
	return str(G.db.species.get(id,{}).get("icon","goblin"))

static func job_text(m: Dictionary) -> String:
	if Stats.ko(m):return "倒れている"
	var t: String=JOB_NAMES.get(str(m.job),"待機")
	var f: Dictionary=G.state.fac(int(m.get("fac",-1)))
	if not f.is_empty():t+="（%s）"%G.db.rooms[f.def].name
	return t

static func grade_chip(m: Dictionary,size: int=12) -> Control:
	var g: int=int(m.get("grade",-1))
	if g<0:return Ui.chip("苗床の子",Ui.DIM,size)
	return Ui.chip(GRADES[g],Ui.GRADE[g].color,size,"star")

## 魔物の一覧の1行。
static func monster_row(m: Dictionary,selected: bool,on_click: Callable,tag: String="") -> Control:
	var sd: Dictionary=G.db.species[str(m.species)]
	var row:=Ui.list_row(selected,Color(str(sd.tint)),10)
	var h:=Ui.hbox(10);row.add_child(h)
	h.add_child(monster_icon(m,34))
	var v:=Ui.vbox(2);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;h.add_child(v)
	var top:=Ui.hbox(6);v.add_child(top)
	top.add_child(Ui.label(str(m.name),17,Ui.TEXT,true))
	top.add_child(Ui.chip(str(sd.name),Color(str(sd.tint)),12))
	top.add_child(role_chip(str(m.species),11))
	if int(m.get("grade",-1))>=0:top.add_child(grade_chip(m,11))
	if tag!="":top.add_child(Ui.chip(tag,Ui.CRIMSON.lightened(0.35),11,"sword"))
	var sub:=Ui.hbox(6);v.add_child(sub)
	var mx: int=Stats.hp_max(m)
	var hm=Ui.meter(float(m.hp),float(mx),Ui.GOOD if not Stats.ko(m) else Ui.DANGER,90,9);hm.size_flags_vertical=Control.SIZE_SHRINK_CENTER;sub.add_child(hm)
	sub.add_child(Ui.label("%d/%d"%[int(m.hp),mx],12,Ui.DANGER if Stats.ko(m) else Ui.DIM))
	sub.add_child(Ui.chip(job_text(m),Ui.DANGER if Stats.ko(m) else (Ui.GOLD if str(m.job)!="none" else Ui.FAINT),12))
	var s:=Ui.hbox(4);v.add_child(s)
	for k in Ui.STATS:s.add_child(Ui.label("%s%d"%[Ui.STAT[k].glyph,int(m.stats[k])],13,Ui.STAT[k].color))
	s.add_child(Ui.label("　技%d"%Stats.passives(m).size(),13,Ui.DIM))
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_LEFT:on_click.call())
	return row

## スキルの行（名前・説明・効く能力）。
static func skill_line(id: String,width: float,color: Color=Ui.GOLD_HI,prefix: String="") -> Control:
	var s: Dictionary=G.db.skill(id)
	var v:=Ui.vbox(1)
	var h:=Ui.hbox(6);v.add_child(h)
	h.add_child(Ui.label(prefix+str(s.get("name",id)),15,color,true))
	for k in Sk.stats_used(id):h.add_child(Ui.chip(Ui.STAT[k].name,Ui.STAT[k].color,11))
	v.add_child(Ui.wrap_label(Sk.describe(id),13,Ui.DIM,width))
	return v

static func monster_detail(m: Dictionary,width: float=380) -> VBoxContainer:
	var v:=Ui.vbox(8)
	var sd: Dictionary=G.db.species[str(m.species)]
	var head:=Ui.hbox(10);v.add_child(head)
	head.add_child(monster_icon(m,48))
	var hv:=Ui.vbox(2);head.add_child(hv)
	hv.add_child(Ui.title(str(m.name),24))
	if str(m.get("kin",""))!="":hv.add_child(Ui.label(str(m.kin),14,Ui.DIM))
	var sub:=Ui.hbox(6);hv.add_child(sub)
	sub.add_child(Ui.chip(str(sd.name),Color(str(sd.tint)),13))
	sub.add_child(role_chip(str(m.species),13))
	sub.add_child(grade_chip(m,13))
	sub.add_child(Ui.chip("第%d世代"%int(m.generation),Ui.DIM,13))
	sub.add_child(Ui.chip("勝ち %d"%int(m.wins),Ui.DIM,13))
	var mx: int=Stats.hp_max(m)
	var hh:=Ui.hbox(8);v.add_child(hh)
	hh.add_child(Ui.label("体力",15,Ui.DIM,true))
	var hm=Ui.meter(float(m.hp),float(mx),Ui.GOOD if not Stats.ko(m) else Ui.DANGER,width-200,12);hm.size_flags_vertical=Control.SIZE_SHRINK_CENTER;hh.add_child(hm)
	hh.add_child(Ui.num("%d / %d"%[int(m.hp),mx],15,Ui.DANGER if Stats.ko(m) else Ui.TEXT))
	v.add_child(Ui.label(job_text(m),14,Ui.GOLD_HI))
	v.add_child(Ui.label("能力 / 素質（上限）",14,Ui.DIM))
	v.add_child(stat_bars(m.stats,100.0,width-170,{},m.apt))
	if str(m.get("mother_name",""))!="":v.add_child(Ui.label("母：%s（%s）"%[m.mother_name,G.db.jobs.get(str(m.get("mother_job","")),{}).get("name","")],13,Ui.DIM))
	v.add_child(Ui.section("アクティブ（押して撃つ）"))
	v.add_child(skill_line(str(sd.active),width))
	v.add_child(Ui.section("種族のパッシブ（能力で開く）"))
	for p in Stats.passive_table(m):
		var need: Array=[]
		for k in p.need:need.append("%s%d"%[Ui.STAT[k].name,int(p.need[k])])
		var col: Color=Ui.GOOD if p.open else (Ui.DIM if p.reachable else Ui.FAINT)
		var pre: String="◆ " if p.open else ("◇ %s　"%"・".join(need))
		v.add_child(skill_line(str(p.skill),width,col,pre))
		if not p.open and not p.reachable:v.add_child(Ui.label("　素質が足りず、この子では開かない",12,Ui.FAINT))
	v.add_child(Ui.section("継承のパッシブ（%d / %d）"%[m.inherited.size(),int(G.db.balance.inherit_max)]))
	if m.inherited.is_empty():v.add_child(Ui.label("なし",13,Ui.FAINT))
	for id in m.inherited:v.add_child(skill_line(str(id),width,Ui.PINK,"◆ "))
	return v
