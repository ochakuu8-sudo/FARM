extends RefCounted
## 女・一行の者・魔物の記録を作る（設計書 2.2・3.2）。乱数はすべて rng() で、保存の種と用途から作る。
const G=preload("res://game/core/g.gd")
const Parts=preload("res://game_v2/animation/parts.gd")
const STATS:=["str","mag","spd","end"]

## 決まった種から乱数を作る。同じ parts なら毎回同じ並びになる。
static func rng(parts: Array) -> RandomNumberGenerator:
	var r:=RandomNumberGenerator.new()
	r.seed=hash(parts)
	return r

static func pick_weighted(weights: Array,r: RandomNumberGenerator) -> int:
	var total:=0.0
	for w in weights:total+=float(w)
	if total<=0.0:return 0
	var x:=r.randf()*total
	for i in weights.size():
		x-=float(weights[i])
		if x<0:return i
	return weights.size()-1

static func pick_key(weights: Dictionary,r: RandomNumberGenerator) -> String:
	var keys: Array=weights.keys()
	keys.sort()
	var ws: Array=[]
	for k in keys:ws.append(weights[k])
	return str(keys[pick_weighted(ws,r)])

static func zero_stats() -> Dictionary:
	return {"str":0.0,"mag":0.0,"spd":0.0,"end":0.0}

static func stat_sum(s: Dictionary) -> float:
	var t:=0.0
	for k in STATS:t+=float(s.get(k,0))
	return t

## 能力の合計から★（設計書 3.2）。
static func star_of(stats: Dictionary) -> int:
	var th: Array=G.db.balance.star_sum
	var s: float=stat_sum(stats)
	var star:=1
	for t in th:
		if s>=float(t):star+=1
	return clampi(star,1,5)

static func eggs_for(star: int) -> int:
	var b: Array=G.db.balance.eggs
	return int(b[clampi(star,1,5)-1])

# ───────── 一行の女 ─────────
## 職の部品から見た目を組む。頭は頭の候補（mob_rules の head_pool。画風をそろえた原型）から、ほかの部位は職の候補から（肌の色が合うものだけ）。
static func look(job: String,r: RandomNumberGenerator) -> Dictionary:
	var all: Array=Parts.ids()
	if all.is_empty():return {}
	var heads: Array=G.db.mob.get("head_pool",[]).filter(func(p):return p in all)
	if heads.is_empty():heads=all
	var cand: Array=G.db.jobs[job].get("parts",[]).filter(func(p):return p in all)
	var head: String=heads[r.randi()%heads.size()] if cand.is_empty() or r.randf()<0.6 else cand[r.randi()%cand.size()]
	var pool: Array=cand.filter(func(p):return Parts.same_skin(head,p))
	var out: Dictionary={"head":head}
	for m in Parts.MODULES:
		if m=="head":continue
		if pool.is_empty() or r.randf()<float(G.db.mob.get("parts_same",0.5))*0.5:out[m]=head
		else:out[m]=pool[r.randi()%pool.size()]
	return out

## 名前なしの1人。能力は職の範囲 × power（まれに逸材）。
static func mob_member(job: String,power: float,r: RandomNumberGenerator) -> Dictionary:
	var jd: Dictionary=G.db.jobs[job]
	var names: Array=G.db.mob.names
	var gifted: bool=r.randf()<float(G.db.mob.get("gifted",0.0))
	var mul: float=power*(float(G.db.mob.get("gifted_mul",1.3)) if gifted else 1.0)
	var stats: Dictionary={}
	for k in STATS:
		var rg: Array=jd.stats[k]
		stats[k]=float(clampi(int(round(r.randf_range(float(rg[0]),float(rg[1]))*mul)),1,100))
	var parts: Dictionary=look(job,r)
	return {"job":job,"named":"","name":str(names[r.randi()%names.size()]),"stats":stats,"star":star_of(stats),"gifted":gifted,
		"parts":parts,"hair":Parts.hair(str(parts.get("head","0"))),"weak":STATS[r.randi()%4]}

