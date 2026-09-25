extends RefCounted
## セーブの中身のすべて（設計書 2.2）。値は辞書と配列だけで持ち、そのまま JSON に書ける。
## 牧場のマスは文字列（1マス1文字。0 岩・1 床）で持つ。牧場は掘らない（決まった広さ）。
const VERSION:=5
const G=preload("res://game/core/g.gd")
const Make=preload("res://game/core/make.gd")

var day:=1
var chapter:=0                    # 破った地方の数（＝今の章）
var phase:="day"                  # morning / day
var seed:=1
var next_uid:=1
var res: Dictionary={"money":0.0,"essence":0.0}
var stamina: Dictionary={"now":100,"max":100}
var caps: Dictionary={"cell":4,"den":6}
var grid: Dictionary={"w":26,"h":18,"cells":""}
var facilities: Array=[]          # {uid, def, x, y, rot, woman, monster}
var women: Array=[]
var monsters: Array=[]
var eggs: Array=[]                # 産んだが孵っていない卵
var world: Dictionary={"cleared":[],"sites_today":[],"chain":{}}
var party: Array=[]               # 前回の編成（魔物の uid）
var placement: Dictionary={}      # 前回の配置 {uid: [x, y]}
var altar_miss:=0
var named: Dictionary={}          # 名前付き {id: {captured, lost}}
var unlocked: Dictionary={"species":[],"regions":[]}
var records: Dictionary={"scenes":{},"endings":[],"captured":0,"born":0,"battles":[],"wins":0,"losses":0}
var report: Array=[]              # 朝の報告
var flags: Dictionary={}
var bonus_stamina:=0              # 施設で上げたスタミナの最大

func new_game(db,seed_value: int=-1) -> void:
	seed=seed_value if seed_value>=0 else int(Time.get_unix_time_from_system())%100000
	var b: Dictionary=db.balance
	res={"money":float(b.start.money),"essence":float(b.start.essence)}
	caps=b.start.caps.duplicate()
	day=1;chapter=0;phase="day";next_uid=1;altar_miss=0;bonus_stamina=0
	facilities=[];women=[];monsters=[];eggs=[];report=[];party=[];placement={}
	world={"cleared":[],"sites_today":[],"chain":{},"done":[]}
	records={"scenes":{},"endings":[],"captured":0,"born":0,"battles":[],"wins":0,"losses":0}
	flags={"help_seen":{}}
	named={}
	for id in db.women:named[id]={"captured":false,"lost":false}
	unlocked={"species":[],"regions":[str(db.regions[0].id)]}
	stamina={"now":stamina_max(),"max":stamina_max()}
	# 牧場：外周の岩の内側が床。柱を少し立てる。
	var w: int=int(b.ranch.w);var h: int=int(b.ranch.h)
	grid={"w":w,"h":h,"cells":""}
	var cells:=""
	for y in h:
		for x in w:
			var wall: bool=x==0 or y==0 or x==w-1 or y==h-1
			if (x==9 or x==17) and (y==4 or y==13):wall=true
			cells+="0" if wall else "1"
	grid.cells=cells
	for f in b.start.facilities:add_facility(str(f[0]),int(f[1]),int(f[2]))
	for i in b.start.monsters.size():
		var sp: Array=b.start.monsters[i]
		var m: Dictionary=Make.starter(str(sp[0]),float(sp[1]),Make.rng([seed,"start",i]))
		add_monster(m)
		# 出撃は始めの4体（残りは控え。編成で入れ替える）
		if party.size()<int(b.party_size):party.append(int(m.uid))

func uid() -> int:
	next_uid+=1;return next_uid

func prologue() -> bool:
	return chapter==0

# ───────── 資源 ─────────
func can_pay(cost: Dictionary) -> bool:
	for k in cost:
		if float(res.get(k,0))<float(cost[k]):return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):return false
	for k in cost:res[k]=float(res.get(k,0))-float(cost[k])
	return true

func gain(values: Dictionary) -> void:
	for k in values:
		if res.has(k):res[k]=maxf(0.0,float(res[k])+float(values[k]))

func log_event(kind: String,text: String,data: Dictionary={}) -> void:
	var e: Dictionary={"kind":kind,"text":text,"day":day}
	e.merge(data)
	report.append(e)

## 枠を増やす値段（買うたびに上がる）。key：cell_slot / den_slot / stamina_up
func slot_cost(key: String) -> int:
	var c: Dictionary=G.db.balance.costs
	return int(c[key])+int(c.slot_growth)*int(flags.get("bought_"+key,0))

