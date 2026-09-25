extends RefCounted
## 魔物の能力・素質・体力・パッシブ（企画書 5章・設計書 5章）。
##   能力は素質（上限）を越えて伸びない。種族固有のパッシブは能力が条件に届くと開き、継承のパッシブは条件なしで効く。
const G=preload("res://game/core/g.gd")
const Make=preload("res://game/core/make.gd")
const STATS:=["str","mag","spd","end"]

static func species_of(m: Dictionary) -> Dictionary:
	return G.db.species.get(str(m.get("species","")),{})

static func hp_max(m: Dictionary) -> int:
	return Make.hp_max(m)

## 開いている種族固有のパッシブ（今の能力で）。
static func open_passives(m: Dictionary) -> Array:
	var out: Array=[]
	for p in species_of(m).get("passives",[]):
		if G.db.meets(m.stats,p.get("need",{})):out.append(str(p.skill))
	return out

## 効いているパッシブすべて（種族固有＋継承。重なりは1つに）。
static func passives(m: Dictionary) -> Array:
	var out: Array=open_passives(m)
	for id in m.get("inherited",[]):
		if not id in out:out.append(str(id))
	return out

## 種族固有のパッシブの一覧と、開いているか・あといくつか。
static func passive_table(m: Dictionary) -> Array:
	var out: Array=[]
	for p in species_of(m).get("passives",[]):
		var need: Dictionary=p.get("need",{})
		var gap:=0.0
		var reachable:=true
		for k in need:
			gap+=maxf(0.0,float(need[k])-float(m.stats.get(k,0)))
			if float(m.apt.get(k,0))<float(need[k]):reachable=false
		out.append({"skill":str(p.skill),"need":need,"open":gap<=0.0,"gap":gap,"reachable":reachable})
	return out

## 能力を伸ばす（素質まで）。耐が伸びたら体力の最大も今の体力も同じだけ増える。新しく開いたパッシブを返す。
static func grow(m: Dictionary,stat: String,amount: float) -> Array:
	var before: Array=open_passives(m)
	var hp_before: int=hp_max(m)
	var cap: float=float(m.apt.get(stat,0))
	m.stats[stat]=minf(cap,float(m.stats[stat])+amount)
	var hp_after: int=hp_max(m)
	if hp_after>hp_before and int(m.hp)>0:m.hp=int(m.hp)+(hp_after-hp_before)
	var opened: Array=[]
	for id in open_passives(m):
		if not id in before:opened.append(id)
	return opened

## すべての能力が素質に届いているか。
static func maxed(m: Dictionary) -> bool:
	for k in STATS:
		if float(m.stats[k])<float(m.apt[k]):return false
	return true

static func ko(m: Dictionary) -> bool:
	return int(m.hp)<=0

## すぐ全快させるお金（体力0は高い）。
static func heal_cost(m: Dictionary) -> int:
	var b: Dictionary=G.db.balance.heal
	var missing: int=hp_max(m)-int(m.hp)
	if missing<=0:return 0
	return int(ceil(float(missing)*float(b.rate)*(float(b.ko_mult) if ko(m) else 1.0)))

static func heal_now(m: Dictionary) -> bool:
	var cost: int=heal_cost(m)
	if cost<=0 or not G.state.pay({"money":cost}):return false
	m.hp=hp_max(m)
	return true

## 戦闘に出せるか（体力が残っている）。
static func can_fight(m: Dictionary) -> bool:
	return int(m.hp)>0

static func power(m: Dictionary) -> float:
	return Make.stat_sum(m.stats)
