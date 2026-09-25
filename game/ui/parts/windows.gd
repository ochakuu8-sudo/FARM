extends RefCounted
## 牧場の上に重ねる窓：捕らえた女（詳しく・見回り・手放す）・魔物帳（詳しく・回復・育成）・卵（苗床と召喚陣の予想）・図鑑と記録。
## 女と魔物を施設に入れるのは牧場の地図の上だけ（「地図で入れる」で牧場の選ぶ状態へ渡す）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const Cards=preload("res://game/ui/parts/cards.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]

static func frame(title: String,icon: String,size: Vector2) -> Array:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,26);p.custom_minimum_size=size
	var v:=Ui.vbox(12);p.add_child(v)
	var th:=Ui.hbox(12);v.add_child(th)
	th.add_child(Ui.icon_disc(icon,44,Ui.GOLD));th.add_child(Ui.title(title,30))
	th.add_child(Ui.spacer())
	var close:=Ui.icon_button("close","閉じる",func():G.main.close_overlay(null),16);th.add_child(close)
	v.add_child(Ui.rule())
	var body:=Ui.hbox(18);body.size_flags_vertical=Control.SIZE_EXPAND_FILL;v.add_child(body)
	return [p,v,body]

static func column(parent: Control,width: float,height: float) -> VBoxContainer:
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(width,height);parent.add_child(box)
	return Ui.scroll_box(box,8)

static func flow() -> HFlowContainer:
	var f:=HFlowContainer.new();f.add_theme_constant_override("h_separation",6);f.add_theme_constant_override("v_separation",6)
	return f

const NUMS:=["①","②","③","④","⑤","⑥","⑦","⑧","⑨","⑩"]
## 施設の名前。同じ施設が2つ以上あれば番号を付ける（建てた順）。
static func fac_label(f: Dictionary) -> String:
	var rd: Dictionary=G.db.rooms[f.def]
	var same: Array=G.state.facilities.filter(func(x):return str(x.def)==str(f.def))
	var num: String=""
	if same.size()>1:
		var i: int=same.find(f)
		num=NUMS[i] if i>=0 and i<NUMS.size() else str(i+1)
	if str(rd.kind)=="house":return "%s%s（%s）"%[rd.name,num,Ui.STAT[str(rd.house)].name]
	return str(rd.name)+num

# ───────── 捕らえた女 ─────────
static func captives(screen,select_uid: int=-1) -> void:
	var st=G.state
	var fr: Array=frame("捕らえた女","heart",Vector2(1400,840))
	var list: VBoxContainer=column(fr[2],580,720)
	var detail: VBoxContainer=column(fr[2],740,720)
	var sel:=[select_uid]
	# 無名関数は作った時点の変数の値を写し取るので、自分を呼ぶには配列に入れて参照する
	var fill_ref:=[Callable()]
	fill_ref[0]=func():
		for c in list.get_children():c.queue_free()
		for c in detail.get_children():c.queue_free()
		var women: Array=st.women.duplicate()
		var order:={"cell":0,"house":1,"nursery":2,"altar":3,"press":4}
		women.sort_custom(func(a,c):return [int(order.get(str(a.use),9)),-int(a.star),int(a.uid)]<[int(order.get(str(c.use),9)),-int(c.star),int(c.uid)])
		list.add_child(Ui.label("牢 %d / %d　（あふれていると出撃できない）"%[st.cell_count(),int(st.caps.cell)],16,Ui.DANGER if st.cell_count()>int(st.caps.cell) else Ui.DIM,true))
		if women.is_empty():list.add_child(Ui.wrap_label("まだ誰も捕らえていない。出撃して一行に勝つと、全員を獲得して牢に入る。",16,Ui.DIM,540))
		var grid: GridContainer=Cards.tile_grid(2);list.add_child(grid)
		for w in women:
			var u: int=int(w.uid)
			grid.add_child(Cards.woman_tile(w,u==sel[0],func():sel[0]=u;fill_ref[0].call(),Cards.woman_note(w)))
		var w0: Dictionary=st.woman(sel[0])
		if w0.is_empty() and not women.is_empty():w0=women[0];sel[0]=int(w0.uid)
		if w0.is_empty():return
		detail.add_child(Cards.woman_detail(w0,700))
		detail.add_child(Ui.rule())
		use_actions(screen,w0,detail,fill_ref[0])
	fill_ref[0].call()
	G.main.overlay(fr[0],0.6)