## 枠を1段増やす。
func buy_slot(key: String) -> bool:
	var cost: int=slot_cost(key)
	if not pay({"money":cost}):return false
	flags["bought_"+key]=int(flags.get("bought_"+key,0))+1
	match key:
		"cell_slot":caps.cell=int(caps.cell)+int(G.db.balance.slot_step)
		"den_slot":caps.den=int(caps.den)+int(G.db.balance.slot_step)
		"stamina_up":
			bonus_stamina+=int(G.db.balance.stamina_step)
			stamina.max=stamina_max();stamina.now=int(stamina.now)+int(G.db.balance.stamina_step)
	return true

func stamina_max() -> int:
	var b: Dictionary=G.db.balance.stamina
	return int(b.max)+chapter*int(b.per_chapter)+bonus_stamina

# ───────── 牧場のマス ─────────
func cell(x: int,y: int) -> int:
	if x<0 or y<0 or x>=int(grid.w) or y>=int(grid.h):return 0
	return int(grid.cells.unicode_at(y*int(grid.w)+x))-48

func is_floor(x: int,y: int) -> bool:
	return cell(x,y)>=1

# ───────── 施設 ─────────
func add_facility(def: String,x: int,y: int,rot: int=0) -> Dictionary:
	# scene：流す場面（"" はその家具の場面）、expr：女の表情（"" は場面のまま）、outfit：女の服（"" は元の服、原型IDならその服）
	var f: Dictionary={"uid":uid(),"def":def,"x":x,"y":y,"rot":rot,"woman":-1,"monster":-1,"scene":"","expr":"","outfit":""}
	facilities.append(f)
	return f

func fac(u: int) -> Dictionary:
	for f in facilities:
		if int(f.uid)==u:return f
	return {}

func kind_of(f: Dictionary) -> String:
	return str(G.db.rooms.get(f.get("def",""),{}).get("kind",""))

func facilities_of(kind: String) -> Array:
	return facilities.filter(func(f):return kind_of(f)==kind)

## 施設を動かす・回す（置けなければ理由を返し、動かさない）。自分自身とは重ならない扱い。
func move_facility(f: Dictionary,x: int,y: int,rot: int) -> String:
	var why: String=place_block(str(f.def),x,y,rot,int(f.uid))
	if why!="":return why
	f.x=x;f.y=y;f.rot=posmod(rot,4)
	return ""

func fac_size(f: Dictionary) -> Vector2i:
	var s: Array=G.db.rooms[f.def].size
	return Vector2i(int(s[1]),int(s[0])) if int(f.rot)%2==1 else Vector2i(int(s[0]),int(s[1]))

func fac_rect(f: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(int(f.x),int(f.y)),fac_size(f))

func fac_center(f: Dictionary) -> Vector2:
	var r: Rect2i=fac_rect(f)
	return Vector2(r.position)+Vector2(r.size)*0.5

func fac_at(x: int,y: int) -> Dictionary:
	for f in facilities:
		if fac_rect(f).has_point(Vector2i(x,y)):return f
	return {}

func first_of(kind: String) -> Dictionary:
	for f in facilities:
		if kind_of(f)==kind:return f
	return {}

## 置けない理由（置けるなら ""）。
## 置けるか（置けなければ理由）。ignore は重なりを見ない施設の uid（動かすときの自分）。
func place_block(def: String,x: int,y: int,rot: int=0,ignore: int=-1) -> String:
	var tmp: Dictionary={"def":def,"x":x,"y":y,"rot":rot}
	var r: Rect2i=fac_rect(tmp)
	for cx in range(r.position.x,r.end.x):
		for cy in range(r.position.y,r.end.y):
			if not is_floor(cx,cy):return "床の上にしか置けない"
			var o: Dictionary=fac_at(cx,cy)
			if not o.is_empty() and int(o.uid)!=ignore:return "ほかの施設と重なる"
	return ""

func remove_facility(u: int) -> void:
	var f: Dictionary=fac(u)
	if f.is_empty():return
	var w: Dictionary=woman(int(f.woman))
	if not w.is_empty():move_woman(w,"cell")
	var m: Dictionary=monster(int(f.monster))
	if not m.is_empty():set_job(m,"rest")
	facilities.erase(f)

# ───────── 女 ─────────
func woman(id: int) -> Dictionary:
	if id<0:return {}
	for w in women:
		if int(w.uid)==id:return w
	return {}

func add_woman(w: Dictionary) -> Dictionary:
	w.uid=uid()
	women.append(w)
	if str(w.get("woman_id",""))!="":named[w.woman_id].captured=true
	records.captured=int(records.captured)+1
	return w

func women_in(use: String) -> Array:
	return women.filter(func(w):return str(w.use)==use)

func cell_count() -> int:
	return women_in("cell").size()

