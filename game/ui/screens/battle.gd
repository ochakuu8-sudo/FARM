extends Control
## 戦闘（企画書 4.3・設計書 第4章）。TABS型のリアルタイム：配置したら、移動・通常攻撃・スキルはすべて自動で進む。
## 計算（sim.gd）を TICK 秒ずつ進め、役者はその位置へ滑らかに寄せて描く。速さ×1・×2・×4と、止める（Space）。
## 勝てば一行を全員獲得（捕らえる瞬間は性的でない「縛る」演出）。負ければ使ったスタミナと減った体力を失う。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const BattleView=preload("res://game/map/battle_view.gd")
const Help=preload("res://game/ui/parts/help.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Look=preload("res://game/map/look.gd")
const Sites=preload("res://game/world/sites.gd")
const Setup=preload("res://game/battle/setup.gd")
const Outcome=preload("res://game/battle/outcome.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Sk=preload("res://game/battle/skills.gd")
const Day=preload("res://game/core/day.gd")
const SPEEDS:=[1.0,2.0,4.0]
## 1フレームで進める刻みの上限（重いときに追いつこうとして固まらないように）。
const MAX_STEPS:=24
## 攻撃・術・被弾の見せ方を保つ秒。
const ACTION_HOLD:=0.6
const STATUS_NAMES:={"haste":"速まった","bind":"縛られた","slow":"遅い","weak":"力が抜けた","stun":"休み","taunt":"挑発","guard":"かばう","last_stand":"誓い"}

var view
var sim
var site: Dictionary={}
var k:=0
var fight: Dictionary={}
var acc:=0.0
var speed_i:=0
var paused:=false
var finished:=false
var log_i:=0                      # 画面に出した記録の数
var focusing:=false               # 「狙え」の的を選んでいる
var order_label: Label
var order_buttons: Array=[]
var hold: Dictionary={}           # 駒の鍵 → 攻撃などの見せ方を保つ残り秒
var cards_box: HBoxContainer
var cards: Dictionary={}          # uid → {panel, hp, charge, button, state}
var log_box: VBoxContainer
var head_label: Label
var speed_buttons: Array=[]
var pause_button: Button
var hint: Label

func open(p: Dictionary) -> void:
	site=Sites.find(str(p.get("site","")))
	k=int(p.get("k",0))
	if site.is_empty():G.main.goto("ranch",{});return
	var st=G.state
	fight=Setup.fight(site,k)
	sim=Setup.start(site,k,st.party)
	st.world.chain={"site":str(site.id),"k":k}
	speed_i=clampi(int(G.settings.get("battle_speed",1))-1,0,2)
	var layer:=CanvasLayer.new();layer.layer=-5;add_child(layer)
	view=BattleView.new();layer.add_child(view)
	view.set_board(site.board)
	view.seamless=true
	view.screen_center=Vector2(820,470)
	view.zoom=2.3*10.8/float(str(site.board[0]).length()+1)
	for u in sim.units:
		var look: Dictionary=Look.minion() if u.minion else (Look.monster(st.monster(int(u.ref))) if u.side=="m" else Look.member(fight.party[int(u.ref)]))
		view.set_piece(key_of(u),{"look":look,"cell":cell_pos(u),"follow":true,"face":2 if u.side=="m" else 6,"action":"idle","side":u.side,"hp":int(u.hp),"max":int(u.max),"name":str(u.name),"named":str(u.get("named","")),"alive":u.alive,"charge":float(u.charge) if u.side=="m" else null})
		if u.side=="w" or u.minion:view.pieces[key_of(u)].erase("charge")
	build_hud()
	refresh_units()
	Help.first("battle")

## 計算の位置（マスの中心が +0.5）を、駒の座標（マスの左上が 0）へ。
static func cell_pos(u: Dictionary) -> Vector2:
	return (u.pos as Vector2)-Vector2(0.5,0.5)

func close() -> void:
	if view!=null:view.release_all()
	G.anim.detach()

func key_of(u: Dictionary) -> String:
	if u.get("minion",false):return "n%d"%int(u.id)
	return ("m%d" if u.side=="m" else "w%d")%int(u.ref)

# ───────── 画面の部品 ─────────
func build_hud() -> void:
	var top:=Ui.panel(Color(Ui.PANEL,0.93),Ui.LINE,12);top.position=Vector2(360,14);top.custom_minimum_size=Vector2(1200,0);add_child(top)
	var h:=Ui.hbox(10);top.add_child(h)
	head_label=Ui.label("",18,Ui.TEXT,true);head_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(head_label)
	for i in SPEEDS.size():
		var b:=Ui.button(["×1","×2","×4"][i],func():speed_i=i;paused=false;refresh_head(),15)
		speed_buttons.append(b);h.add_child(b)
	pause_button=Ui.button("止める",func():paused=not paused;refresh_head(),15);h.add_child(pause_button)
	var lp:=Ui.placed_panel(self,Rect2(1530,110,376,640),12)
	var lv:=Ui.vbox(6);lp.add_child(lv)
	lv.add_child(Ui.label("記録",16,Ui.GOLD_HI,true))
	var holder:=VBoxContainer.new();holder.custom_minimum_size=Vector2(350,580);lv.add_child(holder)
	log_box=Ui.scroll_box(holder,2)
	var bottom:=Ui.panel(Color(Ui.PANEL,0.95),Ui.LINE,12);bottom.position=Vector2(14,846);bottom.custom_minimum_size=Vector2(1500,220);add_child(bottom)
	var bv:=Ui.vbox(6);bottom.add_child(bv)
	hint=Ui.label("",15,Ui.DIM);bv.add_child(hint)
	cards_box=Ui.hbox(10);bv.add_child(cards_box)
	var i:=0
	for u in sim.units:
		if u.side!="m" or u.minion:continue
		i+=1
		cards_box.add_child(make_card(u,i))
	# 号令
	var ob:=Ui.vbox(6);cards_box.add_child(ob)
	ob.add_child(Ui.label("号令",15,Ui.GOLD_HI,true))
	order_label=Ui.label("",13,Ui.DIM);ob.add_child(order_label)
	var fb:=Ui.icon_button("target","狙え（女を押す）",func():start_focus(),15);ob.add_child(fb)
	var rb:=Ui.icon_button("bolt","押し込め",func():give_order("rally",-1),15);ob.add_child(rb)
	order_buttons=[fb,rb]
	refresh_head()

func make_card(u: Dictionary,index: int) -> Control:
	var st=G.state
	var m: Dictionary=st.monster(int(u.ref))
	var sd: Dictionary=G.db.species[str(m.species)]
	var p:=PanelContainer.new();p.add_theme_stylebox_override("panel",Ui.ornate(Color("1e1519"),Ui.GOLD.darkened(0.3),10,8));p.custom_minimum_size=Vector2(362,0)
	var v:=Ui.vbox(4);p.add_child(v)
	var h:=Ui.hbox(8);v.add_child(h)
	h.add_child(Ui.icon_disc(Cards.species_icon(str(m.species)),34,Color(str(sd.tint))))
	var hv:=Ui.vbox(0);h.add_child(hv)
	hv.add_child(Ui.label("%d　%s"%[index,m.name],16,Ui.TEXT,true))
	hv.add_child(Ui.label("%s〔%s〕"%[str(sd.name),Cards.role_of(str(m.species))],12,Ui.DIM))
	var hp=Ui.meter(float(u.hp),float(u.max),Ui.GOOD,330,9);v.add_child(hp)
	var ch=Ui.meter(float(u.charge),float(u.full),Ui.GOLD,330,7);v.add_child(ch)
	var uid: int=int(u.ref)
	var sl:=Ui.label("",14,Ui.DIM);sl.tooltip_text=Sk.describe(str(u.skill));sl.mouse_filter=Control.MOUSE_FILTER_PASS
	v.add_child(sl)
	cards[uid]={"panel":p,"hp":hp,"charge":ch,"skill":sl,"flash":0.0}
	return p

func refresh_head() -> void:
	if sim==null:return
	head_label.text="%s%s　%d秒%s"%[str(site.name),"　%d / %d戦目"%[k+1,site.chain.size()] if site.chain.size()>1 else "",int(sim.t),"　（止めている）" if paused else ""]
	for i in speed_buttons.size():
		if i==speed_i and not paused:Ui.color_style(speed_buttons[i],Ui.CRIMSON)
		else:
			for s in ["normal","hover","pressed","disabled"]:speed_buttons[i].remove_theme_stylebox_override(s)
	pause_button.text="進める" if paused else "止める"
	if focusing:
		hint.text="狙わせる女を押す（右クリックでやめる）"
		hint.add_theme_color_override("font_color",Ui.GOLD_HI)
	else:
		hint.text="移動・攻撃・スキルは自動。号令は1戦に%d回：「狙え」で全員に1人を狙わせ、「押し込め」で全員を速める。Space で止める、Q / E で視点を回す。"%int(G.db.balance.get("orders",{}).get("count",0))
		hint.add_theme_color_override("font_color",Ui.DIM)
	if order_label!=null:
		order_label.text="残り %d 回"%int(sim.orders_left)
		for b in order_buttons:b.disabled=int(sim.orders_left)<=0 or finished

## 駒と札を計算の今の状態に合わせる（毎フレーム）。
func refresh_units(delta: float=0.0) -> void:
	for u in sim.units:
		var key: String=key_of(u)
		if not view.pieces.has(key):continue
		var p: Dictionary=view.pieces[key]
		p.cell=cell_pos(u);p.hp=int(u.hp);p.max=int(u.max);p.alive=u.alive
		p.walking=bool(u.moving) and u.alive
		p.hidden=float(u.status.hidden)>0 and u.alive
		if u.alive and (u.face as Vector2).length()>0.01:p.face=BattleView.dir_of(u.face)
		hold[key]=maxf(0.0,float(hold.get(key,0.0))-delta)
		var base:="idle"
		if not u.alive:base="defeated"
		elif float(u.status.bind)>0:base="bound"
		elif float(u.status.stun)>0:base="down"
		if base!="idle" or float(hold[key])<=0:p.action=base
		if u.side=="m" and not u.minion:
			p.charge=float(u.charge)/maxf(1.0,float(u.full))*100.0;p.ready=sim.ready(u)
			var c: Dictionary=cards.get(int(u.ref),{})
			if c.is_empty():continue
			c.hp.value=float(u.hp);c.hp.maximum=float(u.max);c.hp.queue_redraw()
			c.charge.value=float(u.charge);c.charge.queue_redraw()
			c.flash=maxf(0.0,float(c.flash)-delta)
			var sname: String=G.db.skill_name(str(u.skill))
			var col: Color=Ui.GOLD.darkened(0.3)
			if not u.alive:
				col=Ui.DANGER.darkened(0.3);c.panel.modulate.a=0.5;c.skill.text=sname
			elif float(c.flash)>0:
				col=Ui.GOLD_HI;c.skill.text="★ %s を撃った"%sname;c.skill.add_theme_color_override("font_color",Ui.GOLD_HI)
			else:
				c.skill.text="%s（溜まると自動）"%sname;c.skill.add_theme_color_override("font_color",Ui.DIM)
			c.panel.add_theme_stylebox_override("panel",Ui.ornate(Color("2a1c20") if float(c.flash)>0 else Color("1e1519"),col,10,8))

# ───────── 進める ─────────
func _process(delta: float) -> void:
	if sim==null or finished:return
	var before: int=int(sim.t)
	if not paused and not G.main.has_overlay():
		acc+=delta*float(SPEEDS[speed_i])
		var n:=0
		while acc>=sim.TICK and n<MAX_STEPS and not sim.done:
			acc-=sim.TICK;n+=1
			sim.step()
			show_events()
		if n>=MAX_STEPS:acc=0.0
	refresh_units(delta)
	view.shots=sim.projectiles.map(func(p):return {"pos":(p.pos as Vector2)-Vector2(0.5,0.5),"magic":bool(p.magic),"side":str(p.side)})
	if int(sim.t)!=before:refresh_head()
	if sim.done and not finished:refresh_head();finish()

func show_events() -> void:
	for e in sim.events:
		var u: Dictionary=sim.unit(int(e.get("u",-1)))
		var t: Dictionary=sim.unit(int(e.get("t",-1)))
		match str(e.k):
			"order":
				if str(e.kind)=="focus" and not t.is_empty():view.flash(cell_pos(t),"狙え！",Ui.GOLD_HI,true)
				else:
					for m in sim.alive("m"):view.flash(cell_pos(m),"押し込め！",Ui.GOLD_HI)
				G.main.sfx("confirm")
			"knock":
				if not t.is_empty() and view.pieces.has(key_of(t)):view.pieces[key_of(t)].flash_t=0.25
			"attack":
				if not u.is_empty() and view.pieces.has(key_of(u)):
					view.pieces[key_of(u)].action="attack";hold[key_of(u)]=ACTION_HOLD
			"hit":
				if not t.is_empty():
					view.flash(cell_pos(t),"-%d"%int(e.dmg),Ui.DANGER if t.side=="m" else Color("f0e0c0"))
					if view.pieces.has(key_of(t)):view.pieces[key_of(t)].flash_t=0.18
					if view.pieces.has(key_of(t)) and t.alive and float(hold.get(key_of(t),0.0))<=0:
						view.pieces[key_of(t)].action="hit";hold[key_of(t)]=0.35
			"cast":
				if not u.is_empty():
					var a: Dictionary=e.area
					view.flash_shape(str(a.shape),(a.center as Vector2),(a.from as Vector2),float(a.r),Color("e2b24c") if u.side=="m" else Color("c05060"))
					view.flash(cell_pos(u),str(e.skill),Ui.GOLD_HI if u.side=="m" else Ui.PINK,true)
					if view.pieces.has(key_of(u)):view.pieces[key_of(u)].action="cast";hold[key_of(u)]=ACTION_HOLD
					if u.side=="m" and cards.has(int(u.ref)):cards[int(u.ref)].flash=1.2
					G.main.sfx("cue")
			"heal":
				if not t.is_empty():view.flash(cell_pos(t),"+%d"%int(e.amt),Ui.GOOD)
			"down":
				if not t.is_empty():
					view.flash(cell_pos(t),"倒れた",Ui.DANGER if t.side=="m" else Ui.PINK,true)
					G.main.sfx("hit")
			"status":
				if not t.is_empty() and STATUS_NAMES.has(str(e.s)) and str(e.s)!="last_stand":view.flash(cell_pos(t)+Vector2(0,-0.3),STATUS_NAMES[str(e.s)],Ui.PURPLE)
			"stand":if not t.is_empty():view.flash(cell_pos(t),"踏みとどまった",Ui.GOLD_HI,true)
			"evade":if not t.is_empty():view.flash(cell_pos(t),"外れた",Ui.DIM)
			"block":if not t.is_empty():view.flash(cell_pos(t),"防いだ",Ui.INFO)
			"tear":if not u.is_empty():view.flash(cell_pos(u),"引きちぎった",Ui.DANGER,true)
			"unbind":if not t.is_empty():view.flash(cell_pos(t),"解かれた",Ui.GOLD)
			"whiff":if not u.is_empty():view.flash(cell_pos(u),"空振り",Ui.FAINT)
	while log_i<sim.logs.size():
		var l: Dictionary=sim.logs[log_i];log_i+=1
		add_log("%d秒　%s"%[int(l.time),str(l.text)],Ui.GOOD if str(l.side)=="m" else (Ui.PINK if str(l.side)=="w" else Ui.GOLD_HI))

func add_log(text: String,color: Color) -> void:
	var l:=Ui.wrap_label(text,13,color,340);log_box.add_child(l)
	while log_box.get_child_count()>60:log_box.get_child(0).free()
	await get_tree().process_frame
	var sc: ScrollContainer=log_box.get_parent().get_parent()
	if is_instance_valid(sc):sc.scroll_vertical=int(sc.get_v_scroll_bar().max_value)

# ───────── 終わり ─────────
func finish() -> void:
	finished=true
	view.shots=[]
	var res: Dictionary=sim.result()
	var out: Dictionary=Outcome.apply(site,k,res,fight)
	refresh_units()
	if res.won:
		G.main.sfx("capture")
		capture_show()
		await get_tree().create_timer(2.4).timeout
	else:
		G.main.sfx("error")
		await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():return
	if out.victory:
		G.main.notice("勇者パーティを捕らえた","父を討った勇者たちは、魔物の群れに組み伏せられた。","見届ける",func():G.main.goto("ending",{}))
		return
	result_panel(res,out)

## 倒れた女を、近くの魔物が縛る（性的でない場面。割り当てがなければ縛られた姿勢だけ）。
func capture_show() -> void:
	var shown:=0
	for w in sim.units:
		if w.side!="w" or w.alive:continue
		var wk: String=key_of(w)
		if view.pieces.has(wk):view.pieces[wk].action="bound"
		if shown>=3:continue
		var near: Dictionary={}
		for m in sim.alive("m"):
			if near.is_empty() or sim.dist(m,w)<sim.dist(near,w):near=m
		if near.is_empty():continue
		var a: String=view.actors.get(wk,"");var b: String=view.actors.get(key_of(near),"")
		if a=="" or b=="":continue
		var ev: Dictionary={"kind":"battle.capture","a":a,"b":b,"target_definition_id":str(fight.party[int(w.ref)].get("named","")),"target_tags":[str(w.kind)],"source_definition_id":str(near.kind),"source_tags":["monster"]}
		var h: int=G.anim.present(ev,view.project(w.pos),true)
		if h>=0:
			G.anim.view(h,view.dir*1,NAN,view.pitch_deg*0.7,view.PPU*view.HEIGHT)
			view.pieces.erase(key_of(near))
			shown+=1
		view.flash(cell_pos(w),"捕らえた",Ui.PINK,true)

func result_panel(res: Dictionary,out: Dictionary) -> void:
	var st=G.state
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,30);p.custom_minimum_size=Vector2(1100,0)
	var v:=Ui.vbox(12);p.add_child(v)
	var th:=Ui.hbox(14);v.add_child(th)
	th.add_child(Ui.icon_disc("crown" if res.won else "skull",56,Ui.GOLD if res.won else Ui.DANGER))
	th.add_child(Ui.title("勝ち" if res.won else "負け",40,Ui.GOLD_HI if res.won else Ui.DANGER.lightened(0.2)))
	th.add_child(Ui.label("%d秒"%int(round(float(res.secs))),18,Ui.DIM))
	v.add_child(Ui.flourish(800))
	if res.won:
		v.add_child(Ui.label("獲得した女 %d人　金 +%d"%[out.captured.size(),int(out.money)],20,Ui.TEXT,true))
		if int(out.sold)>0:v.add_child(Ui.label("牢が満杯なので %d人をその場で売り払った（+%d）。牢を広げると全員連れ帰れる。"%[int(out.sold),int(out.sold_money)],15,Ui.GOLD))
		var fl:=HFlowContainer.new();fl.add_theme_constant_override("h_separation",8);fl.add_theme_constant_override("v_separation",8);v.add_child(fl)
		for u in out.captured:
			var w: Dictionary=st.woman(int(u))
			var row: Control=Cards.woman_row(w,false,func():pass)
			row.custom_minimum_size=Vector2(520,0)
			fl.add_child(row)
		for o in out.opened:
			var m: Dictionary=st.monster(int(o.uid))
			v.add_child(Ui.label("%sが「%s」を覚えた"%[m.name,"・".join(o.skills.map(func(id):return G.db.skill_name(str(id))))],16,Ui.GOLD_HI))
		if out.chapter_up:v.add_child(Ui.label("地方を落とした。次の地方が開いた。",18,Ui.GOLD_HI,true))
	else:
		v.add_child(Ui.wrap_label("使ったスタミナと、減った体力は戻らない。倒れた魔物は牧場で回復させる（すぐ全快は高い）。",16,Ui.DIM,1000))
	v.add_child(Ui.section("魔物"))
	var mh:=Ui.hbox(12);v.add_child(mh)
	for uid in res.hp:
		var m2: Dictionary=st.monster(int(uid))
		if m2.is_empty():continue
		var mv:=Ui.vbox(2);mh.add_child(mv)
		mv.add_child(Ui.label(str(m2.name),15,Ui.TEXT,true))
		var mm=Ui.meter(float(m2.hp),float(Stats.hp_max(m2)),Ui.GOOD if int(m2.hp)>0 else Ui.DANGER,220,10);mv.add_child(mm)
		mv.add_child(Ui.label("%d / %d%s"%[int(m2.hp),Stats.hp_max(m2),"　倒れた" if int(m2.hp)<=0 else ""],13,Ui.DANGER if int(m2.hp)<=0 else Ui.DIM))
	var h:=Ui.hbox(12);h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var layer: Control
	var alive: int=res.hp.values().filter(func(x):return int(x)>0).size()
	var more: bool=res.won and k+1<site.chain.size()
	if more:
		var cost: int=Sites.cost_of(site,k+1)
		var nb:=Ui.icon_button("sword","次の戦闘へ（スタミナ %d）"%cost,func():
			G.main.close_overlay(layer);G.main.goto("prep",{"site":str(site.id),"k":k+1}),19)
		nb.disabled=int(st.stamina.now)<cost or alive==0 or Day.sortie_block()!=""
		if Day.sortie_block()!="":nb.tooltip_text=Day.sortie_block()
		Ui.primary_style(nb);h.add_child(nb)
	var wb:=Ui.icon_button("map","大陸の地図へ",func():
		st.world.chain={};G.main.close_overlay(layer);G.main.goto("world",{}),18)
	wb.disabled=Day.sortie_block()!=""
	h.add_child(wb)
	var rb:=Ui.icon_button("castle","牧場へ帰る",func():
		st.world.chain={};G.main.close_overlay(layer);G.main.goto("ranch",{}),19)
	if not more:Ui.primary_style(rb)
	h.add_child(rb)
	layer=G.main.overlay(p,0.55)

# ───────── 号令 ─────────
func start_focus() -> void:
	if finished or int(sim.orders_left)<=0:return
	focusing=true;refresh_head()

func give_order(kind: String,target: int) -> void:
	if sim.order(kind,target):add_log("%d秒　号令：%s"%[int(sim.t),"狙え" if kind=="focus" else "押し込め"],Ui.GOLD_HI)
	focusing=false;refresh_head()

# ───────── 入力 ─────────
func _unhandled_input(e: InputEvent) -> void:
	if finished:return
	if e is InputEventMouseMotion:
		view.hover_cell=view.cell_under(e.position)
	elif e is InputEventMouseButton and e.pressed:
		if focusing and e.button_index==MOUSE_BUTTON_LEFT:
			var key: String=view.piece_under(e.position)
			if key.begins_with("w"):
				for w in sim.alive("w"):
					if key_of(w)==key:give_order("focus",int(w.id));break
			return
		if focusing and e.button_index==MOUSE_BUTTON_RIGHT:focusing=false;refresh_head();return
		if e.button_index==MOUSE_BUTTON_WHEEL_UP:view.zoom=minf(3.4,view.zoom*1.08)
		elif e.button_index==MOUSE_BUTTON_WHEEL_DOWN:view.zoom=maxf(1.1,view.zoom/1.08)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:paused=not paused;refresh_head()
			KEY_F:start_focus()
			KEY_R:give_order("rally",-1)
			KEY_ESCAPE:focusing=false;refresh_head()
			KEY_Q:view.rotate_view(-1)
			KEY_E:view.rotate_view(1)
