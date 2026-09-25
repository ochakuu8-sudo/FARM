extends RefCounted
## 戦闘の結果を反映する（設計書 8.3・8.4）。
##   勝ち：倒れた一行を全員獲得して牢へ、お金（報酬＋女ごとの持ち物）、出た魔物の能力が少し伸びる。
##   牢が満杯なら、名前なしの女はその場で売り払う（手放すと同じ ★×30 のお金）。名前付きは必ず牢へ。
##   負け：得るものはない（使ったスタミナと減った体力はそのまま）。どちらも魔物の体力は戦闘の後の値になる。
const G=preload("res://game/core/g.gd")
const Make=preload("res://game/core/make.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]

## 返り値：{won, captured: [女の uid], money, opened: [{uid, skills}], cleared, chapter_up, victory}
static func apply(site: Dictionary,k: int,res: Dictionary,fight: Dictionary) -> Dictionary:
	var st=G.state
	var b: Dictionary=G.db.balance
	var out: Dictionary={"won":bool(res.won),"captured":[],"sold":0,"sold_money":0,"money":0,"opened":[],"cleared":false,"chapter_up":false,"victory":false}
	for uid in res.hp:
		var m: Dictionary=st.monster(int(uid))
		if not m.is_empty():m.hp=int(res.hp[uid])
	st.records.battles.push_front({"day":st.day,"site":str(site.name),"k":k,"won":bool(res.won),"secs":float(res.secs),"units":res.units})
	st.records.battles=st.records.battles.slice(0,12)
	if not res.won:
		st.records.losses=int(st.records.losses)+1
		return out
	st.records.wins=int(st.records.wins)+1
	# 勝った狩場はその日はもう選べない（同じ一行を何度も捕らえられないように）
	if str(site.kind)=="hunt" and not str(site.id) in st.world.get("done",[]):
		if not st.world.has("done"):st.world.done=[]
		st.world.done.append(str(site.id))
	var money: int=int(site.chain[k].reward)
	for i in res.down:
		var mem: Dictionary=fight.party[int(i)]
		if str(mem.get("named",""))=="" and st.women_in("cell").size()>=int(st.caps.cell):
			var sell: int=int(mem.star)*30+int(round(float(G.db.jobs[str(mem.job)].get("value",0))*float(b.money.value_rate)))
			money+=sell;out.sold=int(out.sold)+1;out.sold_money=int(out.sold_money)+sell
			continue
		var rec: Dictionary=Make.woman_from(mem,str(site.name))
		rec.name=Make.free_woman_name(str(rec.name),str(rec.get("woman_id","")),Make.rng([st.seed,"wname",st.day,str(site.id),k,int(i)]))
		var w: Dictionary=st.add_woman(rec)
		w.history.append({"day":st.day,"text":"%sで捕らえた"%str(site.name)})
		out.captured.append(int(w.uid))
		money+=int(w.star)*int(b.money.per_star)+int(round(float(G.db.jobs[str(w.job)].get("value",0))*float(b.money.value_rate)))
	st.gain({"money":money})
	out.money=money
	for uid in res.hp:
		var m2: Dictionary=st.monster(int(uid))
		if m2.is_empty():continue
		m2.wins=int(m2.wins)+1
		var opened: Array=[]
		for s in STATS:opened+=Stats.grow(m2,s,float(b.win_gain))
		if not opened.is_empty():out.opened.append({"uid":int(m2.uid),"skills":opened})
	# ストーリー戦：勝った所までは進んだまま（次は続きから。同じ一行を何度も捕らえられないように）
	if str(site.kind)=="story" and k<site.chain.size()-1:
		if not st.world.has("story_k"):st.world.story_k={}
		st.world.story_k[str(site.stage)]=k+1
	# ストーリー戦を最後まで破った
	if str(site.kind)=="story" and k>=site.chain.size()-1:
		out.cleared=true
		st.world.cleared.append(str(site.stage))
		var ri: int=G.db.region_index(str(site.region))
		var r: Dictionary=G.db.regions[ri]
		if str(r.story[-1])==str(site.stage):
			if bool(site.final):
				out.victory=true;st.flags.victory=true
			elif ri+1<G.db.regions.size():
				st.chapter=maxi(st.chapter,ri+1)
				var nr: Dictionary=G.db.regions[ri+1]
				if not str(nr.id) in st.unlocked.regions:st.unlocked.regions.append(str(nr.id))
				out.chapter_up=true
				st.log_event("chapter","%sを落とした。次は%s　─ %s"%[r.name,nr.name,str(nr.get("intro",""))],{"region":str(nr.id)})
	return out