## 女を使い道へ移す（牢・房・苗床・召喚陣・搾り場）。前の施設は空く。産む途中はやめる。
func move_woman(w: Dictionary,use: String,f: Dictionary={}) -> void:
	var prev: Dictionary=fac(int(w.get("fac",-1)))
	if not prev.is_empty() and int(prev.woman)==int(w.uid):prev.woman=-1
	w.laying={}
	w.use=use;w.fac=-1
	if use=="cell" or f.is_empty():w.use="cell";return
	w.fac=int(f.uid)
	f.woman=int(w.uid)

func woman_at(f: Dictionary) -> Dictionary:
	return woman(int(f.get("woman",-1)))

# ───────── 魔物 ─────────
func monster(id: int) -> Dictionary:
	if id<0:return {}
	for m in monsters:
		if int(m.uid)==id:return m
	return {}

func add_monster(m: Dictionary) -> Dictionary:
	if int(m.get("uid",0))<=0:m.uid=uid()
	monsters.append(m)
	if not str(m.species) in unlocked.species:unlocked.species.append(str(m.species))
	if job_count("rest")<int(caps.den):m.job="rest"
	return m

func job_count(job: String) -> int:
	return monsters.filter(func(m):return str(m.job)==job).size()

## 今夜の務めを決める（rest 巣で休む／partner 房の相手役／father 苗床の父／none）。前の施設は空く。
func set_job(m: Dictionary,job: String,f: Dictionary={}) -> void:
	var prev: Dictionary=fac(int(m.get("fac",-1)))
	if not prev.is_empty() and int(prev.monster)==int(m.uid):prev.monster=-1
	m.fac=-1
	if job=="rest" and job_count("rest")>=int(caps.den) and str(m.job)!="rest":job="none"
	m.job=job
	if (job=="partner" or job=="father") and not f.is_empty():
		var old: Dictionary=monster(int(f.monster))
		if not old.is_empty() and int(old.uid)!=int(m.uid):old.fac=-1;old.job="none";set_job(old,"rest")
		f.monster=int(m.uid);m.fac=int(f.uid)
	elif job=="partner" or job=="father":m.job="none"

func monster_at(f: Dictionary) -> Dictionary:
	return monster(int(f.get("monster",-1)))

# ───────── 保存 ─────────
func to_dict() -> Dictionary:
	return {"version":VERSION,"day":day,"chapter":chapter,"phase":phase,"seed":seed,"next_uid":next_uid,"res":res,"stamina":stamina,"caps":caps,
		"grid":grid,"facilities":facilities,"women":women,"monsters":monsters,"eggs":eggs,"world":world,"party":party,"placement":placement,
		"altar_miss":altar_miss,"named":named,"unlocked":unlocked,"records":records,"report":report,"flags":flags,"bonus_stamina":bonus_stamina}

func from_dict(d: Dictionary) -> void:
	day=int(d.day);chapter=int(d.chapter);phase=str(d.get("phase","day"));seed=int(d.seed);next_uid=int(d.next_uid)
	res=d.res;stamina=d.stamina;caps=d.caps;grid=d.grid;facilities=d.facilities;women=d.women;monsters=d.monsters;eggs=d.get("eggs",[])
	world=d.world;party=ints(d.get("party",[]));placement=d.get("placement",{});altar_miss=int(d.get("altar_miss",0))
	named=d.named;unlocked=d.unlocked;records=d.records;report=d.get("report",[]);flags=d.get("flags",{});bonus_stamina=int(d.get("bonus_stamina",0))
	grid.w=int(grid.w);grid.h=int(grid.h)
	stamina.now=int(stamina.now);stamina.max=int(stamina.max)
	for k in caps:caps[k]=int(caps[k])
	# JSON から戻すと整数が小数になるので、ID の類いを整数へ戻す。
	for f in facilities:
		for k in ["uid","x","y","rot","woman","monster"]:f[k]=int(f.get(k,-1 if k in ["woman","monster"] else 0))
	for w in women:
		for k in ["uid","star","stage","nights","eggs_left","eggs_done","fac"]:w[k]=int(w.get(k,-1 if k=="fac" else 0))
		w.children=ints(w.get("children",[]))
		if w.get("laying",{}) is Dictionary and not w.laying.is_empty():
			w.laying.nights=int(w.laying.nights);w.laying.father=int(w.laying.get("father",-1))
	for m in monsters:
		for k in ["uid","grade","hp","wins","fac","mother","father","generation","born_day"]:m[k]=int(m.get(k,-1 if k in ["fac","mother","father","grade"] else 0))
	for e in eggs:
		for k in ["uid","mother","grade","hatch_day","father"]:e[k]=int(e.get(k,-1))
	for k in placement.keys():placement[k]=[int(placement[k][0]),int(placement[k][1])]

static func ints(a: Array) -> Array:
	var out: Array=[]
	for v in a:out.append(int(v))
	return out
