extends Control
## 編成と配置（企画書 4.3・設計書 12章 E2）。魔物を4体まで選び、左の2列に置く。一行の並びと能力を見て、戦闘を始める。
## 編成と配置は覚えておき、次の出撃でもそのまま使う。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const BattleView=preload("res://game/map/battle_view.gd")
const TopBar=preload("res://game/ui/parts/top_bar.gd")
const Help=preload("res://game/ui/parts/help.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Look=preload("res://game/map/look.gd")
const Sites=preload("res://game/world/sites.gd")
const Setup=preload("res://game/battle/setup.gd")
const Stats=preload("res://game/monsters/stats.gd")
const LEFT:=Rect2(14,76,470,876)
const RIGHT:=Rect2(1450,76,456,876)

var view
var site: Dictionary={}
var k:=0
var fight: Dictionary={}
var sel_uid:=-1
var enemy_sel:=-1
var roster: VBoxContainer
var info: VBoxContainer
var start_button: Button
var count_label: Label
var home: Array=[]

func open(p: Dictionary) -> void:
	site=Sites.find(str(p.get("site","")))
	k=int(p.get("k",0))
	if site.is_empty():G.main.goto("world",{});return
	fight=Setup.fight(site,k)
	home=Setup.home_cells(site.board)
	var layer:=CanvasLayer.new();layer.layer=-5;add_child(layer)
	view=BattleView.new();layer.add_child(view)
	view.set_board(site.board)
	view.screen_center=Vector2(967,540)
	# 左右の欄の間（約970px）に14マスが収まる寄り
	view.zoom=2.3*8.5/float(str(site.board[0]).length()+1)
	var top:=TopBar.new();top.help_topic="prep";add_child(top)
	var lp:=Ui.placed_panel(self,LEFT,14)
	var lv:=Ui.vbox(8);lp.add_child(lv)
	var lh:=Ui.hbox(8);lv.add_child(lh)
	lh.add_child(Ui.icon_disc("group",32,Ui.GOLD));lh.add_child(Ui.title("編成",22))
	lh.add_child(Ui.spacer())
	count_label=Ui.label("",16,Ui.TEXT,true);lh.add_child(count_label)
	var holder:=VBoxContainer.new();holder.custom_minimum_size=Vector2(LEFT.size.x-28,LEFT.size.y-80);lv.add_child(holder)
	roster=Ui.scroll_box(holder,6)
	var rp:=Ui.placed_panel(self,RIGHT,16)
	var holder2:=VBoxContainer.new();holder2.custom_minimum_size=RIGHT.size-Vector2(32,32);rp.add_child(holder2)
	info=Ui.scroll_box(holder2,8)
	var bottom:=Ui.hbox(12);bottom.position=Vector2(500,968);bottom.custom_minimum_size=Vector2(934,96);add_child(bottom)
	var back:=Ui.icon_button("back","大陸の地図へ" if k==0 else "連戦をやめて牧場へ",back_out,18);back.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bottom.add_child(back)
	bottom.add_child(Ui.icon_button("group","強い順に並べる",auto_fill,16))
	bottom.add_child(Ui.spacer())
	start_button=Ui.icon_button("sword","戦闘開始",start,22);Ui.primary_style(start_button);start_button.custom_minimum_size=Vector2(300,64);start_button.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bottom.add_child(start_button)
	var head:=Ui.hbox(10);head.position=Vector2(500,80);add_child(head)
	head.add_child(Ui.title("%s%s"%[str(site.name),"　%d / %d戦目"%[k+1,site.chain.size()] if site.chain.size()>1 else ""],28))
	for m in fight.party:
		var key: String="w%d"%fight.party.find(m)
		view.set_piece(key,{"look":Look.member(m),"cell":m.pos,"face":6,"action":"idle","side":"w","hp":1,"max":1,"name":str(m.name),"named":str(m.get("named","")),"alive":true})
	# 置き場の印
	for c in home:view.marks[c]=Color("7299bf")
	if G.state.party.is_empty():auto_fill()
	refresh()
	Help.first("prep")

func close() -> void:
	if view!=null:view.release_all()
	G.anim.detach()

func party() -> Array:
	var st=G.state
	return st.party.filter(func(u):return not st.monster(int(u)).is_empty() and Stats.can_fight(st.monster(int(u))))

func refresh() -> void:
	var st=G.state
	st.party=party()
	var team: Array=Setup.team(st.party,site.board)
	for t in team:st.placement[str(int(t.m.uid))]=[t.pos.x,t.pos.y]
	for key in view.pieces.keys():
		if str(key).begins_with("m") or str(key).begins_with("n"):view.remove_piece(key)
	var mins: Array=Setup.minions(site.board,team)
	for i in mins.size():
		view.set_piece("n%d"%i,{"look":Look.minion(),"cell":mins[i].pos,"face":2,"action":"idle","side":"m","hp":1,"max":1,"name":"雑兵","alive":true})
	for t in team:
		var m: Dictionary=t.m
		view.set_piece("m%d"%int(m.uid),{"look":Look.monster(m),"cell":t.pos,"face":2,"action":"idle","side":"m","hp":int(m.hp),"max":Stats.hp_max(m),"name":str(m.name),"alive":true})
		view.pieces["m%d"%int(m.uid)].cell=t.pos
	view.selected_key="m%d"%sel_uid if sel_uid in st.party else ""
	var n: int=st.party.size()
	count_label.text="出撃 %d / %d"%[n,int(G.db.balance.party_size)]
	start_button.disabled=n==0 or int(st.stamina.now)<Sites.cost_of(site,k)
	start_button.text="戦闘開始（スタミナ %d）"%Sites.cost_of(site,k)
	fill_roster()
	fill_info()

func fill_roster() -> void:
	var st=G.state
	for c in roster.get_children():c.queue_free()
	roster.add_child(Ui.wrap_label("魔物を押して選び、盤の青いマスを押して置く。置いた魔物をもう一度押すと外す。雑兵%d体は、空いている前の列に自動で並ぶ。"%int(G.db.balance.get("minions",{}).get("count",0)),13,Ui.DIM,430))
	var ms: Array=st.monsters.duplicate()
	ms.sort_custom(func(a,b):return [0 if int(a.uid) in st.party else 1,-Stats.power(a),int(a.uid)]<[0 if int(b.uid) in st.party else 1,-Stats.power(b),int(b.uid)])
	for m in ms:
		var u: int=int(m.uid)
		var row: Control=Cards.monster_row(m,u==sel_uid,func():pick(u),"出撃" if u in st.party else "")
		if not Stats.can_fight(m):row.modulate.a=0.45;row.tooltip_text="倒れている（牧場で回復させる）"
		roster.add_child(row)

func fill_info() -> void:
	var st=G.state
	for c in info.get_children():c.queue_free()
	if enemy_sel>=0 and enemy_sel<fight.party.size():
		var m: Dictionary=fight.party[enemy_sel]
		var jd: Dictionary=G.db.jobs[str(m.job)]
		info.add_child(Ui.title(str(m.name),26))
		var h:=Ui.hbox(6);info.add_child(h)
		h.add_child(Cards.job_chip(str(m.job)));h.add_child(Ui.stars(int(m.star),15))
		info.add_child(Cards.stat_bars(m.stats,100.0,260))
		var sk: String=str(G.db.women[str(m.named)].unique) if str(m.get("named",""))!="" else str(jd.get("skill",""))
		info.add_child(Ui.section("動き方"))
		info.add_child(Ui.wrap_label({"basic":"近い魔物を殴る。","guard":"仲間の隣に寄り、「かばう」で仲間への攻撃を引き受ける。","healer":"仲間を癒やし、縛られた仲間を解きに行く。","flank":"一番後ろの魔物を狙って回り込む。縛りが半分で解ける。","caster":"離れた所から、魔物が密な所へ術を撃つ。","bruiser":"近い魔物を強く殴る。縛られても少しで引きちぎる。"}.get(str(jd.ai),""),14,Ui.TEXT,410))
		if sk!="":info.add_child(Cards.skill_line(sk,410))
		info.add_child(Ui.text_button("魔物の側を見る",func():enemy_sel=-1;fill_info(),15))
		return
	var m0: Dictionary=st.monster(sel_uid)
	if not m0.is_empty():
		info.add_child(Cards.monster_detail(m0,410))
		return
	# こちらの役割のそろい方
	var roles: Dictionary={}
	for u in st.party:
		var pm: Dictionary=st.monster(int(u))
		if not pm.is_empty():roles[Cards.role_of(str(pm.species))]=int(roles.get(Cards.role_of(str(pm.species)),0))+1
	var rh:=Ui.hbox(4);info.add_child(rh)
	rh.add_child(Ui.label("出撃の役割",14,Ui.DIM))
	for r in roles:rh.add_child(Ui.chip("%s×%d"%[r,int(roles[r])] if int(roles[r])>1 else str(r),Color(str(Cards.ROLE_COLORS.get(r,"888888"))),12))
	if roles.is_empty():rh.add_child(Ui.label("まだ誰も選んでいない",13,Ui.FAINT))
	info.add_child(Ui.title("一行",24))
	for i in fight.party.size():
		var m2: Dictionary=fight.party[i]
		var row:=Ui.list_row(false,Color(str(G.db.jobs[str(m2.job)].color)),8)
		var v:=Ui.vbox(2);row.add_child(v)
		var hh:=Ui.hbox(6);v.add_child(hh)
		hh.add_child(Cards.job_chip(str(m2.job),12));hh.add_child(Ui.label(str(m2.name),16,Ui.GOLD_HI if str(m2.get("named",""))!="" else Ui.TEXT,true));hh.add_child(Ui.stars(int(m2.star),12))
		var s:=Ui.hbox(4);v.add_child(s)
		for kk in Ui.STATS:s.add_child(Ui.label("%s%d"%[Ui.STAT[kk].glyph,int(m2.stats[kk])],13,Ui.STAT[kk].color))
		var idx: int=i
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_LEFT:enemy_sel=idx;fill_info())
		info.add_child(row)
	info.add_child(Ui.wrap_label("盤の女を押すと、職の動き方とスキルが出る。",13,Ui.FAINT,410))