## 使い道（企画書 6.2）。見返りを並べて見せる。入れるのは地図の上で（牧場の画面の hold）。
static func use_actions(screen,w: Dictionary,box: VBoxContainer,refill: Callable) -> void:
	var st=G.state
	box.add_child(Ui.section("使い道","今：%s"%Captive.USE_NAMES.get(str(w.use),"")))
	if screen!=null and screen.has_method("hold"):
		var hb:=Ui.icon_button("hand","地図で入れる（光る施設を押す）",func():G.main.close_overlay(null);screen.hold("woman",int(w.uid)),17)
		Ui.primary_style(hb);box.add_child(hb)
	var rows: Array=[
		["house","chain","仕込む（房）","心の段階が進み、子の素質に足される仕込みが伸びる。相手役の魔物も房の能力が伸びる。"],
		["nursery","egg","産ませる（苗床）","父と同じ種族の卵。素質は母で決まり、父のパッシブを抽選で継ぐ。"],
		["altar","magic","産ませる（召喚陣）","精気 %d を払う抽選の卵。新しい種族が出る。等級（並〜伝説）あり。"%Eggs.altar_cost()],
		["press","drop","絞る（搾り場）","毎晩 精気 %d（★と段階で増える）。"%int(round(Captive.press_amount(w)))],
	]
	for r in rows:
		var use: String=r[0]
		var card:=PanelContainer.new();card.add_theme_stylebox_override("panel",Ui.ornate(Color("1e1519"),Ui.GOLD.darkened(0.2),12,8))
		var cv:=Ui.vbox(6);card.add_child(cv)
		var ch:=Ui.hbox(8);cv.add_child(ch)
		ch.add_child(Icons.rect(r[1],22,Ui.GOLD));ch.add_child(Ui.label(r[2],19,Ui.GOLD_HI,true))
		if str(w.use)==use:ch.add_child(Ui.chip("今ここ",Ui.GOOD,12))
		cv.add_child(Ui.wrap_label(r[3],13,Ui.DIM,660))
		var why: String=Eggs.can_lay(w) if use in ["nursery","altar"] else ""
		if why!="":cv.add_child(Ui.label(why,14,Ui.FAINT))
		box.add_child(card)
	var ah:=flow();box.add_child(ah)
	if str(w.use)!="cell":ah.add_child(Ui.icon_button("cage","牢へ戻す",func():st.move_woman(w,"cell");G.main.refresh();refill.call(),15))
	var patrol_used: bool=int(st.flags.get("patrol_day",0))==st.day
	if not w.weak_known:
		var pb:=Ui.icon_button("eye","見回り（今日%s）"%("はもう行った" if patrol_used else "は1人まで"),func():
			if Captive.patrol(w):
				G.main.toast("%sの弱点は%sだった"%[w.name,Ui.STAT[str(w.weak)].house],Ui.GOOD)
				if screen!=null and screen.has_method("focus_woman"):screen.focus_woman(int(w.uid))
				G.main.refresh();refill.call(),15)
		pb.disabled=patrol_used
		ah.add_child(pb)
	ah.add_child(Ui.icon_button("coin","手放す（金 %d）"%(int(w.star)*30),func():
		G.main.confirm("手放す","%sを帰す。取り戻せない。"%w.name,"帰す",func():
			var money: int=Captive.release(w);G.main.toast("金 %d を受け取った"%money,Ui.GOOD);G.main.refresh();refill.call(),true),15))
	if not w.history.is_empty():
		box.add_child(Ui.section("これまで"))
		for hst in w.history.slice(maxi(0,w.history.size()-6)):
			box.add_child(Ui.label("%d日目　%s"%[int(hst.day),str(hst.text)],13,Ui.DIM))

# ───────── 魔物帳 ─────────
static func monsters(screen,select_uid: int=-1) -> void:
	var st=G.state
	var fr: Array=frame("魔物帳","paw",Vector2(1400,840))
	var list: VBoxContainer=column(fr[2],580,720)
	var detail: VBoxContainer=column(fr[2],740,720)
	var sel:=[select_uid]
	var fill_ref:=[Callable()]
	fill_ref[0]=func():
		for c in list.get_children():c.queue_free()
		for c in detail.get_children():c.queue_free()
		var ms: Array=st.monsters.duplicate()
		ms.sort_custom(func(a,c):return [-Stats.power(a),int(a.uid)]<[-Stats.power(c),int(c.uid)])
		list.add_child(Ui.label("魔物 %d体　巣 %d / %d"%[ms.size(),st.job_count("rest"),int(st.caps.den)],16,Ui.DIM,true))
		var grid: GridContainer=Cards.tile_grid(2);list.add_child(grid)
		for m in ms:
			var u: int=int(m.uid)
			grid.add_child(Cards.monster_tile(m,u==sel[0],func():sel[0]=u;fill_ref[0].call(),Cards.monster_note(m),Ui.DANGER if Stats.ko(m) else Ui.DIM))
		var m0: Dictionary=st.monster(sel[0])
		if m0.is_empty() and not ms.is_empty():m0=ms[0];sel[0]=int(m0.uid)
		if m0.is_empty():return
		detail.add_child(Cards.monster_detail(m0,700))
		detail.add_child(Ui.rule())
		monster_actions(m0,detail,fill_ref[0])
	fill_ref[0].call()
	G.main.overlay(fr[0],0.6)

