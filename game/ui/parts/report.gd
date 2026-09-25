extends RefCounted
## 朝（企画書 7.3・12章）：卵が孵るのを1体ずつ明かす → 報告の一覧 → 名前付きの節目と結末。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Captive=preload("res://game/breed/captive.gd")
const Stats=preload("res://game/monsters/stats.gd")
const GROUPS:=[["chapter"],["hatch","egg"],["stage"],["grow","passive"],["income"],["warn"]]
const GROUP_NAMES:=["章","卵","心の段階","魔物の育ち","収入","注意"]
const GROUP_COLORS:=[Color("e2b24c"),Color("c4628c"),Color("c8b458"),Color("84ad6c"),Color("d8b050"),Color("cc9440")]
const GROUP_ICONS:=["crown","egg","heart","paw","drop","bolt"]
const SHELL:=[Color("938a84"),Color("5aa88a"),Color("76a2cc"),Color("e2b24c")]

## 朝の一連の流れ。終わったら on_done。
static func morning(screen,on_done: Callable) -> void:
	var st=G.state
	var kids: Array=[]
	for e in st.report:
		if e.kind=="hatch":kids.append(int(e.monster))
	var after_list:=func():milestones(screen,on_done)
	var after_births:=func():show_list(after_list)
	if not kids.is_empty():reveal(kids,after_births)
	else:after_births.call()

static func show_list(on_close: Callable) -> void:
	var st=G.state
	if st.report.is_empty():
		on_close.call();return
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,30);p.custom_minimum_size=Vector2(980,0)
	var v:=Ui.vbox(12);p.add_child(v)
	var th:=Ui.hbox(14);v.add_child(th)
	th.add_child(Ui.icon_disc("moon",56,Ui.GOLD))
	th.add_child(Ui.title("%d日目の朝"%st.day,36))
	v.add_child(Ui.flourish(700))
	var sc:=ScrollContainer.new();sc.custom_minimum_size=Vector2(920,480);sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;v.add_child(sc)
	var list:=Ui.vbox(10);list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sc.add_child(list)
	for gi in GROUPS.size():
		var items: Array=st.report.filter(func(e):return e.kind in GROUPS[gi])
		if items.is_empty():continue
		var head:=Ui.hbox(8);list.add_child(head)
		head.add_child(Icons.rect(GROUP_ICONS[gi],20,GROUP_COLORS[gi]));head.add_child(Ui.label(GROUP_NAMES[gi],19,GROUP_COLORS[gi],true))
		for e in items:
			list.add_child(Ui.wrap_label("・"+str(e.text),16,Ui.TEXT,880))
	var h:=Ui.hbox();h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var layer: Control
	var sb:=Ui.icon_button("play","昼の支度へ",func():
		G.main.close_overlay(layer)
		on_close.call(),21)
	Ui.primary_style(sb);sb.custom_minimum_size=Vector2(260,58);h.add_child(sb)
	layer=G.main.overlay(p,0.65)

# ───────── 孵化 ─────────
static func reveal(ids: Array,on_done: Callable) -> void:
	var queue: Array=ids.duplicate()
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,32);p.custom_minimum_size=Vector2(980,600)
	var v:=Ui.vbox(12);p.add_child(v)
	G.main.overlay(p,0.8)
	next_child(v,queue,on_done)

