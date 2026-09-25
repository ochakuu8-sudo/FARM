extends RefCounted
## 卵（企画書 第7章・設計書 第7章）。出産はすべて卵。産むたびに女の産める数を1つ使う。
##   苗床：種族は父と同じ。素質は母（能力×1.25＋仕込み×1.5、±10%。倍率は balance.apt_mul）。父のパッシブを抽選で継ぐ（2つまで）。
##   召喚陣：種族は母の職（種族）の抽選表。等級（並・良・稀・伝説）で素質の上乗せと生まれつきのパッシブ。天井つき。
const G=preload("res://game/core/g.gd")
const Make=preload("res://game/core/make.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]

static func can_lay(w: Dictionary) -> String:
	if int(w.stage)<2:return "心の段階が「従順」に届いていない"
	if int(w.eggs_left)<=0:return "もう産めない"
	return ""

static func lay_nights() -> int:
	var b: Dictionary=G.db.balance.lay_nights
	return int(b.prologue if G.state.prologue() else b.main)

static func hatch_nights() -> int:
	var b: Dictionary=G.db.balance.hatch_nights
	return int(b.prologue if G.state.prologue() else b.main)

static func altar_cost() -> int:
	return int(G.db.pick(G.db.balance.altar.cost,G.state.chapter))

static func center(w: Dictionary,k: String) -> float:
	var mul: Dictionary=G.db.balance.apt_mul
	return float(w.stats.get(k,0))*float(mul.mother)+float(w.shikomi.get(k,0))*float(mul.shikomi)

## 素質の予想の幅 {k: [低い, 高い]}。bonus は等級の上乗せ。
static func predict_apt(w: Dictionary,bonus: float=0.0) -> Dictionary:
	var s: float=float(G.db.balance.apt_spread)
	var out: Dictionary={}
	for k in STATS:
		var c: float=center(w,k)
		out[k]=[clampf(roundf(c*(1.0-s))+bonus,5,100),clampf(roundf(c*(1.0+s))+bonus,5,100)]
	return out

## 父から継ぐパッシブの候補と確率。
static func inherit_chances(father: Dictionary) -> Array:
	var p: float=float(G.db.balance.inherit_p)
	return Stats.passives(father).map(func(id):return {"skill":id,"p":p})

## 召喚陣で出る種族と確率 [{species, p}]（天井に届いていれば、図鑑にない種族だけ）。
static func altar_table(w: Dictionary) -> Array:
	var st=G.state
	var weights: Dictionary=G.db.jobs[str(w.job)].get("altar",{}).duplicate()
	if int(st.altar_miss)>=int(G.db.balance.altar.pity):
		var fresh: Dictionary={}
		for k in weights:
			if not k in st.unlocked.species:fresh[k]=weights[k]
		if fresh.is_empty():
			for k in G.db.species:
				if not G.db.species[k].has("unique_of") and not k in st.unlocked.species:fresh[k]=1
		if not fresh.is_empty():weights=fresh
	var total:=0.0
	for k in weights:total+=float(weights[k])
	var uniq: String=str(G.db.women.get(str(w.get("woman_id","")),{}).get("species",""))
	var up: float=float(G.db.balance.altar.unique_p) if uniq!="" else 0.0
	var out: Array=[]
	var keys: Array=weights.keys();keys.sort()
	for k in keys:out.append({"species":str(k),"p":(1.0-up)*float(weights[k])/maxf(total,0.001)})
	if uniq!="":out.append({"species":uniq,"p":up})
	return out

## 等級の確率 [並, 良, 稀, 伝説]。★と心の段階で稀以上が出やすい。
static func grade_table(w: Dictionary) -> Array:
	var a: Dictionary=G.db.balance.altar
	var ws: Array=a.grade_weights[clampi(int(w.star),1,5)-1].duplicate()
	var mul: float=1.0+float(w.stage)*float(a.grade_stage)
	ws[2]=float(ws[2])*mul;ws[3]=float(ws[3])*mul
	var total:=0.0
	for x in ws:total+=float(x)
	return ws.map(func(x):return float(x)/maxf(total,0.001))

## 卵を産む（中身はこのとき決まる）。
static func lay(w: Dictionary,kind: String,father: Dictionary) -> Dictionary:
	var st=G.state
	var b: Dictionary=G.db.balance
	var r:=Make.rng([st.seed,"egg",int(w.uid),int(w.eggs_done)])
	var e: Dictionary={"uid":st.uid(),"mother":int(w.uid),"mother_name":str(w.name),"kind":kind,"grade":-1,"apt":{},"inherited":[],
		"father":int(father.get("uid",-1)),"generation":int(father.get("generation",0))+1,"tint":str(w.get("hair","")),
		"hatch_day":st.day+hatch_nights(),"pattern":r.randi()%1000}
	var s: float=float(b.apt_spread)
	var bonus:=0.0
	if kind=="nursery":
		e.species=str(father.species)
		for id in Stats.passives(father):
			if e.inherited.size()>=int(b.inherit_max):break
			if r.randf()<float(b.inherit_p):e.inherited.append(id)
	else:
		var table: Array=altar_table(w)
		var ws: Array=table.map(func(x):return x.p)
		e.species=str(table[Make.pick_weighted(ws,r)].species)
		e.grade=Make.pick_weighted(grade_table(w),r)
		bonus=float(b.altar.grade_bonus[e.grade])
		var rg: Array=b.altar.innate[e.grade]
		var n: int=r.randi_range(int(rg[0]),int(rg[1]))
		var pool: Dictionary={}
		for id in G.db.inherit_pool:pool[id]=float(G.db.inherit_pool[id][e.grade])
		for i in n:
			if pool.is_empty():break
			var id: String=Make.pick_key(pool,r)
			if float(pool[id])<=0.0:break
			e.inherited.append(id);pool.erase(id)
		if str(e.species) in st.unlocked.species:st.altar_miss=int(st.altar_miss)+1
		else:st.altar_miss=0
	for k in STATS:
		var u: float=(r.randf()+r.randf()-1.0)*s
		e.apt[k]=clampf(roundf(center(w,k)*(1.0+u))+bonus,5,100)
	w.eggs_left=int(w.eggs_left)-1
	w.eggs_done=int(w.eggs_done)+1
	w.history.append({"day":st.day,"text":"%sの卵を産んだ"%("召喚陣で抽選" if kind=="altar" else G.db.species_name(str(e.species)))})
	st.eggs.append(e)
	return e

## 孵す。孵った魔物を返す。
static func hatch(e: Dictionary) -> Dictionary:
	var st=G.state
	var m: Dictionary=Make.base_monster(str(e.species))
	m.grade=int(e.grade)
	for k in STATS:
		m.apt[k]=float(e.apt[k])
		m.stats[k]=roundf(float(e.apt[k])*float(G.db.balance.hatch_ratio))
	m.inherited=e.inherited.duplicate()
	m.mother=int(e.mother);m.father=int(e.father);m.generation=int(e.generation)
	var w: Dictionary=st.woman(int(e.mother))
	var order: Array=G.db.texts.get("child_order",["子"])
	var n: int=w.children.size() if not w.is_empty() else 0
	# 名前は見分けやすい短い名前。「〜の長子」は添え書き（kin）に回す。
	m.name=Make.monster_name(Make.rng([st.seed,"name",int(e.uid)]))
	m.kin="%sの%s"%[str(e.mother_name),str(order[mini(n,order.size()-1)])]
	m.mother_name=str(e.mother_name);m.mother_job=str(w.get("job",""))
	m.tint=str(e.tint)
	m.born_day=st.day
	m.hp=Stats.hp_max(m)
	st.add_monster(m)
	if not w.is_empty():w.children.append(int(m.uid))
	st.records.born=int(st.records.born)+1
	st.eggs.erase(e)
	return m
