extends RefCounted
## 確かめ用の自動の遊び手（play_test・--setup・battle_test が使う）。決めた手順で牧場を回し、スタミナの許す限り出撃する。
## 上手に遊ぶためではなく、仕組みが通しで回るかを確かめるためのもの。
const G=preload("res://game/core/g.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Setup=preload("res://game/battle/setup.gd")
const Outcome=preload("res://game/battle/outcome.gd")
const Sites=preload("res://game/world/sites.gd")
const Day=preload("res://game/core/day.gd")
const STATS:=["str","mag","spd","end"]

## 1日の昼の支度と出撃を行う。返り値は今日の戦闘の要約。
static func play_day() -> Dictionary:
	var st=G.state
	st.flags.milestones=[]
	build()
	assign_women()
	assign_monsters()
	var sum: Dictionary={"fights":0,"wins":0,"captured":0,"story":""}
	var tries:=0
	while tries<8:
		tries+=1
		if Day.sortie_block()!="":assign_women();if Day.sortie_block()!="":break
		var site: Dictionary=choose_site()
		if site.is_empty():break
		var k: int=Sites.start_k(site)
		while k<site.chain.size():
			var cost: int=Sites.cost_of(site,k)
			if int(st.stamina.now)<cost:break
			var team: Array=pick_party()
			if team.size()<2:break
			st.stamina.now=int(st.stamina.now)-cost
			var f: Dictionary=Setup.fight(site,k)
			var sim=Setup.start(site,k,team)
			var res: Dictionary=sim.run_all()
			var out: Dictionary=Outcome.apply(site,k,res,f)
			sum.fights+=1
			if res.won:sum.wins+=1;sum.captured+=out.captured.size()
			if out.cleared:sum.story=str(site.name)
			if not res.won:
				if str(site.kind)=="story":st.flags.story_fail_day=st.day
				break
			k+=1
			if Day.victory():return sum
			assign_women()
		if Day.victory():break
	return sum

static func choose_site() -> Dictionary:
	var st=G.state
	var sites: Array=st.world.sites_today
	var power:=0.0
	for u in pick_party():power+=Stats.power(st.monster(u))
	for s in sites:
		if str(s.kind)=="story" and int(st.flags.get("story_fail_day",-1))!=st.day:
			var k0: int=Sites.start_k(s)
			var need: int=Sites.cost_of(s,k0)+(Sites.cost_of(s,k0+1) if k0+1<s.chain.size() else 0)
			if int(st.stamina.now)>=need:return s
	var best: Dictionary={};var bv:=-1.0
	for s in sites:
		if str(s.kind)!="hunt" or int(st.stamina.now)<int(s.cost) or Sites.done(s):continue
		var foe:=0.0
		for m in s.chain[0].party:foe+=Make_sum(m.stats)
		if foe>power*0.9:continue
		var v: float=foe
		if v>bv:bv=v;best=s
	return best

static func Make_sum(s: Dictionary) -> float:
	var t:=0.0
	for k in STATS:t+=float(s.get(k,0))
	return t

## 出す4体：体力が半分以上ある者の中で強い順。
## 出撃の4体：役割で組む（盾1・回復1・遠距離か術1、残りは強い順）。並べ方も役割で決める（盾と近接は前、遠距離・術・回復は後ろ）。
## 役割の欄が無ければ強い順。考える遊び手の目安（何も考えない構成より勝てるか）を見るためのもの。
static func pick_party() -> Array:
	var st=G.state
	var list: Array=st.monsters.filter(func(m):return Stats.can_fight(m) and float(m.hp)>=float(Stats.hp_max(m))*0.35)
	list.sort_custom(func(a,b):return Stats.power(a)>Stats.power(b))
	var n: int=int(G.db.balance.party_size)
	var out: Array=[]
	var role:=func(m):return str(G.db.species.get(str(m.species),{}).get("role",""))
	for want in [["盾"],["回復"],["遠距離","術"]]:
		for m in list:
			if out.size()<n and not m in out and role.call(m) in want:out.append(m);break
	for m in list:
		if out.size()<n and not m in out:out.append(m)
	# 並べ方：前の列に盾・近接・暗殺・妨害、後ろの列に遠距離・術・回復・支援
	var front: Array=[Vector2i(3,3),Vector2i(3,4),Vector2i(3,2),Vector2i(3,5)]
	var back: Array=[Vector2i(1,3),Vector2i(1,4),Vector2i(1,2),Vector2i(1,5)]
	for m in out:
		var r: String=role.call(m)
		var c: Vector2i=(back if r in ["遠距離","術","回復","支援"] else front).pop_front()
		st.placement[str(int(m.uid))]=[c.x,c.y]
	return out.map(func(m):return int(m.uid))

static func build() -> void:
	var st=G.state
	var want:={"house":2+st.chapter,"press":1+st.chapter/2,"nursery":1+st.chapter/3,"altar":1+st.chapter/3}
	for kind in ["altar","house","press","nursery"]:
		while st.facilities_of(kind).size()<int(want[kind]):
			var def:=""
			for id in G.db.rooms:
				var rd: Dictionary=G.db.rooms[id]
				if str(rd.kind)==kind and int(rd.get("chapter",0))<=st.chapter and st.can_pay({"money":int(rd.cost)+150}):def=id;break
			if def=="" or not place(def):break
	if st.cell_count()>=int(st.caps.cell)-1 and st.res.money>st.slot_cost("cell_slot")+300:st.buy_slot("cell_slot")
	if st.monsters.size()>int(st.caps.den)+2 and st.res.money>st.slot_cost("den_slot")+300:st.buy_slot("den_slot")
	if st.res.money>st.slot_cost("stamina_up")+600:st.buy_slot("stamina_up")

static func place(def: String) -> bool:
	var st=G.state
	for y in range(1,int(st.grid.h)-2,2):
		for x in range(1,int(st.grid.w)-2,2):
			if st.place_block(def,x,y)=="" and st.pay({"money":int(G.db.rooms[def].cost)}):
				st.add_facility(def,x,y);return true
	return false

static func free_fac(kind: String) -> Dictionary:
	for f in G.state.facilities_of(kind):
		if int(f.woman)<0:return f
	return {}

static func assign_women() -> void:
	var st=G.state
	var list: Array=st.women.duplicate()
	list.sort_custom(func(a,c):return int(a.star)>int(c.star))
	for w in list:
		if not w.weak_known and int(st.flags.get("patrol_day",0))!=st.day:Captive.patrol(w)
		var use: String=str(w.use)
		if use in ["nursery","altar"] and Eggs.can_lay(w)=="":continue
		if Eggs.can_lay(w)=="":
			var n: Dictionary=free_fac("nursery")
			var a: Dictionary=free_fac("altar")
			if not a.is_empty() and st.res.essence>=Eggs.altar_cost() and (int(w.eggs_done)%2==0 or n.is_empty()):Captive.to_use(w,"altar",a);continue
			if not n.is_empty():Captive.to_use(w,"nursery",n);continue
		if use=="cell" or (use in ["nursery","altar"] and Eggs.can_lay(w)!=""):
			if int(w.stage)<4:
				var h: Dictionary=free_house(w)
				if not h.is_empty():Captive.to_use(w,"house",h);continue
			var p: Dictionary=free_fac("press")
			if not p.is_empty():Captive.to_use(w,"press",p);continue
			if use!="cell":st.move_woman(w,"cell")
	while st.cell_count()>int(st.caps.cell):
		var pool: Array=st.women_in("cell")
		pool.sort_custom(func(a,c):return int(a.star)<int(c.star))
		Captive.release(pool[0])

## 弱点の房が空いていればそこ、なければ空いている房。
static func free_house(w: Dictionary) -> Dictionary:
	var any: Dictionary={}
	for f in G.state.facilities_of("house"):
		if int(f.woman)>=0:continue
		if str(G.db.rooms[f.def].house)==str(w.weak):return f
		if any.is_empty():any=f
	return any

## 伸びしろ（素質の合計 − 能力の合計）。
static func potential(m: Dictionary) -> float:
	var t:=0.0
	for k in STATS:t+=float(m.apt[k])-float(m.stats[k])
	return t+Make_sum(m.apt)*0.2

## 父（苗床）と相手役（房）を決める。出撃に出す強い4体は務めさせない（休ませる）。
static func assign_monsters() -> void:
	var st=G.state
	var party: Array=pick_party()
	var list: Array=st.monsters.duplicate()
	list.sort_custom(func(a,b):return Stats.power(a)>Stats.power(b))
	for m in list:
		if not int(m.uid) in party:st.set_job(m,"rest")
	for f in st.facilities_of("nursery"):
		if int(f.woman)<0:continue
		var father: Dictionary={}
		for m in list:
			if int(m.uid) in party:continue
			if father.is_empty() or Stats.passives(m).size()>Stats.passives(father).size():father=m
		if father.is_empty() and not list.is_empty():father=list[0]
		if not father.is_empty():st.set_job(father,"father",f)
	for f in st.facilities_of("house"):
		if int(f.woman)<0:continue
		var best: Dictionary={}
		for m in list:
			if int(m.uid) in party or str(m.job)!="rest" or Stats.maxed(m):continue
			if best.is_empty() or potential(m)>potential(best):best=m
		if not best.is_empty():st.set_job(best,"partner",f)
	for m in list:
		if int(m.uid) in party:st.set_job(m,"rest")
	# 余った精気で、出撃する魔物を育てる
	for u in party:
		var pm: Dictionary=st.monster(int(u))
		if pm.is_empty() or int(pm.get("trained_day",-1))==st.day:continue
		var gap_k:="";var gap:=0.0
		for k in STATS:
			if float(pm.apt[k])-float(pm.stats[k])>gap:gap=float(pm.apt[k])-float(pm.stats[k]);gap_k=k
		if gap_k!="" and st.res.essence>Eggs.altar_cost()+60 and st.pay({"essence":int(G.db.balance.train.cost)}):
			pm.trained_day=st.day;Stats.grow(pm,gap_k,float(G.db.balance.train.gain))
	# 体力0の者はお金に余裕があれば起こす
	for m in list:
		if Stats.ko(m) and st.res.money>400:Stats.heal_now(m)