static func monster_actions(m: Dictionary,box: VBoxContainer,refill: Callable) -> void:
	var st=G.state
	box.add_child(Ui.section("今夜の務め","務めた晩は体力が戻らない"))
	box.add_child(Ui.label("今：%s"%Cards.job_text(m),15,Ui.GOLD_HI))
	var scr=G.main.current
	if scr!=null and scr.has_method("hold"):
		var hb:=Ui.icon_button("hand","地図で務めを決める（光る施設を押す）",func():G.main.close_overlay(null);scr.hold("monster",int(m.uid)),17)
		Ui.primary_style(hb);box.add_child(hb)
	box.add_child(Ui.section("回復と育成"))
	var fl2:=flow();box.add_child(fl2)
	var cost: int=Stats.heal_cost(m)
	var hb:=Ui.icon_button("heart","すぐ全快（金 %d）%s"%[cost,"・倒れているので高い" if Stats.ko(m) else ""],func():
		if Stats.heal_now(m):G.main.toast("%sが全快した"%m.name,Ui.GOOD);G.main.refresh();refill.call()
		else:G.main.toast("お金が足りない",Ui.DANGER),15)
	hb.disabled=cost<=0 or not st.can_pay({"money":cost})
	fl2.add_child(hb)
	var tc: int=int(G.db.balance.train.cost)
	var trained: bool=int(m.get("trained_day",-1))==st.day
	for k in STATS:
		var tb:=Ui.button("%s＋%d（精気 %d）"%[Ui.STAT[k].name,int(G.db.balance.train.gain),tc],func():
			if not st.pay({"essence":tc}):G.main.toast("精気が足りない",Ui.DANGER);return
			m.trained_day=st.day
			var opened: Array=Stats.grow(m,k,float(G.db.balance.train.gain))
			for id in opened:G.main.toast("%sが「%s」を覚えた"%[m.name,G.db.skill_name(id)],Ui.GOLD_HI)
			G.main.refresh();refill.call(),14)
		Ui.color_style(tb,Ui.STAT[k].color.darkened(0.55))
		tb.disabled=trained or float(m.stats[k])>=float(m.apt[k]) or not st.can_pay({"essence":tc})
		fl2.add_child(tb)
	box.add_child(Ui.label("精気での育成は1体につき1日1回。能力は素質を越えない。" if not trained else "今日はもう育てた",13,Ui.FAINT))

# ───────── 卵 ─────────
static func eggs(screen) -> void:
	var st=G.state
	var fr: Array=frame("卵と予想","egg",Vector2(1400,840))
	var left: VBoxContainer=column(fr[2],640,720)
	var right: VBoxContainer=column(fr[2],680,720)
	left.add_child(Ui.section("孵るのを待つ卵"))
	if st.eggs.is_empty():left.add_child(Ui.label("まだない",14,Ui.FAINT))
	for e in st.eggs:
		var row:=Ui.list_row(false,Ui.PINK,10)
		var h:=Ui.hbox(10);row.add_child(h)
		var col: Color=Ui.GRADE[int(e.grade)].color if int(e.grade)>=0 else Color(str(G.db.species[str(e.species)].tint))
		h.add_child(Ui.icon_disc("egg",36,col))
		var v:=Ui.vbox(2);h.add_child(v)
		var what: String=G.db.species_name(str(e.species)) if str(e.kind)=="nursery" else "召喚陣の卵（何が孵るかは孵ってのお楽しみ）"
		v.add_child(Ui.label("%sの卵　%s"%[str(e.mother_name),what],16,Ui.TEXT,true))
		v.add_child(Ui.label("%d日目の朝に孵る%s"%[int(e.hatch_day),"　殻の色が%s"%["鈍い","青緑","青白い","金"][int(e.grade)] if int(e.grade)>=0 else ""],13,Ui.DIM))
		left.add_child(row)
	left.add_child(Ui.section("産む途中"))
	var any:=false
	for w in st.women:
		if w.get("laying",{}).is_empty():continue
		any=true
		left.add_child(Ui.label("%s ─ %s　あと%d晩で産む"%[w.name,Captive.USE_NAMES[str(w.use)],int(w.laying.nights)],15,Ui.PINK))
	if not any:left.add_child(Ui.label("いない",14,Ui.FAINT))
	# 苗床の予想
	right.add_child(Ui.section("苗床の予想"))
	for f in st.facilities_of("nursery"):
		var w2: Dictionary=st.woman_at(f);var fa: Dictionary=st.monster_at(f)
		right.add_child(Ui.label("%s：%s × 父 %s"%[fac_label(f),w2.name if not w2.is_empty() else "（女がいない）",fa.name if not fa.is_empty() else "（父がいない）"],16,Ui.GOLD_HI,true))
		if w2.is_empty() or fa.is_empty():continue
		right.add_child(nursery_forecast(w2,fa,640))
	right.add_child(Ui.section("召喚陣の予想"))
	for f in st.facilities_of("altar"):
		var w3: Dictionary=st.woman_at(f)
		right.add_child(Ui.label("%s：%s"%[fac_label(f),w3.name if not w3.is_empty() else "（女がいない）"],16,Ui.GOLD_HI,true))
		if w3.is_empty():continue
		right.add_child(altar_forecast(w3,640))
	G.main.overlay(fr[0],0.6)