static func next_child(v: VBoxContainer,queue: Array,on_done: Callable) -> void:
	for c in v.get_children():c.queue_free()
	if queue.is_empty():
		G.main.close_overlay(null)
		on_done.call()
		return
	var m: Dictionary=G.state.monster(int(queue.pop_front()))
	if m.is_empty():next_child(v,queue,on_done);return
	var tree: SceneTree=v.get_tree()
	var sd: Dictionary=G.db.species[str(m.species)]
	var g: int=int(m.get("grade",-1))
	# 卵：ひびが入り、光の色で等級、姿（種族）の順に明かす
	var egg:=EggView.new();egg.custom_minimum_size=Vector2(916,200);egg.shell=SHELL[g] if g>=0 else Color("c4a888");v.add_child(egg)
	var head:=Ui.hbox(16);head.modulate.a=0.0;v.add_child(head)
	head.add_child(Ui.icon_disc(Cards.species_icon(str(m.species)),84,Color(str(sd.tint))))
	var hv:=Ui.vbox(4);hv.size_flags_vertical=Control.SIZE_SHRINK_CENTER;head.add_child(hv)
	var chips:=Ui.hbox(6);hv.add_child(chips)
	chips.add_child(Ui.chip("孵化",Ui.PINK,15,"egg"))
	if g>=0:chips.add_child(Ui.chip(Cards.GRADES[g],Ui.GRADE[g].color,15,"star"))
	hv.add_child(Ui.title(str(m.name),32))
	hv.add_child(Ui.label("%s　第%d世代"%[sd.name,int(m.generation)],19,Ui.DIM,true))
	var row:=Ui.hbox(40);row.alignment=BoxContainer.ALIGNMENT_CENTER;v.add_child(row)
	var cells: Array=[]
	for k in Ui.STATS:
		var cv:=Ui.vbox(2);row.add_child(cv)
		var ch:=Ui.hbox(4);ch.alignment=BoxContainer.ALIGNMENT_CENTER;cv.add_child(ch)
		ch.add_child(Icons.rect(str(Icons.STAT[k]),18,Ui.STAT[k].color));ch.add_child(Ui.label("%sの素質"%Ui.STAT[k].name,16,Ui.STAT[k].color,true))
		var l:=Ui.title("？",40,Color("4a3a40"));l.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;l.custom_minimum_size=Vector2(130,0);cv.add_child(l)
		cells.append([k,l])
	var note:=Ui.wrap_label("",16,Ui.TEXT,900);v.add_child(note)
	var h:=Ui.hbox(10);h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var skip:=[false]
	h.add_child(Ui.icon_button("arrow","飛ばす",func():
		skip[0]=true;queue.clear();G.main.close_overlay(null);on_done.call(),16))
	var nxt:=Ui.icon_button("play","次へ" if not queue.is_empty() else "報告へ",func():next_child(v,queue,on_done),20)
	Ui.primary_style(nxt);nxt.custom_minimum_size=Vector2(220,56);nxt.disabled=true;h.add_child(nxt)
	# ひび → 光 → 姿
	for i in 3:
		if skip[0] or not is_instance_valid(egg):return
		egg.cracks=i+1;egg.queue_redraw()
		G.main.sfx("click")
		await tree.create_timer(0.35).timeout
	if skip[0] or not is_instance_valid(egg):return
	egg.glow=Ui.GRADE[g].color if g>=0 else Color(str(m.get("tint","#ffffff")) if str(m.get("tint",""))!="" else "#ffffff")
	egg.open=true;egg.queue_redraw()
	G.main.sfx("capture")
	var tw:=head.create_tween();tw.tween_property(head,"modulate:a",1.0,0.4)
	await tree.create_timer(0.45).timeout
	for cell in cells:
		if skip[0] or not is_instance_valid(note):return
		cell[1].text=str(int(m.apt[cell[0]]));cell[1].add_theme_color_override("font_color",Ui.STAT[cell[0]].color.lightened(0.3))
		cell[1].pivot_offset=Vector2(65,25);cell[1].scale=Vector2(1.35,1.35)
		var tw3: Tween=cell[1].create_tween();tw3.tween_property(cell[1],"scale",Vector2.ONE,0.2).set_trans(Tween.TRANS_BACK)
		G.main.sfx("click")
		await tree.create_timer(0.22).timeout
	if skip[0] or not is_instance_valid(note):return
	var extra: Array=["孵ったときの能力は素質の%d%%。房の相手役と戦闘で素質まで伸びる。"%int(float(G.db.balance.hatch_ratio)*100)]
	extra.append("アクティブ：%s"%G.db.skill_name(str(sd.active)))
	if not m.inherited.is_empty():extra.append("継承のパッシブ：%s"%"・".join(m.inherited.map(func(id):return G.db.skill_name(str(id)))))
	var open: Array=Stats.open_passives(m)
	if not open.is_empty():extra.append("開いているパッシブ：%s"%"・".join(open.map(func(id):return G.db.skill_name(str(id)))))
	note.text="\n".join(extra)
	nxt.disabled=false

