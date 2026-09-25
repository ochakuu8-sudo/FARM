extends RefCounted
## 戦闘の計算（企画書 4.3・設計書 第4章）。TABS型のリアルタイム：配置したら全員が自由に動き、通常攻撃もスキルも自動。
## 時間は TICK 秒ずつ進め、乱数を使わない（同じ配置なら必ず同じ結果）。位置はマスを単位にした連続した座標（マス (x, y) の中心が x+0.5, y+0.5）。
##   1刻み：号令の記録を当てる → 溜まりが増える → 番号の順に1人ずつ（気絶・縛り → 技の構え → 振りかぶり → スキル → 神官の縛り解き
##   → 動き方ごとの位置取り（騎士は後衛を守る、盗賊は端を回る、射程2以上は詰められたら下がる）→ 射程なら振りかぶる／でなければ近づく）
##   → 押し合い（重なりを離す）→ 飛び道具が進む → 1秒ごとの効き目（再生・毒・締め上げ）。
## こちらは魔物4体と雑兵（setup.gd の minions）。雑兵は戦闘の中だけの者で、魔物が全員倒れたら逃げ散る。
## 号令（order）：戦闘中に balance.orders.count 回だけ出せる。focus は全員でその女を狙う、rally は全員が速まり溜まりが増える。
const G=preload("res://game/core/g.gd")
const Field=preload("res://game/battle/field.gd")
const Sk=preload("res://game/battle/skills.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]
const MAGIC_SPECIES:=["shadow","incubus","holy","rune_wraith","ward_angel","sanctum_holy"]
## 1刻みの秒。
const TICK:=0.05
## 体の半径（マス）。押し合いと当たりに使う。
const RADIUS:=0.3
## 射程の余裕（体の厚みの分。射程1は隣に立って届く）。
const REACH_PAD:=0.15
## 狙いを考え直す間隔（秒）。
const THINK:=0.25
## 飛び道具の速さ（マス/秒）。
const SHOT_SPEED:=8.0
## 戦士が縛りを引きちぎるまでの秒。
const TEAR_AFTER:=1.5

var field
var units: Array=[]
var t:=0.0                         # 経過秒
var ticks:=0
var cap:=120.0
var done:=false
var won:=false
var events: Array=[]              # この刻みの出来事（画面が読む）
var logs: Array=[]                # 記録 {time, text, side, u}
var stats: Dictionary={}          # unit id → {dealt, taken, casts, whiffs}
var projectiles: Array=[]         # 飛んでいる矢・術 {id, src, to, pos, dmg, magic}
var shot_seq:=0
var orders: Array=[]              # 号令の記録 [{tick, kind, target}]（同じ記録なら同じ結果）
var orders_left:=0
var second_acc:=0.0
var bal: Dictionary
## 痛手・回復・盾の倍率（balance.damage.scale）。見て分かる長さの戦闘にするため、全部を同じ割合で薄める。
var scale:=1.0

# ───────── 用意 ─────────
## fight：{board: [行], party: [一行の者 {job, named, name, stats, star, pos}]}、team：[{m: 魔物の記録, pos: マス}]。
## 3つ目の引数は、拍の戦闘で押したスキルの記録を受けていた名残（今は使わない）。
func setup(fight: Dictionary,team: Array,script: Array=[]) -> void:
	bal=G.db.balance
	cap=float(bal.time.cap)
	scale=float(bal.damage.get("scale",1.0))
	field=Field.new();field.setup(fight.board)
	units=[];t=0.0;ticks=0;done=false;won=false;events=[];logs=[];stats={};projectiles=[];shot_seq=0;second_acc=0.0
	orders=script.duplicate(true);orders_left=int(bal.get("orders",{}).get("count",0))-orders.size()
	for tm in team:
		if tm.has("minion"):units.append(minion_unit(tm.minion,tm.pos))
		else:units.append(monster_unit(tm.m,tm.pos))
	for i in fight.party.size():units.append(woman_unit(fight.party[i],i))
	for u in units:
		finish_unit(u)
		u.charge=float(u.full)*clampf(float(u.mods.get("start_charge",0.0)),0,1)
		stats[u.id]={"dealt":0,"taken":0,"casts":0,"whiffs":0}

func base_unit(id: int,side: String) -> Dictionary:
	return {"id":id,"side":side,"alive":true,"charge":0.0,"shield":0,"mods":{},"flags":[],
		"status":{"hidden":0.0,"haste":0.0,"bind":0.0,"slow":0.0,"stun":0.0,"weak":0.0,"weak_p":0.0,"taunt":0.0,"taunt_by":-1,"guard":0.0,"poison":0.0,"poison_v":0,"last_stand":0,"bound_by":-1,"bound_for":0.0},
		"used":{"first":false,"evade":false,"stand":false}}

func monster_unit(m: Dictionary,cell) -> Dictionary:
	var u: Dictionary=base_unit(units.size(),"m")
	var sp: Dictionary=G.db.species[str(m.species)]
	u.ref=int(m.uid);u.name=str(m.name);u.kind=str(m.species);u.cell=cell
	u.mods=mods_of(Stats.passives(m))
	u.st={}
	for k in STATS:u.st[k]=float(m.stats[k])*(1.0+float(u.mods.get(k+"_pct",0.0)))
	u.max=Stats.hp_max(m);u.hp=clampi(int(m.hp),0,u.max)
	u.alive=u.hp>0
	u.atk=float(sp.atk);u.range=int(sp.range)+int(u.mods.get("reach",0));u.move=int(sp.move)+int(u.mods.get("move",0))
	u.skill=str(sp.active);u.ai=str(sp.get("ai","monster"))
	u.magic=str(m.species) in MAGIC_SPECIES or bool(sp.get("magic",false))
	return u

## 雑兵（名前のない兵。スキルもパッシブも持たない）。
func minion_unit(spec: Dictionary,cell) -> Dictionary:
	var u: Dictionary=base_unit(units.size(),"m")
	u.ref=-1;u.name=str(spec.get("name","雑兵"));u.kind="minion";u.cell=cell;u.minion=true
	u.st={}
	for k in STATS:u.st[k]=float(spec.stats[k])
	u.max=int(round(float(spec.hp_base)+u.st.end*float(bal.hp.per_end)));u.hp=u.max
	u.atk=float(spec.atk);u.range=1;u.move=1
	u.skill="";u.ai="monster";u.magic=false
	return u

func woman_unit(mem: Dictionary,index: int) -> Dictionary:
	var u: Dictionary=base_unit(units.size(),"w")
	var jd: Dictionary=G.db.jobs[str(mem.job)]
	u.ref=index;u.name=str(mem.name);u.kind=str(mem.job);u.cell=mem.pos
	u.st={}
	for k in STATS:u.st[k]=float(mem.stats[k])
	var named: String=str(mem.get("named",""))
	var mul: float=float(G.db.women[named].get("hp_mul",1.0)) if named!="" else 1.0
	u.max=int(round((float(jd.hp_base)+u.st.end*float(bal.hp.per_end))*mul));u.hp=u.max
	u.atk=float(jd.atk);u.range=int(jd.range);u.move=int(jd.move)
	u.skill=str(G.db.women[named].unique) if named!="" else str(jd.get("skill",""))
	u.ai=str(jd.ai);u.flags=jd.get("flags",[]).duplicate();u.named=named
	u.mods=mods_of([]);u.mods.merge(jd.get("mods",{}),true)
	u.magic=u.ai in ["caster","healer"]
	return u

## 位置・速さ・射程・攻撃の間隔を決める（マスの中心に立たせる）。
func finish_unit(u: Dictionary) -> void:
	u.pos=Vector2(u.cell)+Vector2(0.5,0.5)
	u.face=Vector2(1,0) if u.side=="m" else Vector2(-1,0)
	var sp: float=float(u.st.spd)
	u.speed=(float(bal.move.base)+float(u.move)*float(bal.move.per_move))*(1.0+(sp-50.0)*float(bal.move.per_spd))
	u.reach=float(u.range)+REACH_PAD
	u.interval=float(bal.attack.interval)/maxf(0.4,1.0+(sp-50.0)*float(bal.attack.per_spd))/(1.0+float(u.mods.get("atk_speed",0.0)))
	u.full=float(G.db.skill(u.skill).get("charge",bal.charge.full)) if u.skill!="" else float(bal.charge.full)
	u.status.hidden=float(u.mods.get("start_hidden",0.0))
	u.cd=float(bal.attack.first_delay)
	u.swing=-1.0;u.swing_t=-1;u.lock=0.0;u.think=0.0;u.target=-1;u.moving=false
	u.forced=-1;u.forced_t=0.0
	if not u.has("minion"):u.minion=false

static func mods_of(ids: Array) -> Dictionary:
	var out: Dictionary={}
	for id in ids:
		var m: Dictionary=G.db.skills.get(id,{}).get("mods",{})
		for k in m:
			if m[k] is Dictionary:out[k]=m[k]
			elif k=="charge_mul":out[k]=float(out.get(k,1.0))*float(m[k])
			else:out[k]=float(out.get(k,0.0))+float(m[k])
	return out

# ───────── 引き ─────────
func unit(id: int) -> Dictionary:
	return units[id] if id>=0 and id<units.size() else {}

func unit_of_monster(uid: int) -> Dictionary:
	for u in units:
		if u.side=="m" and int(u.ref)==uid:return u
	return {}

func alive(side: String) -> Array:
	return units.filter(func(u):return u.alive and u.side==side)

## 魔物（雑兵を除く）で生きている者。
func alive_monsters() -> Array:
	return units.filter(func(u):return u.alive and u.side=="m" and not u.minion)

func foes(u: Dictionary) -> Array:
	return alive("w" if u.side=="m" else "m")

func friends(u: Dictionary) -> Array:
	return alive(u.side)

## 1秒あたりの溜まり。
func charge_rate(u: Dictionary) -> float:
	return (float(bal.charge.base)+float(u.st.spd)*float(bal.charge.per_spd))*float(u.mods.get("charge_mul",1.0))

func ready(u: Dictionary) -> bool:
	return u.alive and u.skill!="" and float(u.charge)>=float(u.full)

## 姿を隠している者は狙われない（全員隠れていれば別）。
func visible(list: Array) -> Array:
	var out: Array=list.filter(func(x):return float(x.status.hidden)<=0)
	return out if not out.is_empty() else list

func ratio(u: Dictionary) -> float:
	return float(u.hp)/maxf(1.0,float(u.max))

func dist(a: Dictionary,b: Dictionary) -> float:
	return (a.pos as Vector2).distance_to(b.pos)

## 近い順（同じなら体力の割合が低い方、次に番号）。
func nearest(u: Dictionary,list: Array) -> Dictionary:
	var best: Dictionary={};var key:=[]
	for x in list:
		var k: Array=[snappedf(dist(u,x),0.001),ratio(x),x.id]
		if best.is_empty() or k<key:best=x;key=k
	return best

## 相手の側の一番奥（魔物は左に並ぶので x が小さい方、一行は x が大きい方）。
func farthest_back(u: Dictionary,list: Array) -> Dictionary:
	var best: Dictionary={};var key:=[]
	for x in list:
		var back: float=float(x.pos.x) if u.side=="w" else -float(x.pos.x)
		var k: Array=[snappedf(back,0.001),snappedf(dist(u,x),0.001),x.id]
		if best.is_empty() or k<key:best=x;key=k
	return best

# ───────── 号令 ─────────
## 画面から：号令を出す（次の刻みで効く）。出せたら true。
func order(kind: String,target: int=-1) -> bool:
	if done or orders_left<=0 or not kind in ["focus","rally"]:return false
	if kind=="focus":
		var tg: Dictionary=unit(target)
		if tg.is_empty() or not tg.alive or tg.side!="w":return false
	orders.append({"tick":ticks+1,"kind":kind,"target":target});orders_left-=1
	return true

func apply_order(o: Dictionary) -> void:
	var ob: Dictionary=bal.get("orders",{})
	match str(o.kind):
		"focus":
			var tg: Dictionary=unit(int(o.target))
			if tg.is_empty() or not tg.alive:return
			for u in alive("m"):u.forced=tg.id;u.forced_t=float(ob.get("focus_secs",6));u.think=0.0
			ev({"k":"order","kind":"focus","t":tg.id});note(-1,"号令：%sを狙え"%tg.name,"m")
		"rally":
			for u in alive("m"):
				u.status.haste=maxf(float(u.status.haste),float(ob.get("rally_secs",4)))
				if u.skill!="":u.charge=minf(float(u.full),float(u.charge)+float(ob.get("rally_charge",30)))
			ev({"k":"order","kind":"rally"});note(-1,"号令：押し込め","m")

# ───────── 進める ─────────
func run_all() -> Dictionary:
	while not done:step()
	return result()

func step() -> void:
	if done:return
	ticks+=1;t=ticks*TICK
	events=[]
	for o in orders:
		if int(o.tick)==ticks:apply_order(o)
	for u in units:
		if u.alive and u.skill!="":u.charge=minf(float(u.full),float(u.charge)+charge_rate(u)*TICK)
	for u in units:
		if done:break
		if u.alive:act(u,TICK)
		check_end()
	if not done:
		separate()
		fly(TICK)
		second_acc+=TICK
		if second_acc>=1.0-1e-6:
			second_acc-=1.0
			each_second()
	check_end()
	if not done and t>=cap-1e-6:
		done=true;won=false
		note(-1,"時間切れ（負け）","")

func check_end() -> void:
	if done:return
	if alive("w").is_empty():done=true;won=true;note(-1,"一行が全員倒れた（勝ち）","")
	elif alive_monsters().is_empty():done=true;won=false;note(-1,"魔物が全員倒れた（負け）","")

## 1人の1刻み。
func act(u: Dictionary,dt: float) -> void:
	var s: Dictionary=u.status
	u.moving=false
	for k in ["weak","taunt","guard"]:
		if float(s[k])>0:s[k]=maxf(0.0,float(s[k])-dt)
	if float(u.forced_t)>0:u.forced_t=float(u.forced_t)-dt
	if float(s.weak)<=0:s.weak_p=0.0
	var slowed: bool=float(s.slow)>0
	if slowed:s.slow=maxf(0.0,float(s.slow)-dt)
	var hasted: bool=float(s.haste)>0
	if hasted:s.haste=maxf(0.0,float(s.haste)-dt)
	if float(s.hidden)>0:s.hidden=maxf(0.0,float(s.hidden)-dt)
	var pace: float=(0.5 if slowed else 1.0)*(float(bal.attack.haste) if hasted else 1.0)
	u.cd=maxf(0.0,float(u.cd)-dt*pace)
	if float(s.stun)>0:
		s.stun=maxf(0.0,float(s.stun)-dt);u.swing=-1.0
		return
	if float(s.bind)>0:
		s.bound_for=float(s.bound_for)+dt
		if "tear" in u.flags and float(s.bound_for)>=TEAR_AFTER:
			s.bind=0.0;s.bound_for=0.0
			ev({"k":"tear","u":u.id});note(u.id,"%sが縛りを引きちぎった"%u.name,u.side)
		else:
			s.bind=maxf(0.0,float(s.bind)-dt)
			if float(s.bind)<=0:s.bound_for=0.0
			u.swing=-1.0
			return
	# 技を撃った直後の構え
	if float(u.lock)>0:
		u.lock=float(u.lock)-dt
		return
	# 振りかぶり中（当たるまで動かない）
	if float(u.swing)>=0:
		u.swing=float(u.swing)-dt*pace
		if float(u.swing)<=0:
			u.swing=-1.0
			release_swing(u)
		return
	# スキル（溜まったら自動）
	if ready(u) and try_skill(u):return
	# 神官：縛られた仲間を解きに行く
	if u.ai=="healer":
		var tied: Array=friends(u).filter(func(f):return f.id!=u.id and float(f.status.bind)>0)
		if not tied.is_empty():
			var f: Dictionary=nearest(u,tied)
			if dist(u,f)<=1.0+REACH_PAD:
				if float(u.cd)<=0:
					f.status.bind=0.0;f.status.bound_for=0.0;u.cd=u.interval
					u.face=(f.pos-u.pos).normalized()
					ev({"k":"unbind","u":u.id,"t":f.id});note(u.id,"%sが%sの縛りを解いた"%[u.name,f.name],u.side)
				return
			move_to(u,f.pos,1.0,dt,pace);return
	# 狙い
	u.think=float(u.think)-dt
	var tg: Dictionary=unit(int(u.target))
	if float(u.think)<=0 or tg.is_empty() or not tg.alive:
		tg=pick_target(u);u.target=int(tg.get("id",-1));u.think=THINK
	if tg.is_empty():return
	var d: float=dist(u,tg)
	# 射程2以上の者は、詰められたら少し下がる（攻撃の合間だけ）
	if int(u.range)>=2 and float(u.cd)>0.25:
		var close: Dictionary=nearest(u,foes(u))
		if not close.is_empty() and dist(u,close)<1.2:
			var away: Vector2=u.pos+(u.pos-close.pos).normalized()*2.0
			move_to(u,away,0.0,dt,pace*0.7)
			return
	# 騎士：後衛（術・回復）を守る。後衛に寄る敵がいなければ、後衛と敵の間に立つ
	if u.ai=="guard" and float(u.status.taunt)<=0 and float(u.forced_t)<=0:
		var ward: Dictionary=ward_of(u)
		if not ward.is_empty():
			var threat: Dictionary=nearest(ward,visible(foes(u)))
			if not threat.is_empty():
				if dist(ward,threat)<3.0 or dist(u,threat)<=float(u.reach):
					tg=threat;u.target=tg.id;d=dist(u,tg)
				else:
					var post: Vector2=ward.pos+(threat.pos-ward.pos).normalized()*1.0
					move_to(u,post,0.25,dt,pace)
					return
	# 回り込む者：遠いうちは近い方の端を通って、狙いの横へ出る
	if u.ai=="flank" and d>3.0:
		var edge: float=0.6 if u.pos.y<field.h*0.5 else field.h-0.6
		if absf(u.pos.x-tg.pos.x)>1.5 and absf(u.pos.y-edge)>0.4:
			move_to(u,Vector2(lerpf(u.pos.x,tg.pos.x,0.35),edge),0.2,dt,pace)
			return
	if d<=float(u.reach) and field.clear_line(u.pos,tg.pos):
		u.face=(tg.pos-u.pos).normalized()
		if float(u.cd)<=0:
			u.swing=float(bal.attack.windup);u.swing_t=tg.id;u.cd=u.interval;u.status.hidden=0.0
			ev({"k":"attack","u":u.id,"t":tg.id})
		return
	move_to(u,tg.pos,float(u.reach)*0.85,dt,pace)

## 振りかぶりが終わった：近くなら当て、遠くの者は矢・術を飛ばす。狙いが射程から大きく離れていたら空振り。
func release_swing(u: Dictionary) -> void:
	var tg: Dictionary=unit(int(u.swing_t))
	if tg.is_empty() or not tg.alive:return
	if dist(u,tg)>float(u.reach)+0.6:
		ev({"k":"swing_miss","u":u.id});return
	var dmg: int=attack_damage(u,tg)
	if int(u.range)>=2:
		shot_seq+=1
		projectiles.append({"id":shot_seq,"src":u.id,"to":tg.id,"pos":u.pos,"dmg":dmg,"magic":bool(u.magic),"side":u.side})
		ev({"k":"shot","u":u.id,"t":tg.id,"id":shot_seq})
	else:
		land_attack(u,tg,dmg)

# ───────── 狙い ─────────
## 騎士が守る後衛（術・回復のうち、体力の割合が低い方）。
func ward_of(u: Dictionary) -> Dictionary:
	var best: Dictionary={};var key:=[]
	for f in friends(u):
		if f.id==u.id or not f.ai in ["caster","healer"]:continue
		var k: Array=[ratio(f),f.id]
		if best.is_empty() or k<key:best=f;key=k
	return best

func pick_target(u: Dictionary) -> Dictionary:
	if float(u.forced_t)>0:
		var fc: Dictionary=unit(int(u.forced))
		if not fc.is_empty() and fc.alive:return fc
	if float(u.status.taunt)>0:
		var tb: Dictionary=unit(int(u.status.taunt_by))
		if not tb.is_empty() and tb.alive:return tb
	var list: Array=visible(foes(u))
	if list.is_empty():return {}
	if u.ai=="flank":return farthest_back(u,list)
	return nearest(u,list)

## 自動のスキルの的（射程に的がいないときは撃たない）。
func ai_skill_target(u: Dictionary) -> Dictionary:
	var s: Dictionary=G.db.skill(u.skill)
	var kind: String=str(s.get("target","enemy"))
	if kind=="self":return {}
	var rg: float=Sk.reach(s,u.st)+REACH_PAD
	var pool: Array=friends(u) if kind=="ally" else foes(u)
	var cands: Array=pool.filter(func(x):return dist(u,x)<=rg and field.clear_line(u.pos,x.pos))
	if kind!="ally":cands=visible(cands)
	if cands.is_empty():return {}
	if kind=="ally":
		var low: Dictionary={};var lk:=[]
		for x in cands:
			var k0: Array=[ratio(x),x.id]
			if low.is_empty() or k0<lk:low=x;lk=k0
		return low
	if str(s.get("pick",""))=="far":return farthest_back(u,cands)
	if str(s.get("pick",""))=="weak":
		var weak: Dictionary={};var wk:=[]
		for x in cands:
			var k1: Array=[ratio(x),x.id]
			if weak.is_empty() or k1<wk:weak=x;wk=k1
		return weak
	var bonus: int=int(u.mods.get("area_bonus",0))
	var best: Dictionary={};var key:=[]
	for x in cands:
		var n: int=foes(u).filter(func(f):return Sk.in_area(s,x.pos,u.pos,bonus,f.pos) or f.id==x.id).size()
		var k: Array=[-n,ratio(x),x.id]
		if best.is_empty() or k<key:best=x;key=k
	return best

func self_skill_useful(u: Dictionary) -> bool:
	var s: Dictionary=G.db.skill(u.skill)
	var bonus: int=int(u.mods.get("area_bonus",0))
	var heals: bool=s.effects.any(func(e):return str(e.t) in ["heal","cleanse"]) and not s.effects.any(func(e):return str(e.t)=="damage" and str(e.get("to","enemy"))=="enemy")
	if heals:
		return friends(u).any(func(f):return Sk.in_area(s,u.pos,u.pos,bonus,f.pos) and (ratio(f)<0.75 or float(f.status.bind)>0))
	return foes(u).any(func(f):return Sk.in_area(s,u.pos,u.pos,bonus,f.pos) or dist(u,f)<=2.2)

func try_skill(u: Dictionary) -> bool:
	var s: Dictionary=G.db.skill(u.skill)
	if s.is_empty():return false
	if str(s.get("target","enemy"))=="self":
		if not self_skill_useful(u):return false
		cast(u,s,u.pos,{})
		return true
	var tg: Dictionary=ai_skill_target(u)
	if tg.is_empty():return false
	cast(u,s,tg.pos,tg)
	return true

# ───────── 動く ─────────
## goal へ向かう（stop の距離まで近づいたら止まる）。崖で見通しが切れていれば、マスの道を探して回り込む。
func move_to(u: Dictionary,goal: Vector2,stop: float,dt: float,pace: float) -> void:
	var d: float=u.pos.distance_to(goal)
	if d<=stop:return
	var way: Vector2=goal
	if not field.clear_line(u.pos,goal):way=field.waypoint(u.pos,goal)
	var dir: Vector2=way-u.pos
	if dir.length()<1e-4:return
	dir=dir.normalized()
	var sp: float=float(u.speed)*pace
	if field.tile(Field.cell_of(u.pos))=="~":sp*=0.5
	u.pos=u.pos+dir*minf(sp*dt,d-stop)
	u.face=dir;u.moving=true
	field.keep_inside(u,RADIUS)

## 重なった者どうしを押し離す（番号の順。同じ入力なら同じ結果）。
func separate() -> void:
	var live: Array=units.filter(func(u):return u.alive)
	for i in live.size():
		for j in range(i+1,live.size()):
			var a: Dictionary=live[i];var b: Dictionary=live[j]
			var d: Vector2=b.pos-a.pos
			var l: float=d.length()
			var need: float=RADIUS*2.0
			if l>=need:continue
			var n: Vector2=d/l if l>1e-5 else Vector2(1,0).rotated(float(a.id*7+b.id)*0.9)
			# 縛られ・気絶している者は押されにくい
			var wa: float=0.2 if float(a.status.bind)>0 or float(a.status.stun)>0 else 1.0
			var wb: float=0.2 if float(b.status.bind)>0 or float(b.status.stun)>0 else 1.0
			var push: float=need-l
			a.pos=a.pos-n*push*wa/(wa+wb)
			b.pos=b.pos+n*push*wb/(wa+wb)
	for u in live:field.keep_inside(u,RADIUS)

## 飛び道具を進め、届いたら当てる（狙いが倒れていたら消える）。
func fly(dt: float) -> void:
	var keep: Array=[]
	for p in projectiles:
		var tg: Dictionary=unit(int(p.to))
		if tg.is_empty() or not tg.alive:continue
		var d: Vector2=tg.pos-p.pos
		var step: float=SHOT_SPEED*dt
		if d.length()<=step+RADIUS*0.5:
			land_attack(unit(int(p.src)),tg,int(p.dmg))
			ev({"k":"shot_hit","id":int(p.id),"t":tg.id})
		else:
			p.pos=p.pos+d.normalized()*step
			keep.append(p)
	projectiles=keep

## 1秒ごと：再生・毒・締め上げ。
func each_second() -> void:
	for u in units:
		if not u.alive:continue
		var rg: float=float(u.mods.get("regen",0.0))
		if rg>0 and u.hp<u.max:heal(u,u,rg,false)
		var aura: float=float(u.mods.get("aura_heal",0.0))
		if aura>0:
			for f in friends(u):
				if dist(u,f)<=2.5 and f.hp<f.max:heal(u,f,aura,false)
		if float(u.status.poison)>0:
			u.status.poison=maxf(0.0,float(u.status.poison)-1.0)
			hurt({},u,int(u.status.poison_v),false)
		if float(u.status.bind)>0:
			var b: Dictionary=unit(int(u.status.bound_by))
			if not b.is_empty() and b.alive and b.mods.has("bind_tick"):
				hurt(b,u,int(round(Sk.value(b.mods.bind_tick,b.st))),false)

# ───────── 攻撃・痛手 ─────────
func attack_damage(u: Dictionary,tg: Dictionary) -> int:
	var dmg: float
	if u.magic:dmg=u.atk+float(u.st.mag)*float(bal.damage.str)-float(tg.st.mag)*float(bal.damage.mag_def)
	else:dmg=u.atk+float(u.st.str)*float(bal.damage.str)-float(tg.st.end)*float(bal.damage.end)
	if float(u.mods.get("first_strike",0))>0 and not u.used.first:dmg*=2.0;u.used.first=true
	dmg*=1.0-float(u.status.weak_p)
	if dist(u,tg)>1.3 and field.tile(Field.cell_of(tg.pos))=="\"":dmg*=0.5
	return maxi(1,int(round(dmg)))

## 通常攻撃が当たった（痛手と、当てたときの効き目・薙ぎ）。
func land_attack(u: Dictionary,tg: Dictionary,dmg: int) -> void:
	if not tg.alive:return
	var dealt: int=hurt(u,tg,dmg,true,bool(u.get("magic",false)))
	if u.is_empty():return
	if tg.alive and dealt>0:
		if float(u.mods.get("on_hit_slow",0))>0:tg.status.slow=maxf(float(tg.status.slow),float(u.mods.on_hit_slow))
		if float(u.mods.get("on_hit_weak",0))>0:
			tg.status.weak=maxf(float(tg.status.weak),2.0);tg.status.weak_p=maxf(float(tg.status.weak_p),float(u.mods.on_hit_weak))
		if float(u.mods.get("on_hit_poison",0))>0:tg.status.poison=2.0;tg.status.poison_v=int(u.mods.on_hit_poison)
	if float(u.mods.get("cleave",0))>0:
		for f in foes(u):
			if f.id!=tg.id and dist(f,tg)<=1.2:hurt(u,f,maxi(1,int(round(dmg*float(u.mods.cleave)))),true)

## 痛手を与える（かばう・残像・守り・盾・踏みとどまる・棘・吸精）。実際に減った体力を返す。magic の痛手は守り（armor）を抜ける。
func hurt(src: Dictionary,tg: Dictionary,amount: int,is_attack: bool,magic: bool=false) -> int:
	if not tg.alive:return 0
	var to: Dictionary=tg
	if is_attack and not src.is_empty():
		for g in friends(tg):
			if g.id!=tg.id and float(g.status.guard)>0 and dist(g,tg)<=1.2:to=g;break
	if is_attack and float(to.mods.get("evade_first",0))>0 and not to.used.evade:
		to.used.evade=true
		ev({"k":"evade","t":to.id});return 0
	var dmg: int=maxi(1,int(round((amount-(0 if magic else int(to.mods.get("armor",0))))*scale))) if is_attack else maxi(1,int(round(amount*scale)))
	if int(to.shield)>0:
		var ab: int=mini(int(to.shield),dmg);to.shield=int(to.shield)-ab;dmg-=ab
	if dmg<=0:ev({"k":"block","t":to.id});return 0
	to.hp=int(to.hp)-dmg
	if not src.is_empty():stats[src.id].dealt=int(stats[src.id].dealt)+dmg
	stats[to.id].taken=int(stats[to.id].taken)+dmg
	ev({"k":"hit","t":to.id,"dmg":dmg,"from":src.get("id",-1)})
	if to.hp<=0:
		var stand: bool=(float(to.mods.get("last_stand",0))>0 or int(to.status.last_stand)>0) and not to.used.stand
		if stand:
			to.hp=1;to.used.stand=true;to.status.last_stand=0
			ev({"k":"stand","t":to.id});note(to.id,"%sが踏みとどまった"%to.name,to.side)
		else:
			to.hp=0;to.alive=false;to.swing=-1.0;to.moving=false
			ev({"k":"down","t":to.id});note(to.id,"%sが倒れた"%to.name,to.side)
			if not src.is_empty() and src.alive and float(src.mods.get("kill_charge",0))>0:
				src.charge=minf(float(src.full),float(src.charge)+float(src.mods.kill_charge))
	if is_attack and not src.is_empty() and src.alive:
		var th: float=float(to.mods.get("thorns",0))
		if th>0 and dist(src,to)<=1.6:hurt(to,src,maxi(1,int(round(dmg*th))),false)
		var ls: float=float(src.mods.get("lifesteal",0))
		if ls>0:heal(src,src,dmg*ls/maxf(scale,0.01),false)  # dmg は倍率を掛けた後の値
	return dmg

func heal(src: Dictionary,tg: Dictionary,amount: float,show: bool=true) -> void:
	if not tg.alive:return
	for f in foes(tg):
		if float(f.mods.get("anti_heal",0))>0 and dist(f,tg)<=2.5:amount*=0.5;break
	var n: int=mini(int(round(amount*scale)),int(tg.max)-int(tg.hp))
	if n<=0:return
	tg.hp=int(tg.hp)+n
	if show:ev({"k":"heal","t":tg.id,"amt":n})

# ───────── スキル ─────────
func cast(u: Dictionary,s: Dictionary,center: Vector2,tgt: Dictionary) -> void:
	u.charge=0.0;u.lock=float(bal.attack.cast_lock);u.swing=-1.0;u.status.hidden=0.0
	stats[u.id].casts=int(stats[u.id].casts)+1
	if not tgt.is_empty() and tgt.id!=u.id:u.face=(tgt.pos-u.pos).normalized()
	var bonus: int=int(u.mods.get("area_bonus",0))
	var single: bool=str(s.get("area",{}).get("shape","single"))=="single"
	var enemies: Array
	var allies: Array
	if single:
		enemies=[tgt] if not tgt.is_empty() and tgt.side!=u.side else []
		allies=[tgt] if not tgt.is_empty() and tgt.side==u.side else []
	else:
		enemies=foes(u).filter(func(x):return Sk.in_area(s,center,u.pos,bonus,x.pos))
		allies=friends(u).filter(func(x):return Sk.in_area(s,center,u.pos,bonus,x.pos))
	var limit: int=int(s.get("max",0))
	if limit>0:
		limit+=int(u.mods.get("skill_targets",0))
		enemies.sort_custom(func(a,b):return [0 if a.id==tgt.get("id",-1) else 1,snappedf(a.pos.distance_to(center),0.001),a.id]<[0 if b.id==tgt.get("id",-1) else 1,snappedf(b.pos.distance_to(center),0.001),b.id])
		enemies=enemies.slice(0,limit)
	var sb: float=float(u.mods.get("status_bonus",0))
	var hit_any:=false
	ev({"k":"cast","u":u.id,"skill":str(s.get("name","")),"id":str(u.skill),"area":Sk.area_shape(s,center,u.pos,bonus),"t":tgt.get("id",-1)})
	note(u.id,"%sの%s"%[u.name,str(s.get("name",""))],u.side)
	for e in s.effects:
		var to: String=str(e.get("to","enemy"))
		var list: Array=[u] if to=="self" else (allies if to=="ally" else enemies)
		list=list.filter(func(x):return x.alive)
		if str(e.t)=="jump":
			if not tgt.is_empty() and tgt.alive:
				var from: Vector2=u.pos
				var back: Vector2=(u.pos-tgt.pos)
				if back.length()<1e-4:back=Vector2(-1,0) if u.side=="m" else Vector2(1,0)
				u.pos=tgt.pos+back.normalized()*(RADIUS*2.0+0.05)
				field.keep_inside(u,RADIUS)
				ev({"k":"jump","u":u.id,"from":from,"to":u.pos})
			continue
		for x in list:
			match str(e.t):
				"damage":
					var v: float=Sk.value(e.v,u.st)
					var d: float
					if str(e.get("kind","phys"))=="magic":d=v-float(x.st.mag)*float(bal.damage.mag_def)
					else:d=v-float(x.st.end)*float(bal.damage.end)
					d*=1.0-float(u.status.weak_p)
					var ex=e.get("execute",null)
					if ex is Dictionary and ratio(x)<float(ex.get("below",0.0)):d*=float(ex.get("mul",1.0))
					hurt(u,x,maxi(1,int(round(d))),true,str(e.get("kind","phys"))=="magic");hit_any=true
					# 吹き飛ばし（範囲の中心・使い手から離れる向きへ）
					var kb: float=float(s.get("knock",0.3 if not single else 0.15))
					if kb>0 and x.alive and x.id!=u.id:
						var from_p: Vector2=center if not single else u.pos
						var dir: Vector2=x.pos-from_p
						if dir.length()<1e-4:dir=x.pos-u.pos
						if dir.length()>1e-4:
							x.pos=x.pos+dir.normalized()*kb;field.keep_inside(x,RADIUS);x.swing=-1.0
							ev({"k":"knock","t":x.id})
				"heal":heal(u,x,Sk.value(e.v,u.st))
				"shield":
					x.shield=int(x.shield)+int(round(Sk.value(e.v,u.st)*scale))
					ev({"k":"shield","t":x.id})
				"cleanse":
					for k in ["bind","slow","stun","weak","poison"]:x.status[k]=0.0
					x.status.weak_p=0.0;x.status.bound_for=0.0
				"drain_charge":
					x.charge=maxf(0.0,float(x.charge)-Sk.value(e.v,u.st));hit_any=true
				"status":
					var dur: float=Sk.value(e.get("dur",1),u.st)
					if to!="self":dur+=sb
					apply_status(u,x,str(e.status),dur,Sk.value(e.get("power",0.0),u.st))
					if to=="enemy":hit_any=true
	if not hit_any and s.effects.any(func(e):return str(e.get("to","enemy"))=="enemy"):
		stats[u.id].whiffs=int(stats[u.id].whiffs)+1
		ev({"k":"whiff","u":u.id})

## 効き目をかける。長さは秒。
func apply_status(src: Dictionary,tg: Dictionary,st: String,dur: float,power: float) -> void:
	if not tg.alive or dur<=0:return
	var s: Dictionary=tg.status
	match st:
		"bind":
			if "slippery" in tg.flags:dur*=0.5
			s.bind=maxf(float(s.bind),dur);s.bound_by=src.id;s.bound_for=0.0;tg.swing=-1.0
		"slow":s.slow=maxf(float(s.slow),dur)
		"stun":s.stun=maxf(float(s.stun),dur);tg.swing=-1.0
		"weak":s.weak=maxf(float(s.weak),dur);s.weak_p=clampf(maxf(float(s.weak_p),power),0.0,0.8)
		"taunt":s.taunt=dur;s.taunt_by=src.id;tg.think=0.0
		"guard":s.guard=dur
		"haste":s.haste=maxf(float(s.haste),dur)
		"last_stand":s.last_stand=1
	ev({"k":"status","t":tg.id,"s":st,"dur":dur})

# ───────── 記録 ─────────
func ev(e: Dictionary) -> void:
	e.time=t
	events.append(e)

func note(id: int,text: String,side: String) -> void:
	logs.append({"time":t,"text":text,"side":side,"u":id})

## 結果：勝ち負け、かかった秒、倒れた女（一行の並びの番号）、魔物の残りの体力、1人ずつの記録。
func result() -> Dictionary:
	var down: Array=[]
	var hp: Dictionary={}
	for u in units:
		if u.side=="w" and not u.alive:down.append(int(u.ref))
		if u.side=="m" and not u.minion:hp[int(u.ref)]=int(u.hp)
	var per: Array=[]
	for u in units:per.append({"minion":bool(u.minion),"name":u.name,"side":u.side,"alive":u.alive,"hp":int(u.hp),"max":int(u.max),"dealt":int(stats[u.id].dealt),"taken":int(stats[u.id].taken),"casts":int(stats[u.id].casts),"whiffs":int(stats[u.id].whiffs)})
	return {"won":won,"secs":snappedf(t,0.01),"down":down,"hp":hp,"units":per,"log":logs.duplicate(),"orders":orders.duplicate(true)}

## 決定性の確かめ用：盤の様子を1行にする。
func signature() -> String:
	var parts: Array=[str(ticks)]
	for u in units:parts.append("%d:%.4f,%.4f:%d:%.3f"%[u.id,u.pos.x,u.pos.y,int(u.hp),float(u.charge)])
	return "|".join(parts)
