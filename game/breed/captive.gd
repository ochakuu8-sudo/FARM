extends RefCounted
## 捕らえた女（企画書 第6章・設計書 第6章）。使い道（房・苗床・召喚陣・搾り場）、房の夜（仕込み・心の段階・相手役の伸び）、
## 搾り場の夜（精気）、産む夜、巣の休み。
const G=preload("res://game/core/g.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]
const SUB:={"str":"spd","mag":"end","spd":"mag","end":"str"}
const PHASES:=["defiant","shaken","yielded","fallen","deep"]
const STAGE_NAMES:=["反抗","動揺","従順","堕落","心酔"]
const USE_NAMES:={"cell":"牢","house":"房","nursery":"苗床","altar":"召喚陣","press":"搾り場"}

static func nights_per_stage() -> int:
	var b: Dictionary=G.db.balance
	return int(b.nights_per_stage.prologue if G.state.prologue() else b.nights_per_stage.main)

static func stage_cap(stage: int) -> float:
	var a: Array=G.db.balance.stage_cap
	return float(a[clampi(stage,0,a.size()-1)])

static func top_stat(w: Dictionary) -> String:
	var best:="str";var bv:=-1.0
	for k in STATS:
		if float(w.shikomi.get(k,0))>bv:bv=float(w.shikomi[k]);best=k
	return best

static func house_of(w: Dictionary) -> String:
	if str(w.use)!="house":return ""
	var f: Dictionary=G.state.fac(int(w.fac))
	return str(G.db.rooms.get(f.get("def",""),{}).get("house",""))

## 房で1晩過ごしたときの仕込みの増え方（予測にも使う。状態は変えない）。
static func shikomi_after(w: Dictionary,house: String) -> Dictionary:
	var s: Dictionary=w.shikomi.duplicate()
	var b: Dictionary=G.db.balance.shikomi
	s[house]=float(s[house])+float(b.main)
	var sub: String=SUB[house]
	s[sub]=float(s[sub])+float(b.sub)
	var cap: float=stage_cap(int(w.stage))
	var total:=0.0
	for k in STATS:total+=float(s[k])
	if total>cap:
		# 今の房の能力以外から、今の値に比例して差し引く
		var over: float=total-cap
		var others:=0.0
		for k in STATS:
			if k!=house:others+=float(s[k])
		for k in STATS:
			if k==house or others<=0.0:continue
			s[k]=maxf(0.0,float(s[k])-over*float(s[k])/others)
		total=0.0
		for k in STATS:total+=float(s[k])
		if total>cap:s[house]=maxf(0.0,float(s[house])-(total-cap))
	return s

## あと何晩で次の段階か（房にいるとき）。
static func nights_left(w: Dictionary) -> int:
	var h: String=house_of(w)
	if h=="" or int(w.stage)>=4:return -1
	var per: int=2 if h==str(w.weak) else 1
	return int(ceil(float(nights_per_stage()-int(w.nights))/per))

## 相手役の1晩の伸び {主の能力: 量, 副の能力: 量}。
static func partner_gain(w: Dictionary,house: String) -> Dictionary:
	var p: Dictionary=G.db.balance.partner
	return {house:float(p.main)*(1.0+float(w.star)*float(p.per_star)),SUB[house]:float(p.sub)}

static func press_amount(w: Dictionary) -> float:
	var p: Dictionary=G.db.balance.press
	return float(p.base)*(1.0+float(w.star)*float(p.per_star))*(1.0+float(w.stage)*float(p.per_stage))

# ───────── 使い道 ─────────
## 使い道へ移せない理由（移せるなら ""）。
static func use_block(w: Dictionary,use: String,f: Dictionary) -> String:
	if use=="cell":return ""
	if f.is_empty():return "施設を選ぶ"
	if G.state.kind_of(f)!=use:return "この施設では使えない"
	if int(f.woman)>=0 and int(f.woman)!=int(w.uid):return "%sはもう使われている"%G.db.rooms[f.def].name
	if use in ["nursery","altar"]:return Eggs.can_lay(w)
	return ""

static func to_use(w: Dictionary,use: String,f: Dictionary={}) -> String:
	var why: String=use_block(w,use,f)
	if why!="":return why
	G.state.move_woman(w,use,f)
	return ""

## 手放す：お金を少し受け取って帰す（牢があふれたとき用）。
static func release(w: Dictionary) -> int:
	var st=G.state
	var money: int=int(w.star)*30
	st.gain({"money":money})
	st.move_woman(w,"cell")
	var named: String=str(w.get("woman_id",""))
	if named!="":st.named[named].captured=false
	st.women.erase(w)
	return money

static func patrol(w: Dictionary) -> bool:
	var st=G.state
	if int(st.flags.get("patrol_day",0))==st.day:return false
	st.flags.patrol_day=st.day
	w.weak_known=true
	w.history.append({"day":st.day,"text":"見回りで弱点（%sの房）が分かった"%G.db.stat_name(str(w.weak))})
	return true

# ───────── 夜 ─────────
## 房・搾り場・苗床・召喚陣・巣の1晩（女・魔物の番号の順）。
static func night_pass() -> void:
	var st=G.state
	var b: Dictionary=G.db.balance
	var list: Array=st.women.duplicate()
	list.sort_custom(func(a,c):return int(a.uid)<int(c.uid))
	var essence:=0.0
	var grew: Dictionary={}          # 魔物の uid → {能力: 量}
	var opened: Array=[]
	for w in list:
		var f: Dictionary=st.fac(int(w.fac))
		match str(w.use):
			"house":
				var h: String=str(G.db.rooms[f.def].house)
				w.shikomi=shikomi_after(w,h)
				var m: Dictionary=st.monster_at(f)
				if not m.is_empty():
					var g: Dictionary=partner_gain(w,h)
					if not grew.has(int(m.uid)):grew[int(m.uid)]={}
					for k in g:
						var before: float=float(m.stats[k])
						for id in Stats.grow(m,k,float(g[k])):opened.append({"uid":int(m.uid),"skill":id})
						grew[int(m.uid)][k]=float(grew[int(m.uid)].get(k,0.0))+float(m.stats[k])-before
				if int(w.stage)<4:
					w.nights=int(w.nights)+(2 if h==str(w.weak) else 1)
					if int(w.nights)>=nights_per_stage():
						w.nights=0
						stage_up(w)
			"press":
				essence+=press_amount(w)
			"nursery","altar":
				lay_night(w,f)
	if essence>0:
		st.gain({"essence":essence})
		st.log_event("income","搾り場から精気 %d"%int(round(essence)))
	for uid in grew:
		var m2: Dictionary=st.monster(int(uid))
		var parts: Array=[]
		for k in grew[uid]:
			if float(grew[uid][k])>0.0:parts.append("%s+%d"%[G.db.stat_name(k),int(round(float(grew[uid][k])))])
		if not parts.is_empty():st.log_event("grow","%s（相手役）%s"%[m2.name,"　".join(parts)],{"monster":int(uid)})
		elif Stats.maxed(m2):st.log_event("grow","%sは素質の上限まで伸びきった"%m2.name,{"monster":int(uid)})
	for o in opened:
		st.log_event("passive","%sが「%s」を覚えた"%[st.monster(int(o.uid)).name,G.db.skill_name(str(o.skill))],{"monster":int(o.uid)})
	# 巣で休んだ魔物は体力が戻る（務めた魔物は戻らない）
	for m3 in st.monsters:
		if str(m3.job)=="rest":
			var mx: int=Stats.hp_max(m3)
			m3.hp=mini(mx,int(m3.hp)+int(ceil(float(mx)*float(b.rest_heal))))

## 苗床・召喚陣の1晩：産み始める → 数晩で卵を産む。産める限り続ける。
static func lay_night(w: Dictionary,f: Dictionary) -> void:
	var st=G.state
	var kind: String=str(w.use)
	if w.get("laying",{}).is_empty():
		var why: String=Eggs.can_lay(w)
		if why!="":return
		var father: Dictionary=st.monster_at(f) if kind=="nursery" else {}
		if kind=="nursery" and father.is_empty():
			st.log_event("warn","%sの苗床に父がいない"%w.name);return
		if kind=="altar":
			var cost: int=Eggs.altar_cost()
			if not st.pay({"essence":cost}):
				st.log_event("warn","精気が足りず、%sの召喚の儀式を始められなかった（精気 %d）"%[w.name,cost]);return
		w.laying={"kind":kind,"nights":Eggs.lay_nights(),"father":int(father.get("uid",-1))}
		st.records.scenes["%s|%d"%[kind,int(w.uid)]]=true
	w.laying.nights=int(w.laying.nights)-1
	if int(w.laying.nights)<=0:
		var fa: Dictionary=st.monster(int(w.laying.get("father",-1)))
		if kind=="nursery" and fa.is_empty():w.laying={};return
		var e: Dictionary=Eggs.lay(w,kind,fa)
		w.laying={}
		var what: String="%sの卵"%G.db.species_name(str(e.species)) if kind=="nursery" else "召喚陣の卵"
		st.log_event("egg","%sが%sを産んだ（%d晩後に孵る）"%[w.name,what,int(e.hatch_day)-st.day],{"woman":int(w.uid),"egg":int(e.uid)})

## 段階を1つ上げる。名前付きは節目の場面を予約する。
static func stage_up(w: Dictionary) -> void:
	var st=G.state
	w.stage=mini(4,int(w.stage)+1)
	st.gain({"essence":float(G.db.balance.essence.stage)*int(w.stage)})
	w.history.append({"day":st.day,"text":"心の段階が「%s」に"%STAGE_NAMES[int(w.stage)]})
	st.log_event("stage","%sが「%s」になった（精気 +%d）"%[w.name,STAGE_NAMES[int(w.stage)],int(G.db.balance.essence.stage)*int(w.stage)],{"woman":int(w.uid),"stage":int(w.stage)})
	if str(w.get("woman_id",""))!="":
		if not st.flags.has("milestones"):st.flags.milestones=[]
		st.flags.milestones.append({"woman":int(w.uid),"stage":int(w.stage),"ending":int(w.stage)>=4})