func pick(u: int) -> void:
	var st=G.state
	var m: Dictionary=st.monster(u)
	if m.is_empty():return
	if u in st.party and sel_uid==u:
		st.party.erase(u);sel_uid=-1
	elif not Stats.can_fight(m):
		G.main.toast("倒れている魔物は出せない",Ui.DANGER);sel_uid=u
	elif not u in st.party and st.party.size()<int(G.db.balance.party_size):
		st.party.append(u);sel_uid=u;st.placement.erase(str(u))
	else:
		sel_uid=u
	enemy_sel=-1
	refresh()

func place_at(c: Vector2i) -> void:
	var st=G.state
	if sel_uid<0 or not c in home:return
	var m: Dictionary=st.monster(sel_uid)
	if m.is_empty() or not Stats.can_fight(m):return
	if not sel_uid in st.party:
		if st.party.size()>=int(G.db.balance.party_size):G.main.toast("出撃は%d体まで"%int(G.db.balance.party_size),Ui.DANGER);return
		st.party.append(sel_uid)
	var old: Array=st.placement.get(str(sel_uid),[-1,-1])
	for u in st.party:
		var p=st.placement.get(str(int(u)),null)
		if p!=null and int(u)!=sel_uid and Vector2i(int(p[0]),int(p[1]))==c:st.placement[str(int(u))]=old
	st.placement[str(sel_uid)]=[c.x,c.y]
	G.main.sfx("click")
	refresh()

