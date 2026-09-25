extends Control
## 牧場の画面（企画書 第8章・設計書 1.1）。拠点。施設を建て、女の使い道と魔物の務めを決め、出撃し、一日を終える。
## 割り当ては1通りだけ：左の一覧で女か魔物を選ぶ → 入れられる施設が地図で光る → 施設を押す（引きずって落としてもよい）。
## 地図の施設を押したときは、中の様子を見せるだけ。
const Look=preload("res://game/map/look.gd")
const Calls=preload("res://game_v2/animation/call_registry.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Parts=preload("res://game_v2/animation/parts.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const RanchMap=preload("res://game/map/ranch_map.gd")
const TopBar=preload("res://game/ui/parts/top_bar.gd")
const Help=preload("res://game/ui/parts/help.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Windows=preload("res://game/ui/parts/windows.gd")
const Report=preload("res://game/ui/parts/report.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Day=preload("res://game/core/day.gd")
const Sites=preload("res://game/world/sites.gd")
const LEFT:=Rect2(14,76,420,876)
const RIGHT:=Rect2(1472,76,434,876)
const BOTTOM:=Rect2(446,966,1014,104)
const USE_ORDER:={"cell":0,"house":1,"nursery":2,"altar":3,"press":4}

var map
var mode:="view"                  # view / build
var build_def:=""
var build_rot:=0
var build_move:=-1                # 動かしている施設の uid（-1 なら新しく建てる）
var tab:="woman"                  # 左の一覧：woman / monster
var held: Dictionary={}           # 選んでいる人 {kind: woman|monster, uid}
var left_panel: PanelContainer
var left_info: VBoxContainer
var left_box: VBoxContainer
var tab_buttons: Dictionary={}
var right_panel: PanelContainer
var right_box: VBoxContainer
var bottom_panel: PanelContainer
var mode_buttons: Dictionary={}
var sortie_button: Button
var top: Control
var ghost_icon: Control           # 引きずっている札の記号
var ui_hidden:=false
var panning:=false
var pan_from:=Vector2.ZERO
var press_at:=Vector2.ZERO

func open(p: Dictionary) -> void:
	var layer:=CanvasLayer.new();layer.layer=-5;add_child(layer)
	map=RanchMap.new();layer.add_child(map)
	map.screen_center=Vector2(953,540)
	top=TopBar.new();top.help_topic="ranch";add_child(top)
	build_left();build_right();build_bottom()
	G.main.changed.connect(refresh_all)
	refresh_all()
	var dbg: Dictionary=G.main.debug
	if dbg.has("rot"):map.dir=int(dbg.rot);map.yaw_deg=map.dir*45.0
	if p.get("morning",false):
		Report.morning(self,after_morning)
	else:
		Help.first("ranch")
		check_overflow()
	if dbg.has("select"):
		for f in G.state.facilities:
			if f.def==str(dbg.select):select_fac(int(f.uid));break
	if dbg.has("hold"):
		var parts: PackedStringArray=str(dbg.hold).split(":")
		if parts.size()==2:hold(parts[0],int(parts[1]))
		elif str(dbg.hold)=="woman" and not G.state.women.is_empty():hold("woman",int(G.state.women_in("cell")[0].uid if not G.state.women_in("cell").is_empty() else G.state.women[0].uid))
		elif str(dbg.hold)=="monster" and not G.state.monsters.is_empty():hold("monster",int(G.state.monsters[-1].uid))
	if dbg.has("mode"):set_mode(str(dbg.mode))

func close() -> void:
	if map!=null:map.release_all()
	G.anim.detach()

# ───────── 左：女と魔物の一覧 ─────────
func build_left() -> void:
	left_panel=Ui.placed_panel(self,LEFT,14)
	var v:=Ui.vbox(8);left_panel.add_child(v)
	left_info=Ui.vbox(4);v.add_child(left_info)
	var th:=Ui.hbox(6);v.add_child(th)
	for t in [["woman","heart","女"],["monster","paw","魔物"]]:
		var key: String=t[0]
		var b:=Ui.icon_button(t[1],t[2],func():tab=key;refresh_left(),17)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tab_buttons[key]=b;th.add_child(b)
	var hint:=Ui.wrap_label("押して選ぶと、入れられる施設が地図で光る。光る施設を押すか、札を引きずって落とす。",13,Ui.DIM,390);v.add_child(hint)
	var holder:=VBoxContainer.new();holder.custom_minimum_size=Vector2(LEFT.size.x-28,LEFT.size.y-190);v.add_child(holder)
	left_box=Ui.scroll_box(holder,6)

func refresh_left() -> void:
	var st=G.state
	for c in left_info.get_children():c.queue_free()
	var reg: Dictionary=G.db.region(st.chapter)
	var story: String=Sites.next_story(reg)
	left_info.add_child(Ui.label("次の山：%s%s"%[reg.name,"「%s」"%G.db.stages[story].name if story!="" else ""],15,Ui.GOLD_HI,true))
	if st.cell_count()>int(st.caps.cell):left_info.add_child(Ui.wrap_label("牢があふれている（%d/%d）。使い道を決めるか手放すまで出撃できない。"%[st.cell_count(),int(st.caps.cell)],14,Ui.DANGER,390))
	var tomorrow: int=st.eggs.filter(func(e):return int(e.hatch_day)<=st.day+1).size()
	if tomorrow>0:left_info.add_child(Ui.label("明日の朝に孵る卵 %d"%tomorrow,14,Ui.PINK))
	for k in tab_buttons:
		var b: Button=tab_buttons[k]
		b.text="女 %d（牢 %d）"%[st.women.size(),st.cell_count()] if k=="woman" else "魔物 %d"%st.monsters.size()
		if k==tab:Ui.color_style(b,Color("5a2430"))
		else:
			for s in ["normal","hover","pressed","disabled"]:b.remove_theme_stylebox_override(s)
	for c in left_box.get_children():c.queue_free()
	tile_nodes={}
	# 札は一度に全部作らず、1フレームの時間の上限までずつ作る（ブラウザ版・スマホで画面が止まらないように）。
	var items: Array=[]   # 作る札の順番。[種類, 記録] か ["section", 名前]
	if tab=="woman":
		var list: Array=st.women.duplicate()
		list.sort_custom(func(a,b):return [int(USE_ORDER.get(str(a.use),9)),-int(a.star),int(a.uid)]<[int(USE_ORDER.get(str(b.use),9)),-int(b.star),int(b.uid)])
		if list.is_empty():left_box.add_child(Ui.wrap_label("まだ誰も捕らえていない。出撃して一行に勝つと、全員を獲得して牢に入る。",15,Ui.DIM,380))
		var last:=""
		for w in list:
			if str(w.use)!=last:
				last=str(w.use)
				items.append(["section",Captive.USE_NAMES.get(last,"")])
			items.append(["woman",w])
	else:
		var ms: Array=st.monsters.duplicate()
		ms.sort_custom(func(a,b):return [-Stats.power(a),int(a.uid)]<[-Stats.power(b),int(b.uid)])
		for m in ms:items.append(["monster",m])
	list_gen+=1
	add_tiles(items,list_gen)

## 札を作る時間の上限（1フレームあたり、マイクロ秒）。最初のフレームは見えている分として少し多めに作る。
const TILE_BUDGET_US:=6000
var list_gen:=0
var tile_nodes: Dictionary={}      # "woman:uid" / "monster:uid" → 札
func add_tiles(items: Array,gen: int) -> void:
	var i:=0
	var first:=true
	while i<items.size():
		var t0:=Time.get_ticks_usec()
		while i<items.size() and (Time.get_ticks_usec()-t0<TILE_BUDGET_US or (first and i<10)):
			var it: Array=items[i];i+=1
			if str(it[0])=="section":left_box.add_child(Ui.section(str(it[1])));continue
			var tile: Control=make_tile(str(it[0]),it[1])
			left_box.add_child(tile);tile_nodes["%s:%d"%[it[0],int(it[1].uid)]]=tile
		first=false
		if i<items.size():
			await get_tree().process_frame
			if gen!=list_gen or not is_inside_tree():return

func make_tile(kind: String,r: Dictionary) -> Control:
	var st=G.state
	var u: int=int(r.uid)
	var sel: bool=held.get("kind","")==kind and int(held.get("uid",-1))==u
	if kind=="woman":
		return Cards.woman_tile(r,sel,func():toggle_hold("woman",u),Cards.woman_note(r),Ui.DIM,false,drag_for("woman",u))
	var note: String=Cards.monster_note(r)
	if u in st.party:note="出撃組・"+note
	return Cards.monster_tile(r,sel,func():toggle_hold("monster",u),note,Ui.DANGER if Stats.ko(r) else Ui.DIM,false,drag_for("monster",u))

## 選んだ・外した札だけを作り直す（一覧を全部作り直さない）。
func retile(sel: Dictionary) -> void:
	if sel.is_empty():return
	var key: String="%s:%d"%[sel.kind,int(sel.uid)]
	var old=tile_nodes.get(key)
	if old==null or not is_instance_valid(old):return
	var r: Dictionary=G.state.woman(int(sel.uid)) if sel.kind=="woman" else G.state.monster(int(sel.uid))
	if r.is_empty():return
	var tile: Control=make_tile(str(sel.kind),r)
	var idx: int=old.get_index()
	left_box.add_child(tile);left_box.move_child(tile,idx)
	old.queue_free();tile_nodes[key]=tile

func drag_for(kind: String,uid: int) -> Dictionary:
	return {"move":func(p):drag_move(kind,uid,p),"drop":func(p):drag_drop(kind,uid,p)}

# ───────── 選ぶ → 光る施設へ入れる ─────────
func toggle_hold(kind: String,uid: int) -> void:
	if held.get("kind","")==kind and int(held.get("uid",-1))==uid:release_hold()
	else:hold(kind,uid)

## rebuild=false は引きずっている間（つかんでいる札を作り直すと、離したことが届かなくなる）。
func hold(kind: String,uid: int,quiet: bool=false,rebuild: bool=true) -> void:
	if mode!="view":set_mode("view")
	var prev: Dictionary=held.duplicate()
	var same_list: bool=tab==kind and not tile_nodes.is_empty()
	held={"kind":kind,"uid":uid}
	tab=kind
	map.selected=-1
	map.highlight={};map.dimmed={};map.hints={}
	for f in G.state.facilities:
		var t: Dictionary=target_info(f)
		if t.is_empty():continue
		if t.ok:map.highlight[int(f.uid)]=Color("78c27a")
		else:map.dimmed[int(f.uid)]=true
		map.hints[int(f.uid)]={"text":str(t.text),"color":t.color}
	if not quiet:G.main.sfx("click")
	if rebuild:
		if same_list:retile(prev);retile(held)
		else:refresh_left()
	refresh_right()

func release_hold() -> void:
	var prev: Dictionary=held.duplicate()
	held={}
	map.highlight={};map.dimmed={};map.hints={}
	if ghost_icon!=null:ghost_icon.queue_free();ghost_icon=null
	retile(prev);refresh_right()

func held_record() -> Dictionary:
	if held.is_empty():return {}
	return G.state.woman(int(held.uid)) if held.kind=="woman" else G.state.monster(int(held.uid))

## 選んでいる人をこの施設に入れられるか：{ok, text, color}。関係のない施設は {}。
func target_info(f: Dictionary) -> Dictionary:
	var st=G.state
	var kind: String=st.kind_of(f)
	var r: Dictionary=held_record()
	if r.is_empty():return {}
	if held.kind=="woman":
		if not kind in ["cell","house","press","nursery","altar"]:return {}
		if int(f.woman)==int(r.uid) or (kind=="cell" and str(r.use)=="cell"):return {"ok":false,"text":"今ここ","color":Ui.DIM}
		if kind=="cell":return {"ok":true,"text":"牢へ戻す","color":Ui.DIM}
		var why: String=Eggs.can_lay(r) if kind in ["nursery","altar"] else ""
		var hint: Array=woman_hint(r,kind,f,why)
		var other: Dictionary=st.woman_at(f)
		var text: String=str(hint[0])
		if why=="" and not other.is_empty():text+="（%sと入れ替え）"%other.name
		return {"ok":why=="","text":text,"color":hint[1]}
	if not kind in ["house","nursery","den"]:return {}
	if kind=="den":
		if str(r.job)=="rest":return {"ok":false,"text":"休んでいる","color":Ui.DIM}
		var full: bool=st.job_count("rest")>=int(st.caps.den)
		var heal: int=mini(Stats.hp_max(r)-int(r.hp),int(ceil(float(Stats.hp_max(r))*float(G.db.balance.rest_heal))))
		return {"ok":not full,"text":"巣がいっぱい" if full else "休む（体力 +%d）"%heal,"color":Ui.DANGER if full else Ui.GOOD}
	if int(f.monster)==int(r.uid):return {"ok":false,"text":"今ここ","color":Ui.DIM}
	var h: Array=monster_hint(r,kind,f,st.woman_at(f))
	return {"ok":true,"text":str(h[0]),"color":h[1]}

## 光っている施設へ入れる。
func place_held(f: Dictionary) -> void:
	var st=G.state
	var t: Dictionary=target_info(f)
	var r: Dictionary=held_record()
	if t.is_empty() or r.is_empty():return
	if not t.ok:G.main.toast(str(t.text),Ui.DANGER);G.main.sfx("error");return
	var kind: String=st.kind_of(f)
	if held.kind=="woman":
		if kind=="cell":st.move_woman(r,"cell")
		else:
			var other: Dictionary=st.woman_at(f)
			if not other.is_empty() and int(other.uid)!=int(r.uid):st.move_woman(other,"cell")
			var why: String=Captive.to_use(r,kind,f)
			if why!="":G.main.toast(why,Ui.DANGER);return
		G.main.toast("%sを%sへ"%[r.name,Windows.fac_label(f)],Ui.GOOD)
	else:
		match kind:
			"den":st.set_job(r,"rest")
			"house":st.set_job(r,"partner",f)
			"nursery":st.set_job(r,"father",f)
		G.main.toast("%sを%s"%[r.name,{"den":"巣で休ませた","house":"%sの相手役にした"%Windows.fac_label(f),"nursery":"苗床の父にした"}[kind]],Ui.GOOD)
	G.main.sfx("confirm")
	held={}
	map.highlight={};map.dimmed={};map.hints={}
	map.selected=int(f.uid)
	G.main.refresh()

func drag_move(kind: String,uid: int,p: Vector2) -> void:
	if held.get("kind","")!=kind or int(held.get("uid",-1))!=uid:hold(kind,uid,false,false)
	if ghost_icon==null:
		var r: Dictionary=held_record()
		ghost_icon=Cards.woman_icon(r,52) if kind=="woman" else Cards.monster_icon(r,52)
		ghost_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		ghost_icon.z_index=100
		add_child(ghost_icon)
	ghost_icon.position=p-Vector2(26,26)
	var c: Vector2=map.cell_at_screen(p)
	map.hover_cell=Vector2i(int(floor(c.x)),int(floor(c.y)))

func drag_drop(kind: String,uid: int,p: Vector2) -> void:
	if ghost_icon!=null:ghost_icon.queue_free();ghost_icon=null
	var f: Dictionary={}
	if not (Rect2(LEFT).has_point(p) or (Rect2(RIGHT).has_point(p) and right_panel.visible)):
		var c: Vector2=map.cell_at_screen(p)
		f=G.state.fac_at(int(floor(c.x)),int(floor(c.y)))
	if f.is_empty() or not map.hints.has(int(f.uid)):
		refresh_left.call_deferred();return
	place_held(f)

# ───────── 右：選んだ人・施設の中・建てる物 ─────────
func build_right() -> void:
	right_panel=Ui.placed_panel(self,RIGHT,16)
	var holder:=VBoxContainer.new();holder.custom_minimum_size=RIGHT.size-Vector2(32,32);right_panel.add_child(holder)
	right_box=Ui.scroll_box(holder,8)

func refresh_right() -> void:
	for c in right_box.get_children():c.queue_free()
	right_panel.visible=not ui_hidden and (mode=="build" or map.selected>=0 or not held.is_empty())
	if mode=="build":palette();return
	if not held.is_empty():held_panel();return
	var f: Dictionary=G.state.fac(map.selected)
	if f.is_empty():return
	fac_panel(f)

## 選んでいる人の中身と、光る施設の案内。
func held_panel() -> void:
	var st=G.state
	var r: Dictionary=held_record()
	if r.is_empty():release_hold();return
	var box:=PanelContainer.new();box.add_theme_stylebox_override("panel",Ui.box(Color("2a1c20"),Color("78c27a"),1,3,10));right_box.add_child(box)
	box.add_child(Ui.wrap_label("光る施設を押す（札を引きずって落としてもよい）。右クリックでやめる。",14,Color("a8e0a0"),380))
	if held.kind=="woman":
		right_box.add_child(Cards.woman_detail(r,380))
		var ah:=HFlowContainer.new();ah.add_theme_constant_override("h_separation",6);ah.add_theme_constant_override("v_separation",6);right_box.add_child(ah)
		ah.add_child(Ui.icon_button("scroll","詳しく",func():Windows.captives(self,int(r.uid)),14))
		ah.add_child(Ui.icon_button("coin","手放す（金 %d）"%(int(r.star)*30),func():
			G.main.confirm("手放す","%sを帰す。取り戻せない。"%r.name,"帰す",func():
				var money: int=Captive.release(r);release_hold();G.main.toast("金 %d を受け取った"%money,Ui.GOOD);G.main.refresh(),true),14))
	else:
		right_box.add_child(Cards.monster_detail(r,380))
		var ah2:=HFlowContainer.new();ah2.add_theme_constant_override("h_separation",6);ah2.add_theme_constant_override("v_separation",6);right_box.add_child(ah2)
		ah2.add_child(Ui.icon_button("scroll","詳しく（回復・育成）",func():Windows.monsters(self,int(r.uid)),14))

## 地図の施設を押したとき：中の様子を見せるだけ。
func fac_panel(f: Dictionary) -> void:
	var st=G.state
	var d: Dictionary=G.db.rooms[f.def]
	var kind: String=str(d.kind)
	var head:=Ui.hbox(10);right_box.add_child(head)
	var col: Color=Ui.STAT[str(d.house)].color if kind=="house" else Ui.GOLD
	head.add_child(Ui.icon_disc({"house":"chain","nursery":"egg","altar":"magic","press":"drop","cell":"cage","den":"paw"}.get(kind,"castle"),44,col))
	var hv:=Ui.vbox(2);head.add_child(hv)
	hv.add_child(Ui.title(Windows.fac_label(f),26))
	if kind=="house":hv.add_child(Ui.chip("%s（仕込みと相手役の%sが伸びる）"%[Ui.STAT[d.house].house,Ui.STAT[d.house].name],col,13))
	else:hv.add_child(Ui.wrap_label(str(d.get("desc","")),13,Ui.DIM,330))
	match kind:
		"cell":
			right_box.add_child(Ui.label("牢 %d / %d"%[st.cell_count(),int(st.caps.cell)],17,Ui.DANGER if st.cell_count()>int(st.caps.cell) else Ui.TEXT,true))
			for w in st.women_in("cell"):
				var u: int=int(w.uid)
				right_box.add_child(Cards.woman_tile(w,false,func():hold("woman",u),Cards.woman_note(w)))
			right_box.add_child(slot_button("cell_slot","牢の定員"))
		"den":
			right_box.add_child(Ui.label("巣 %d / %d（休ませた魔物は体力が戻る）"%[st.job_count("rest"),int(st.caps.den)],16,Ui.TEXT,true))
			for m in st.monsters.filter(func(x):return str(x.job)=="rest"):
				var mu: int=int(m.uid)
				right_box.add_child(Cards.monster_tile(m,false,func():hold("monster",mu),Cards.monster_note(m)))
			right_box.add_child(slot_button("den_slot","巣の枠"))
		"house","nursery","altar","press":
			var w2: Dictionary=st.woman_at(f)
			right_box.add_child(Ui.section("女"))
			if w2.is_empty():right_box.add_child(Ui.wrap_label("空いている。左の一覧で女を選んで、ここを押す。",14,Ui.FAINT,380))
			else:
				right_box.add_child(Cards.woman_detail(w2,380))
				right_box.add_child(Ui.icon_button("cage","牢へ戻す",func():st.move_woman(w2,"cell");G.main.refresh(),14))
			if kind in ["house","nursery"]:
				var role: String="相手役" if kind=="house" else "父"
				var m2: Dictionary=st.monster_at(f)
				right_box.add_child(Ui.section(role,"務めた晩は体力が戻らない"))
				if m2.is_empty():right_box.add_child(Ui.wrap_label("いない。左の一覧で魔物を選んで、ここを押す。",14,Ui.FAINT,380))
				else:
					var h2: Array=monster_hint(m2,kind,f,w2)
					right_box.add_child(Cards.monster_tile(m2,false,func():hold("monster",int(m2.uid)),str(h2[0]),h2[1]))
					right_box.add_child(Ui.icon_button("close","外す（巣へ）",func():st.set_job(m2,"rest");G.main.refresh(),14))
			if not w2.is_empty():
				if kind=="nursery" and not st.monster_at(f).is_empty():
					right_box.add_child(Ui.section("卵の予想"))
					right_box.add_child(Windows.nursery_forecast(w2,st.monster_at(f),380))
				if kind=="altar":
					right_box.add_child(Ui.section("卵の予想"))
					right_box.add_child(Windows.altar_forecast(w2,380))
	if kind in ["house","nursery","altar","press"]:scene_controls(f)
	if not d.get("fixed",false):
		right_box.add_child(Ui.rule())
		var mv:=Ui.hbox(6);right_box.add_child(mv)
		mv.add_child(Ui.icon_button("hand","動かす",func():start_move(f),14))
		mv.add_child(Ui.icon_button("sort","向きを変える",func():
			var why: String=st.move_facility(f,int(f.x),int(f.y),int(f.rot)+1)
			if why!="":G.main.toast(why,Ui.DANGER)
			G.main.refresh(),14))
		right_box.add_child(Ui.icon_button("bin","取り壊す（金 +%d）"%(int(d.get("cost",0))/2),func():
			G.main.confirm("取り壊す","%sを取り壊す。中の女は牢へ、魔物は巣へ戻る。"%d.name,"取り壊す",func():
				st.gain({"money":int(d.get("cost",0))/2});st.remove_facility(int(f.uid));map.selected=-1;G.main.refresh()),14))

## 施設で流す場面・女の表情・女の服を選ぶ（見た目だけ。伸びる能力は家具で決まる）。
const SCENE_NAMES:={"supine_knees":"仰向け膝立て","bind_ground":"組み伏せる","carry_shoulder":"担ぐ","birth_egg":"産卵","greeting":"挨拶","full_nelson":"羽交い締め","mating_press":"種付けプレス"}
const EXPR_NAMES:={"neutral":"通常","closed":"目を閉じる","wink":"ウインク"}
static var event_symbols: Dictionary={}
static func scene_name(id: String) -> String:
	if SCENE_NAMES.has(id):return str(SCENE_NAMES[id])
	if event_symbols.is_empty():
		event_symbols["_"]=""
		for e in Calls.read().get("events",[]):
			var sid: String=str(e.get("pair_scene_id",""))
			if sid!="" and str(e.get("symbol",""))!="" and not event_symbols.has(sid):event_symbols[sid]=str(e.symbol)
	return str(event_symbols.get(id,id))

func scene_controls(f: Dictionary) -> void:
	var st=G.state
	var d: Dictionary=G.db.rooms[f.def]
	var w: Dictionary=st.woman_at(f)
	var partner: bool=int(d.get("staff",0))>0 and (not st.monster_at(f).is_empty() or str(d.kind)=="press")
	right_box.add_child(Ui.section("場面","見た目だけ。伸びる能力は家具で決まる"))
	var ids: Array=[""]
	var names: Array=["家具の場面（おまかせ）"]
	var solo_of: Dictionary=map.scene_solo()
	var all_ids: Array=solo_of.keys();all_ids.sort()
	for id in all_ids:
		if solo_of[id]==partner:continue
		ids.append(id);names.append(scene_name(id))
	var sel: int=maxi(0,ids.find(str(f.get("scene",""))))
	right_box.add_child(Ui.wrap_label("相手の魔物がいる：2体の場面から選ぶ" if partner else "相手の魔物がいない：1人の場面から選ぶ（相手役を入れると2体の場面も選べる）",12,Ui.FAINT,380))
	var ob:=OptionButton.new();ob.custom_minimum_size=Vector2(360,34)
	for n in names:ob.add_item(str(n))
	ob.select(sel)
	ob.item_selected.connect(func(i):f.scene=ids[i];G.main.refresh())
	right_box.add_child(ob)
	if w.is_empty():return
	# 表情（その女の頭が持つ表情だけ）
	var aid: String=map.actors.get("w:%d"%int(w.uid),"")
	var exprs: Array=[""]+G.anim.expressions_of(aid).filter(func(x):return str(x)!="neutral")
	var eh:=Ui.hbox(6);right_box.add_child(eh)
	eh.add_child(Ui.label("表情",14,Ui.DIM))
	var eo:=OptionButton.new();eo.custom_minimum_size=Vector2(160,32)
	for x in exprs:eo.add_item("場面のまま" if str(x)=="" else str(EXPR_NAMES.get(str(x),x)))
	eo.select(maxi(0,exprs.find(str(f.get("expr","")))))
	eo.item_selected.connect(func(i):f.expr=exprs[i];G.main.refresh())
	eh.add_child(eo)
	if exprs.size()<=1:eh.add_child(Ui.label("この頭は表情の差分なし",12,Ui.FAINT))
	# 服（頭はそのまま、胴・腰・腕・脚を選んだキャラの服に。肌の色が合うキャラだけ）
	var head: String=str(Look.woman(w).get("parts",{}).get("head",Parts.BASE))
	var outfits: Array=[""]+Parts.ids("upper_body").filter(func(p):return Parts.same_skin(head,p))
	var oh:=Ui.hbox(6);right_box.add_child(oh)
	oh.add_child(Ui.label("服",14,Ui.DIM))
	var oo:=OptionButton.new();oo.custom_minimum_size=Vector2(260,32)
	for x in outfits:oo.add_item("元の服" if str(x)=="" else Profiles.name(str(x)))
	oo.select(maxi(0,outfits.find(str(f.get("outfit","")))))
	oo.item_selected.connect(func(i):f.outfit=outfits[i];G.main.refresh())
	oh.add_child(oo)

func start_move(f: Dictionary) -> void:
	build_move=int(f.uid);build_def=str(f.def);build_rot=int(f.rot)
	mode="build";map.mode="build";map.selected=-1
	G.main.toast("置き場所を押す（R で向き、右クリックでやめる）",Ui.INFO)
	update_ghost();refresh_right()

## 女を入れたときの一言：入れられない理由、または見込み。[文, 色]
func woman_hint(w: Dictionary,kind: String,f: Dictionary,why: String) -> Array:
	if why!="":
		if int(w.stage)<2 and kind in ["nursery","altar"]:return ["従順から（今：%s）"%Ui.STAGES[int(w.stage)],Ui.DANGER]
		return [why,Ui.DANGER]
	match kind:
		"house":
			var h: String=str(G.db.rooms[f.def].house)
			if w.weak_known and str(w.weak)==h:return ["弱点の房（倍の速さ）",Ui.GOOD]
			return ["%sの仕込み +%d"%[Ui.STAT[h].name,int(G.db.balance.shikomi.main)],Ui.TEXT]
		"nursery","altar":
			var best:="";var bv:=-1.0
			for k in Ui.STATS:
				var c: float=Eggs.center(w,k)
				if c>bv:bv=c;best=k
			var pre: String="抽選の卵・" if kind=="altar" else ""
			return ["%s%sの素質 %d前後"%[pre,Ui.STAT[best].name,int(round(minf(100,bv)))],Ui.PINK]
		"press":return ["精気 %d/晩"%int(round(Captive.press_amount(w))),Ui.RES.essence.color]
	return ["",Ui.DIM]

## 相手役として1晩で実際に伸びる量（素質まで）。
func partner_real(m: Dictionary,f: Dictionary,w: Dictionary) -> Dictionary:
	var out: Dictionary={}
	if w.is_empty():return out
	var g: Dictionary=Captive.partner_gain(w,str(G.db.rooms[f.def].house))
	for k in g:out[k]=minf(float(g[k]),maxf(0.0,float(m.apt[k])-float(m.stats[k])))
	return out

## 魔物を入れたときの一言。[文, 色]
func monster_hint(m: Dictionary,kind: String,f: Dictionary,w: Dictionary) -> Array:
	var st=G.state
	var warn: String=""
	if Stats.ko(m):warn="倒れている・"
	elif int(m.uid) in st.party:warn="出撃組・"
	if kind=="house":
		var h: String=str(G.db.rooms[f.def].house)
		if w.is_empty():return [warn+"女がいない（%s %d / %d）"%[Ui.STAT[h].name,int(m.stats[h]),int(m.apt[h])],Ui.DANGER if warn!="" else Ui.DIM]
		var g: Dictionary=partner_real(m,f,w)
		var parts: Array=[]
		for k in g:
			if float(g[k])>0.0:parts.append("%s+%d"%[Ui.STAT[k].name,int(round(float(g[k])))])
		var txt: String="・".join(parts) if not parts.is_empty() else "伸びきった"
		return [warn+txt,Ui.DANGER if warn!="" else (Ui.GOOD if not parts.is_empty() else Ui.FAINT)]
	var ps: Array=Stats.passives(m)
	var txt2: String="継ぐ候補 %d（%s）"%[ps.size(),"・".join(ps.map(func(id):return G.db.skill_name(id)))] if not ps.is_empty() else "継ぐものなし"
	return [warn+txt2,Ui.DANGER if warn!="" else (Ui.PINK if not ps.is_empty() else Ui.DIM)]

## 枠を増やすボタン（お金。買うたびに値段が上がる）。
func slot_button(key: String,label: String) -> Button:
	var st=G.state
	var cost: int=st.slot_cost(key)
	var b:=Ui.icon_button("coin","%sを%d増やす（金 %d）"%[label,int(G.db.balance.slot_step),cost],func():
		if st.buy_slot(key):G.main.toast("%sを増やした"%label,Ui.GOOD);G.main.refresh(),14)
	b.disabled=not st.can_pay({"money":cost})
	return b

func palette() -> void:
	var st=G.state
	right_box.add_child(Ui.title("施設を建てる",26))
	if build_move>=0:
		right_box.add_child(Ui.wrap_label("動かしている：%s。置き場所を押す。R で向きを変える。右クリックかEscでやめる。"%G.db.rooms[build_def].name,14,Ui.GOLD_HI,370))
		return
	right_box.add_child(Ui.wrap_label("選んで地図の床を押す。R で向きを変える。右クリックかEscでやめる。家具はほとんど1マス（木馬・磔などは1×2）なので、詰めて並べられる。",14,Ui.DIM,370))
	var fl:=HFlowContainer.new();right_box.add_child(fl)
	fl.add_child(slot_button("stamina_up","スタミナの最大"))
	for sec in [["nursery","苗床"],["altar","召喚陣"],["press","搾り場"],["house_end","耐の房"],["house_str","力の房"],["house_mag","魔の房"],["house_spd","速の房"],["deco","飾り（女は入らない。見た目だけ）"]]:
		var key: String=sec[0]
		right_box.add_child(Ui.section(sec[1]))
		for id in G.db.rooms:
			var d: Dictionary=G.db.rooms[id]
			if d.get("fixed",false) or int(d.get("chapter",0))>st.chapter:continue
			var k2: String=str(d.kind) if str(d.kind)!="house" else "house_"+str(d.house)
			if k2!=key:continue
			var col: Color=Ui.STAT[str(d.house)].color if str(d.kind)=="house" else Ui.GOLD
			right_box.add_child(palette_button(id,str(d.name),int(d.cost),str(d.get("desc","")),col))

func palette_button(id: String,name: String,cost: int,desc: String,color: Color) -> Button:
	var b:=Ui.button("%s　金 %d"%[name,cost],func():build_def=id;update_ghost();refresh_right(),15)
	b.tooltip_text=desc
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	if build_def==id:Ui.color_style(b,color.darkened(0.45))
	b.disabled=not G.state.can_pay({"money":cost})
	return b

# ───────── 下：モードと主ボタン ─────────
func build_bottom() -> void:
	bottom_panel=Ui.placed_panel(self,BOTTOM,14)
	var h:=Ui.hbox(8);h.alignment=BoxContainer.ALIGNMENT_CENTER;bottom_panel.add_child(h)
	for x in [["view","eye","見る"],["build","hammer","建てる"]]:
		var key: String=x[0]
		var b:=Ui.icon_button(x[1],x[2],func():set_mode("view" if mode==key else key),15)
		b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		mode_buttons[key]=b;h.add_child(b)
	var sep:=ColorRect.new();sep.color=Color(Ui.GOLD,0.3);sep.custom_minimum_size=Vector2(1,40);sep.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(sep)
	for x in [["egg","卵",func():Windows.eggs(self)],["book","図鑑",func():Windows.book(self)]]:
		var b2:=Ui.icon_button(x[0],x[1],x[2],15);b2.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(b2)
	h.add_child(Ui.spacer())
	var eb:=Ui.icon_button("moon","一日を終える",end_day,16);eb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(eb)
	sortie_button=Ui.icon_button("sword","出撃",sortie,19,Ui.CRIMSON)
	Ui.primary_style(sortie_button)
	sortie_button.custom_minimum_size=Vector2(200,56);sortie_button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	h.add_child(sortie_button)

func set_mode(m: String) -> void:
	mode=m
	map.mode=m
	if m!="build":build_def="";map.ghost={};build_move=-1
	else:
		map.selected=-1
		if not held.is_empty():held={};map.highlight={};map.dimmed={};map.hints={}
	for k in mode_buttons:
		var b: Button=mode_buttons[k]
		if k==m:Ui.color_style(b,Color("5a2430"))
		else:
			for s in ["normal","hover","pressed","disabled"]:b.remove_theme_stylebox_override(s)
	refresh_right()

func refresh_all() -> void:
	if not is_inside_tree():return
	if not held.is_empty() and held_record().is_empty():held={}
	if not held.is_empty():hold(held.kind,int(held.uid),true)
	refresh_left();refresh_right()
	set_mode(mode)
	var why: String=Day.sortie_block()
	sortie_button.disabled=why!=""
	sortie_button.tooltip_text=why if why!="" else "大陸の地図へ（スタミナ %d）"%int(G.state.stamina.now)
	left_panel.visible=not ui_hidden
	bottom_panel.visible=not ui_hidden

# ───────── 施設を見る・建てる ─────────
func select_fac(u: int) -> void:
	map.selected=u
	var f: Dictionary=G.state.fac(u)
	if not f.is_empty():
		map.focus_on(G.state.fac_center(f))
		if int(f.woman)>=0:
			var tw:=create_tween();tw.tween_property(map,"zoom",maxf(map.zoom,3.2),0.35).set_trans(Tween.TRANS_SINE)
	refresh_right()

func focus_woman(uid: int) -> void:
	var w: Dictionary=G.state.woman(uid)
	if w.is_empty():return
	var f: Dictionary=G.state.fac(int(w.get("fac",-1)))
	if f.is_empty():f=G.state.first_of("cell")
	if f.is_empty():return
	map.focus_on(G.state.fac_center(f))
	var tw:=create_tween();tw.tween_property(map,"zoom",maxf(map.zoom,3.4),0.35).set_trans(Tween.TRANS_SINE)

func update_ghost() -> void:
	if build_def=="" or map.hover_cell.x<0:map.ghost={};return
	var why: String=G.state.place_block(build_def,map.hover_cell.x,map.hover_cell.y,build_rot,build_move)
	map.ghost={"def":build_def,"x":map.hover_cell.x,"y":map.hover_cell.y,"rot":build_rot,"ok":why=="","why":why}

func place_here(cell: Vector2i) -> void:
	var st=G.state
	if build_def=="":return
	if build_move>=0:
		var mf: Dictionary=st.fac(build_move)
		var mwhy: String=st.move_facility(mf,cell.x,cell.y,build_rot) if not mf.is_empty() else "施設がない"
		if mwhy!="":G.main.toast(mwhy,Ui.DANGER);G.main.sfx("error");return
		G.main.sfx("confirm");set_mode("view");select_fac(int(mf.uid));G.main.refresh();return
	var d: Dictionary=G.db.rooms[build_def]
	var why: String=st.place_block(build_def,cell.x,cell.y,build_rot)
	if why=="" and not st.can_pay({"money":int(d.cost)}):why="お金が足りない"
	if why!="":G.main.toast(why,Ui.DANGER);G.main.sfx("error");return
	st.pay({"money":int(d.cost)})
	var f: Dictionary=st.add_facility(build_def,cell.x,cell.y,build_rot)
	G.main.sfx("confirm")
	G.main.toast("%sを建てた"%d.name,Ui.GOOD)
	G.main.refresh()
	if not st.can_pay({"money":int(d.cost)}):set_mode("view");select_fac(int(f.uid))

func click_cell(cell: Vector2i) -> void:
	var st=G.state
	if mode=="build":place_here(cell);return
	var f: Dictionary=st.fac_at(cell.x,cell.y)
	if not held.is_empty():
		if f.is_empty() or not map.hints.has(int(f.uid)):release_hold()
		else:place_held(f)
		return
	if f.is_empty():map.selected=-1;refresh_right()
	else:select_fac(int(f.uid))

# ───────── 一日と出撃 ─────────
func check_overflow() -> void:
	var st=G.state
	if st.cell_count()>int(st.caps.cell):
		G.main.toast("牢があふれている（%d/%d）。使い道を決めるか手放す"%[st.cell_count(),int(st.caps.cell)],Ui.DANGER,4.0)

func sortie() -> void:
	var why: String=Day.sortie_block()
	if why!="":G.main.toast(why,Ui.DANGER);tab="woman";refresh_left();return
	G.main.goto("world",{})

func end_day() -> void:
	var st=G.state
	var idle: int=st.women_in("cell").size()
	var body: String="夜になり、房・搾り場・苗床・召喚陣が働き、巣の魔物が休む。スタミナが戻る。"
	if int(st.stamina.now)>0:body+="\n残りのスタミナ %d は使わずに終わる。"%int(st.stamina.now)
	if idle>0:body+="\n牢に %d 人いる（使い道を決めていない）。"%idle
	G.main.confirm("一日を終える",body,"終える",func():
		release_hold()
		Day.end_day()
		G.main.refresh()
		Report.morning(self,after_morning))

func after_morning() -> void:
	refresh_all()
	check_overflow()

# ───────── 入力 ─────────
func _process(delta: float) -> void:
	if not G.main.has_overlay():
		var mv:=Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):mv.x-=1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):mv.x+=1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):mv.y-=1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):mv.y+=1
		if mv!=Vector2.ZERO:map.pan_screen(-mv*delta*900.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var c: Vector2=map.cell_at_screen(e.position)
		var cell:=Vector2i(int(floor(c.x)),int(floor(c.y)))
		if cell!=map.hover_cell:
			map.hover_cell=cell
			if mode=="build":update_ghost()
		if panning:
			map.pan_screen(e.position-pan_from);pan_from=e.position
		elif e.button_mask&(MOUSE_BUTTON_MASK_RIGHT|MOUSE_BUTTON_MASK_MIDDLE)!=0 and e.position.distance_to(press_at)>6:
			panning=true;pan_from=e.position
	elif e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			if e.pressed:press_at=e.position;panning=false
			else:
				if not panning and e.button_index==MOUSE_BUTTON_RIGHT:cancel()
				panning=false
		elif e.button_index==MOUSE_BUTTON_LEFT and e.pressed:
			var c2: Vector2=map.cell_at_screen(e.position)
			click_cell(Vector2i(int(floor(c2.x)),int(floor(c2.y))))
		elif e.pressed and e.button_index==MOUSE_BUTTON_WHEEL_UP:map.zoom=minf(4.4,map.zoom*1.1)
		elif e.pressed and e.button_index==MOUSE_BUTTON_WHEEL_DOWN:map.zoom=maxf(0.55,map.zoom/1.1)
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_Q:map.rotate_view(-1)
			KEY_E:map.rotate_view(1)
			KEY_R:
				build_rot=(build_rot+1)%4;update_ghost()
			KEY_ESCAPE:cancel()
			KEY_H:
				ui_hidden=not ui_hidden;refresh_all()
			KEY_1:set_mode("view")
			KEY_2:set_mode("build")

func cancel() -> void:
	if not held.is_empty():release_hold();return
	if mode!="view":set_mode("view")
	else:
		map.selected=-1
		var tw:=create_tween();tw.tween_property(map,"zoom",1.2,0.3)
		refresh_right()