class EggView extends Control:
	var shell:=Color("c4a888")
	var cracks:=0
	var open:=false
	var glow:=Color.WHITE
	var t:=0.0
	func _process(delta: float) -> void:
		t+=delta;queue_redraw()
	func _draw() -> void:
		var c:=Vector2(size.x*0.5,size.y*0.55)
		var shake: float=sin(t*40.0)*2.0*float(cracks) if not open else 0.0
		c.x+=shake
		if open:
			for i in 6:draw_circle(c,90+i*14+sin(t*3)*4,Color(glow,0.08))
			draw_circle(c,70,Color(glow,0.5))
		var pts:=PackedVector2Array()
		for i in 40:
			var a: float=TAU*i/40.0
			var r: float=62.0*(1.0+0.18*cos(a))
			pts.append(c+Vector2(sin(a)*r*0.78,-cos(a)*r))
		if not open:
			draw_colored_polygon(pts,shell.darkened(0.15))
			draw_circle(c+Vector2(-18,-30),14,Color(1,1,1,0.12))
			for k in cracks:
				var y0: float=-40.0+k*28.0
				var line:=PackedVector2Array([c+Vector2(-30,y0),c+Vector2(-12,y0+10),c+Vector2(4,y0-6),c+Vector2(20,y0+8),c+Vector2(34,y0-2)])
				draw_polyline(line,Color(0,0,0,0.7),3)
		else:
			for i in 2:
				var off: float=-26.0 if i==0 else 26.0
				var half:=PackedVector2Array()
				for p in pts:
					if (p.x<c.x)==(i==0):half.append(p+Vector2(off,40))
				if half.size()>2:draw_colored_polygon(half,shell.darkened(0.25))

# ───────── 節目と結末 ─────────
static func milestones(screen,on_done: Callable) -> void:
	var st=G.state
	var list: Array=st.flags.get("milestones",[])
	if list.is_empty():
		on_done.call();return
	var item: Dictionary=list.pop_front()
	st.flags.milestones=list
	var w: Dictionary=st.woman(int(item.woman))
	var cont:=func():milestones(screen,on_done)
	if w.is_empty():cont.call();return
	if screen!=null and screen.has_method("focus_woman"):screen.focus_woman(int(w.uid))
	if bool(item.get("ending",false)):
		ending(w,cont);return
	var p:=Ui.panel(Color(Ui.PANEL,0.96),Ui.LINE,24);p.custom_minimum_size=Vector2(1000,0)
	var v:=Ui.vbox(10);p.add_child(v)
	var stage: int=clampi(int(item.stage),0,4)
	var sh:=Ui.hbox(12);v.add_child(sh)
	sh.add_child(Ui.badge(str(w.name).substr(0,1),Color(str(w.get("hair","#a06040"))),46))
	sh.add_child(Ui.title("節目　%sが「%s」に"%[w.name,Ui.STAGES[stage]],30,Ui.STAGE_COLORS[stage].lightened(0.2)))
	var txt: String=str(G.db.texts.get("milestone",{}).get(str(stage),"%sに変化があった。"))
	v.add_child(Ui.wrap_label(txt%w.name+"（本文は作者が用意する）",18,Ui.TEXT,940))
	var layer: Control
	var eb:=Ui.icon_button("eye","見届けた",func():G.main.close_overlay(layer);cont.call(),20);Ui.primary_style(eb)
	var h:=Ui.hbox();h.alignment=BoxContainer.ALIGNMENT_END;h.add_child(eb);v.add_child(h)
	layer=G.main.overlay(p,0.35)

static func ending(w: Dictionary,cont: Callable) -> void:
	var st=G.state
	var fall: String=Captive.top_stat(w)
	st.records.endings.append({"woman":str(w.get("woman_id","")),"fall":fall,"day":st.day})
	var p:=Ui.panel(Color(Ui.PANEL,0.96),Ui.LINE,24);p.custom_minimum_size=Vector2(1100,0)
	var v:=Ui.vbox(10);p.add_child(v)
	var eh:=Ui.hbox(12);v.add_child(eh)
	eh.add_child(Ui.icon_disc("crown",46,Ui.STAT[fall].color))
	eh.add_child(Ui.title("結末　%s ─ %sに寄せて堕ちた"%[w.name,Ui.STAT[fall].name],30,Ui.STAT[fall].color.lightened(0.2)))
	v.add_child(Ui.wrap_label("%sは心の底まで染まりきった。（結末の本文は作者が用意する。一番高い仕込みごとに分かれる）"%w.name,18,Ui.TEXT,1050))
	var layer: Control
	var eb:=Ui.icon_button("eye","見届けた",func():G.main.close_overlay(layer);cont.call(),20);Ui.primary_style(eb)
	var h:=Ui.hbox();h.alignment=BoxContainer.ALIGNMENT_END;h.add_child(eb);v.add_child(h)
	layer=G.main.overlay(p,0.35)