func auto_fill() -> void:
	var st=G.state
	var ms: Array=st.monsters.filter(func(m):return Stats.can_fight(m))
	ms.sort_custom(func(a,b):return Stats.power(a)*float(a.hp)/maxf(1.0,float(Stats.hp_max(a)))>Stats.power(b)*float(b.hp)/maxf(1.0,float(Stats.hp_max(b))))
	st.party=ms.slice(0,int(G.db.balance.party_size)).map(func(m):return int(m.uid))
	st.placement={}
	if is_instance_valid(roster):refresh()

func start() -> void:
	var st=G.state
	var cost: int=Sites.cost_of(site,k)
	if int(st.stamina.now)<cost:G.main.toast("スタミナが足りない",Ui.DANGER);return
	if party().is_empty():return
	st.stamina.now=int(st.stamina.now)-cost
	G.main.goto("battle",{"site":str(site.id),"k":k})

func back_out() -> void:
	G.state.world.chain={}
	G.main.goto("world" if k==0 else "ranch",{"site":str(site.id)})

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		view.hover_cell=view.cell_under(e.position)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index==MOUSE_BUTTON_LEFT:
			var key: String=view.piece_under(e.position)
			if key.begins_with("w"):enemy_sel=int(key.substr(1));sel_uid=-1;refresh();return
			if key.begins_with("m"):
				var u: int=int(key.substr(1))
				if sel_uid==u:G.state.party.erase(u);sel_uid=-1
				else:sel_uid=u
				refresh();return
			var c: Vector2i=view.cell_under(e.position)
			if c.x>=0:place_at(c)
		elif e.button_index==MOUSE_BUTTON_RIGHT:
			sel_uid=-1;enemy_sel=-1;refresh()
		elif e.button_index==MOUSE_BUTTON_WHEEL_UP:view.zoom=minf(3.4,view.zoom*1.08)
		elif e.button_index==MOUSE_BUTTON_WHEEL_DOWN:view.zoom=maxf(1.2,view.zoom/1.08)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q:view.rotate_view(-1)
			KEY_E:view.rotate_view(1)
			KEY_SPACE,KEY_ENTER:
				if not start_button.disabled:start()
