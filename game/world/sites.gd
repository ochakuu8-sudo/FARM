extends RefCounted
## 出撃先（企画書 4.1・4.2、設計書 8章）。狩場は朝に種から組み、ストーリー戦は world.json の決まった戦場。
## 出撃先の1件：{id, kind: hunt|story, region, name, icon, board, cost, chain: [{party: [一行の者], reward}], final, stage}
const G=preload("res://game/core/g.gd")
const Make=preload("res://game/core/make.gd")

## 今日の出撃先をすべて組む（開いている地方の狩場と、今の地方の次のストーリー戦）。
static func make_today() -> Array:
	var st=G.state
	var out: Array=[]
	for i in G.db.regions.size():
		var r: Dictionary=G.db.regions[i]
		if not str(r.id) in st.unlocked.regions:continue
		for h in r.get("hunts",[]):out.append(hunt_site(r,h))
		var s: String=next_story(r)
		if s!="":out.append(story_site(r,s))
	return out

static func next_story(r: Dictionary) -> String:
	for s in r.get("story",[]):
		if not s in G.state.world.cleared:return str(s)
	return ""

static func hunt_site(r: Dictionary,h: Dictionary) -> Dictionary:
	var st=G.state
	var rg:=Make.rng([st.seed,"hunt",st.day,str(h.id)])
	var chain: Array=[]
	for k in int(h.get("chain",1)):
		var n: int=rg.randi_range(int(h.size[0]),int(h.size[1]))
		var party: Array=[]
		for i in n:
			var job: String=Make.pick_key(h.jobs,rg)
			var power: float=rg.randf_range(float(h.power[0]),float(h.power[1]))+0.1*k
			party.append(Make.mob_member(job,power,rg))
		unique_names(party,rg)
		chain.append({"party":party,"reward":int(round(float(h.reward)*(1.0+0.3*k)))})
	return {"id":"hunt:%s:%d"%[str(h.id),st.day],"kind":"hunt","region":str(r.id),"name":str(h.name),"icon":str(h.get("icon","flag")),
		"board":G.db.boards[str(h.board)],"cost":int(h.cost),"chain":chain,"final":false,"stage":""}

static func story_site(r: Dictionary,id: String) -> Dictionary:
	var sd: Dictionary=G.db.stages[id]
	var rg:=Make.rng([G.state.seed,"story",id])
	var chain: Array=[]
	for fi in sd.chain.size():
		var fight: Dictionary=sd.chain[fi]
		var party: Array=[]
		var powers: Array=[]
		for m in fight.party:
			if m.has("named"):party.append(Make.named_member(str(m.named)))
			else:party.append(Make.mob_member(str(m.job),float(m.get("power",1.0)),rg));powers.append(float(m.get("power",1.0)))
		# 護衛：地方の人数（escort_to）に足りなければ、その地方の狩場の職で埋める（はじめの戦いは埋めない）。
		# 名前付きのいる戦いは2人少なくする（名前付きが主役になるように）。
		var hunts: Array=r.get("hunts",[])
		var named_here: bool=fight.party.any(func(m):return m.has("named"))
		var to: int=int(r.get("escort_to",0))-(2 if named_here else 0)
		if not (G.db.regions.find(r)==0 and fi==0 and id==str(r.story[0])) and not hunts.is_empty():
			var pw: float=powers.min() if not powers.is_empty() else float(hunts[0].power[1])
			while party.size()<to:
				party.append(Make.mob_member(Make.pick_key(hunts[0].jobs,rg),pw*0.95,rg))
		unique_names(party,rg)
		chain.append({"party":party,"reward":int(fight.get("reward",50))})
	return {"id":"story:"+id,"kind":"story","region":str(r.id),"name":str(sd.name),"icon":"crown" if sd.chain.any(func(f):return f.party.any(func(m):return m.has("named"))) else "castle",
		"board":G.db.boards[str(sd.board)],"cost":int(sd.cost),"chain":chain,"final":bool(sd.get("final",false)),"stage":id}

## 一行の中で名前が重ならないようにする（名前付きはそのまま）。
static func unique_names(party: Array,rg: RandomNumberGenerator) -> void:
	var used: Dictionary={}
	var names: Array=G.db.mob.names
	for m in party:
		var tries:=0
		while used.has(str(m.name)) and str(m.get("named",""))=="" and tries<30:
			m.name=str(names[rg.randi()%names.size()]);tries+=1
		used[str(m.name)]=true

## 連戦の k 戦目のスタミナ（2戦目以降は半分）。
static func cost_of(site: Dictionary,k: int) -> int:
	return int(site.cost) if k==0 else int(ceil(float(site.cost)*0.5))

## ストーリー戦の続き（何戦目から挑むか）。
static func start_k(site: Dictionary) -> int:
	if str(site.kind)!="story":return 0
	return clampi(int(G.state.world.get("story_k",{}).get(str(site.stage),0)),0,site.chain.size()-1)

## 今日もう勝った狩場か。
static func done(site: Dictionary) -> bool:
	return str(site.id) in G.state.world.get("done",[])

static func find(id: String) -> Dictionary:
	for s in G.state.world.sites_today:
		if str(s.id)==id:return s
	return {}

## 一行の陣（右の5列）：前衛（かばう・殴る）は前の列の真ん中、回り込む者は前寄りの上下の端、術と回復は奥の列。崖は避ける。
static func place_party(party: Array,board: Array) -> void:
	var w: int=str(board[0]).length()
	var front: Array=[];var flank: Array=[];var back: Array=[]
	for m in party:
		var ai: String=str(G.db.jobs[str(m.job)].ai)
		if ai=="flank":flank.append(m)
		elif ai in ["caster","healer"]:back.append(m)
		else:front.append(m)
	var used: Dictionary={}
	var put:=func(list: Array,cols: Array,rows: Array):
		for m in list:
			var placed:=false
			for col in cols:
				for y in rows:
					var c:=Vector2i(col,y)
					if used.has(c) or col<0 or col>=w or str(board[y]).substr(col,1)!=".":continue
					m.pos=c;used[c]=true;placed=true;break
				if placed:break
			if not placed:
				for col in range(w-1,w-6,-1):
					for y in 8:
						var c2:=Vector2i(col,y)
						if not used.has(c2) and str(board[y]).substr(col,1)!="#":m.pos=c2;used[c2]=true;placed=true;break
					if placed:break
	put.call(front,[w-5,w-4],[3,4,2,5,1,6,0,7])
	put.call(flank,[w-4,w-3],[0,7,1,6,2,5])
	put.call(back,[w-1,w-2],[3,4,2,5,1,6,0,7])

## 出撃先の見どころ（一行の職の数）。
static func summary(site: Dictionary) -> String:
	var jobs: Dictionary={}
	for f in site.chain:
		for m in f.party:jobs[str(m.job)]=int(jobs.get(str(m.job),0))+1
	var parts: Array=[]
	for j in jobs:parts.append("%s×%d"%[G.db.jobs[j].name,int(jobs[j])])
	return "・".join(parts)