static func nursery_forecast(w: Dictionary,fa: Dictionary,width: float) -> VBoxContainer:
	var v:=Ui.vbox(6)
	v.add_child(Ui.label("種族：%s（父と同じ）"%G.db.species_name(str(fa.species)),15,Ui.TEXT))
	var mul: Dictionary=G.db.balance.apt_mul
	v.add_child(Ui.label("素質の予想（母の能力×%s＋仕込み×%s、±%d%%）"%[str(mul.mother),str(mul.shikomi),int(float(G.db.balance.apt_spread)*100)],14,Ui.DIM))
	v.add_child(Cards.range_bars(Eggs.predict_apt(w),width-200))
	var ch: Array=Eggs.inherit_chances(fa)
	if ch.is_empty():v.add_child(Ui.label("父のパッシブがない（継ぐものがない）",13,Ui.FAINT))
	else:
		v.add_child(Ui.label("父から継ぐパッシブ（それぞれ %d%%・%dつまで）"%[int(float(G.db.balance.inherit_p)*100),int(G.db.balance.inherit_max)],14,Ui.DIM))
		var fl:=flow();v.add_child(fl)
		for c in ch:fl.add_child(Ui.chip(G.db.skill_name(str(c.skill)),Ui.PINK,12))
	var why: String=Eggs.can_lay(w)
	if why!="":v.add_child(Ui.label(why,14,Ui.DANGER))
	return v

static func altar_forecast(w: Dictionary,width: float) -> VBoxContainer:
	var st=G.state
	var v:=Ui.vbox(6)
	v.add_child(Ui.label("産み始める晩に 精気 %d"%Eggs.altar_cost(),14,Ui.RES.essence.color))
	var fl:=flow();v.add_child(fl)
	for t in Eggs.altar_table(w):
		var known: bool=str(t.species) in st.unlocked.species
		var name: String=G.db.species_name(str(t.species)) if known else "？？？"
		fl.add_child(Ui.chip("%s %d%%"%[name,int(round(float(t.p)*100))],Color(str(G.db.species[str(t.species)].tint)) if known else Ui.FAINT,13))
	var g: Array=Eggs.grade_table(w)
	var gl:=flow();v.add_child(gl)
	for i in 4:gl.add_child(Ui.chip("%s %d%%"%[Cards.GRADES[i],int(round(float(g[i])*100))],Ui.GRADE[i].color,12,"star"))
	var bonus: Array=G.db.balance.altar.grade_bonus
	var mul2: Dictionary=G.db.balance.apt_mul
	v.add_child(Ui.wrap_label("素質は母の能力×%s＋仕込み×%s（±%d%%）に、等級で %s を足す。等級が高いほど生まれつきのパッシブが多い。"%[str(mul2.mother),str(mul2.shikomi),int(float(G.db.balance.apt_spread)*100),"・".join(bonus.map(func(x):return "+%d"%int(x)))],13,Ui.DIM,width))
	v.add_child(Cards.range_bars(Eggs.predict_apt(w),width-200))
	if int(st.altar_miss)>0:v.add_child(Ui.label("図鑑にない種族が出ないのが %d 回続いている（%d回で必ず出る）"%[int(st.altar_miss),int(G.db.balance.altar.pity)],13,Ui.GOLD))
	var why: String=Eggs.can_lay(w)
	if why!="":v.add_child(Ui.label(why,14,Ui.DANGER))
	return v