static func named_member(id: String) -> Dictionary:
	var d: Dictionary=G.db.women[id]
	var stats: Dictionary={}
	for k in STATS:stats[k]=float(d.stats[k])
	return {"job":str(d.job),"named":id,"name":str(d.name),"stats":stats,"star":int(d.star),"gifted":false,
		"parts":d.get("parts",{}),"hair":str(d.get("hair","#604030")),"weak":str(d.weak)}

## 勝って獲得した一行の1人から、捕らえた女の記録を作る。
static func woman_from(member: Dictionary,site: String) -> Dictionary:
	var job: String=str(member.job)
	var star: int=int(member.star)
	var jd: Dictionary=G.db.jobs[job]
	var named: String=str(member.get("named",""))
	var title: String=str(G.db.women[named].title) if named!="" else str(jd.name)
	return {"uid":0,"woman_id":named,"name":str(member.name),"title":title,"job":job,"stats":member.stats.duplicate(),"star":star,
		"weak":str(member.weak),"weak_known":false,"stage":0,"nights":0,"shikomi":zero_stats(),
		"eggs_left":eggs_for(star),"eggs_done":0,"use":"cell","fac":-1,"laying":{},
		"origin":{"day":G.state.day,"site":site},"children":[],"history":[],"gifted":bool(member.get("gifted",false)),
		"profile":"0","parts":member.get("parts",{}),"hair":str(member.get("hair","#604030")),"tint":str(jd.get("tint","")),"props":jd.get("props",{})}

## 手元の女と重ならない名前（名前付きはそのまま）。
static func free_woman_name(name: String,named: String,r: RandomNumberGenerator) -> String:
	if named!="" or G.state==null:return name
	var used: Dictionary={}
	for w in G.state.women:used[str(w.name)]=true
	if not used.has(name):return name
	var names: Array=G.db.mob.names
	for i in 60:
		var n: String=str(names[r.randi()%names.size()])
		if not used.has(n):return n
	return name

# ───────── 魔物 ─────────
static func base_monster(species: String) -> Dictionary:
	return {"uid":0,"name":"","species":species,"grade":-1,"apt":zero_stats(),"stats":zero_stats(),"hp":0,"inherited":[],"wins":0,
		"job":"none","fac":-1,"mother":-1,"father":-1,"generation":0,"tint":"","born_day":0,"mother_name":"","mother_job":"","kin":""}

## 始めから手元にいる魔物。素質は apt の近く、能力は素質の7割。
static func starter(species: String,apt: float,r: RandomNumberGenerator) -> Dictionary:
	var m: Dictionary=base_monster(species)
	for k in STATS:
		m.apt[k]=float(clampi(int(apt)+r.randi_range(-6,6),10,100))
		m.stats[k]=roundf(float(m.apt[k])*0.7)
	m.name=monster_name(r)
	m.born_day=0
	m.hp=hp_max(m)
	return m

## 体力の最大 ＝ 種族の基本 ＋ 耐 × 2（継承の頑健などは戦闘で掛ける）。
static func hp_max(m: Dictionary) -> int:
	var sp: Dictionary=G.db.species.get(str(m.species),{})
	var pct:=0.0
	for id in m.get("inherited",[]):pct+=float(G.db.skills.get(id,{}).get("mods",{}).get("hp_pct",0.0))
	return int(round((float(sp.get("hp_base",40))+float(m.stats.end)*float(G.db.balance.hp.per_end))*(1.0+pct)))

## 名前は手持ちの魔物と重ならないようにする。
static func monster_name(r: RandomNumberGenerator) -> String:
	var pool: Array=G.db.texts.get("monster_names",["ガル","ボグ","ズィグ"])
	var used: Dictionary={}
	if G.state!=null:
		for m in G.state.monsters:used[str(m.name)]=true
	for i in 40:
		var n: String="%s%s"%[str(pool[r.randi()%pool.size()]),"" if (r.randf()<0.7 and i<20) else str(pool[r.randi()%pool.size()])]
		if not used.has(n):return n
	return "%s%d"%[str(pool[r.randi()%pool.size()]),r.randi()%1000]