# ───────── 図鑑と記録 ─────────
static func book(screen) -> void:
	var st=G.state
	var fr: Array=frame("図鑑と記録","book",Vector2(1400,840))
	var left: VBoxContainer=column(fr[2],660,720)
	var right: VBoxContainer=column(fr[2],660,720)
	left.add_child(Ui.section("種族図鑑","%d / %d"%[st.unlocked.species.size(),G.db.species.size()]))
	for id in G.db.species:
		var d: Dictionary=G.db.species[id]
		var known: bool=id in st.unlocked.species
		var row:=Ui.list_row(false,Color(str(d.tint)),10)
		var rv:=Ui.vbox(4);row.add_child(rv)
		var rh:=Ui.hbox(8);rv.add_child(rh)
		rh.add_child(Ui.icon_disc(Cards.species_icon(id) if known else "lock",30,Color(str(d.tint)) if known else Ui.FAINT))
		rh.add_child(Ui.label(str(d.name) if known else "？？？",18,Ui.TEXT if known else Ui.FAINT,true))
		if known:rh.add_child(Cards.role_chip(id))
		if d.has("unique_of"):rh.add_child(Ui.chip("%sの卵だけ"%G.db.woman_name(str(d.unique_of)) if known else "名前付きの卵だけ",Ui.GOLD,11))
		if known:
			rv.add_child(Ui.wrap_label(str(d.desc),13,Ui.DIM,600))
			rv.add_child(Ui.label("アクティブ：%s　パッシブ：%s"%[G.db.skill_name(str(d.active)),"・".join(d.passives.map(func(p):return G.db.skill_name(str(p.skill))))],13,Ui.TEXT))
		else:
			var from: Array=[]
			for j in G.db.jobs:
				if G.db.jobs[j].get("altar",{}).has(id):from.append(G.db.jobs[j].name)
			if not from.is_empty():rv.add_child(Ui.label("召喚陣：%sの母から出る"%"・".join(from),13,Ui.FAINT))
		left.add_child(row)
	right.add_child(Ui.section("名前付きの女"))
	for id in G.db.women:
		var d2: Dictionary=G.db.women[id]
		var nm: Dictionary=st.named[id]
		var met: bool=G.db.region_index(str(d2.region))<=st.chapter
		var s: String="捕らえた" if nm.captured else "まだ"
		var hh:=Ui.hbox(8);right.add_child(hh)
		hh.add_child(Ui.label("%s（%s）"%[d2.name,d2.title] if met or nm.captured else "？？？",16,Ui.TEXT))
		hh.add_child(Ui.spacer());hh.add_child(Ui.chip(s,Ui.GOOD if nm.captured else Ui.DIM,12))
	right.add_child(Ui.section("結末"))
	if st.records.endings.is_empty():right.add_child(Ui.label("まだない",14,Ui.FAINT))
	for e in st.records.endings:right.add_child(Ui.label("%s ─ %sに寄せた結末（%d日目）"%[G.db.woman_name(str(e.woman)) if str(e.woman)!="" else "?",Ui.STAT.get(str(e.fall),{"name":"?"}).name,int(e.day)],14,Ui.TEXT))
	right.add_child(Ui.section("回想"))
	right.add_child(Ui.label("見た場面 %d"%st.records.scenes.size(),14,Ui.DIM))
	right.add_child(Ui.section("これまでの戦闘","勝ち %d・負け %d"%[int(st.records.wins),int(st.records.losses)]))
	for b in st.records.battles:
		var took: String="%d秒"%int(round(float(b.secs))) if b.has("secs") else "%d拍"%int(b.get("beats",0))
		right.add_child(Ui.label("%d日目　%s%s　%s　%s"%[int(b.day),str(b.site),"（%d戦目）"%(int(b.k)+1) if int(b.k)>0 else "","勝ち" if b.won else "負け",took],14,Ui.TEXT if b.won else Ui.DANGER))
		var parts: Array=[]
		for u in b.units:
			if str(u.side)=="m":parts.append("%s 与%d 受%d 技%d%s"%[u.name,int(u.dealt),int(u.taken),int(u.casts),"（空振り%d）"%int(u.whiffs) if int(u.whiffs)>0 else ""])
		right.add_child(Ui.wrap_label("　"+"　".join(parts),12,Ui.DIM,620))
	G.main.overlay(fr[0],0.6)
