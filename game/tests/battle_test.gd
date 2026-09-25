extends SceneTree
## 戦闘の計算の確かめ（設計書 11章）。画面なし。
##   Godot_console --headless --path . --script res://game/tests/battle_test.gd [-- --verbose]
##   決定性（同じ入力を2回回して刻みごとに一致）・必ず終わるか・自由に動くか・スキルが自動で撃たれるか・パッシブが開く条件・一行の動き方・連戦の体力の持ち越し・
##   役割ごとの魔物の働き（遠距離・盾・暗殺・回復・術・支援）と、種族ごとの働きの一覧（--verbose）。
const G=preload("res://game/core/g.gd")
const Db=preload("res://game/core/db.gd")
const State=preload("res://game/core/state.gd")
const Day=preload("res://game/core/day.gd")
const Setup=preload("res://game/battle/setup.gd")
const Sim=preload("res://game/battle/sim.gd")
const Sites=preload("res://game/world/sites.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Make=preload("res://game/core/make.gd")
var bad:=0
var verbose:=false

func _initialize():call_deferred("run")

func check(ok: bool,what: String) -> void:
	print(("OK   " if ok else "FAIL ")+what)
	if not ok:bad+=1

func run():
	verbose="--verbose" in OS.get_cmdline_user_args()
	G.db=Db.new()
	if not G.db.load_all():
		print("DB_PROBLEMS ",G.db.problems);quit(1);return
	G.state=State.new();G.state.new_game(G.db,7)
	Day.first_morning()
	var st=G.state
	# 1. 最初の戦闘（麓の村・村の見張り）：始めの4体で勝てる
	var site: Dictionary=Sites.story_site(G.db.regions[0],"foothill_1")
	var sim=Setup.start(site,0,st.party)
	var res: Dictionary=sim.run_all()
	check(res.won,"始めの4体で村の見張りに勝てる　%.1f秒"%float(res.secs))
	if verbose:dump(res)
	# 2. 決定性：同じ入力で2回、刻みごとに一致
	site=Sites.story_site(G.db.regions[1],"frontier_1")
	var a=Setup.start(site,0,st.party);var b=Setup.start(site,0,st.party)
	var same:=true
	while not a.done or not b.done:
		a.step();b.step()
		if a.signature()!=b.signature():same=false;break
	check(same,"同じ入力なら刻みごとに同じ（%.1f秒）"%a.t)
	# 3. 自由に動く：始めて少したつと、マスの中心から外れた所にいる者がいる／スキルが自動で撃たれる
	var c=Setup.start(site,0,st.party)
	for i in 12:c.step()
	var off:=false
	for u in c.units:
		var f: Vector2=(u.pos as Vector2)-Vector2(0.5,0.5)
		if absf(f.x-round(f.x))>0.05 or absf(f.y-round(f.y))>0.05:off=true
	check(off,"マス目にとらわれず動く（0.6秒で途中の位置にいる）")
	var rc: Dictionary=c.run_all()
	var casts:=0
	for u in rc.units:
		if u.side=="m":casts+=int(u.casts)
	check(casts>0,"魔物のスキルが自動で撃たれる（%d回）"%casts)
	# 4. すべての出撃先が時間切れの前に必ず終わる（強い組・弱い組）
	var strong: Array=[];var weak: Array=[]
	for sp in ["tentacle","carapace","slime","beast"]:
		strong.append(fake(sp,80));weak.append(fake(sp,20))
	var n:=0;var over:=0;var wins:=0;var longest:=0.0;var total:=0.0
	var all_sites: Array=[]
	for r in G.db.regions:
		for h in r.hunts:all_sites.append(Sites.hunt_site(r,h))
		for s in r.story:all_sites.append(Sites.story_site(r,s))
	for s in all_sites:
		for k in s.chain.size():
			for team in [strong,weak]:
				for m in team:m.hp=Stats.hp_max(m)
				var sm=Sim.new()
				var f: Dictionary=Setup.fight(s,k)
				sm.setup(f,team.map(func(m):return {"m":m,"pos":Vector2i(1,[3,4,2,5][team.find(m)])}))
				sm.run_all()
				n+=1;longest=maxf(longest,sm.t);total+=sm.t
				if sm.t>=sm.cap-0.01:over+=1
				if sm.won and team==strong:wins+=1
	check(over==0,"%d戦すべて時間切れの前に決着がつく（時間切れ %d、最長 %.1f秒、平均 %.1f秒）"%[n,over,longest,total/maxf(1,n)])
	print("     強い組（能力80）の勝ち：%d / %d"%[wins,n/2])
	# 5. パッシブが開く条件
	var m: Dictionary=fake("tentacle",45)
	check(Stats.open_passives(m).has("squeeze") and not Stats.open_passives(m).has("big_tentacle"),"力45の触手は締め上げだけ開く")
	m.apt.str=70;m.apt.end=70
	var opened: Array=[]
	for i in 30:opened+=Stats.grow(m,"str",1.0)+Stats.grow(m,"end",1.0)
	check("big_tentacle" in opened,"力と耐を60まで伸ばすと大触手が開く")
	check(float(m.stats.str)<=70.0,"素質を越えて伸びない")
	# 6. 大触手で2人縛れる（溜まっていれば、射程に入った的へ自動で撃つ）
	var t2: Dictionary=fake("tentacle",70);t2.inherited=[]
	var sim2=Sim.new()
	var fight2: Dictionary={"board":G.db.boards.open,"party":[mem("warrior",Vector2i(3,3)),mem("warrior",Vector2i(3,4))]}
	sim2.setup(fight2,[{"m":t2,"pos":Vector2i(1,3)}])
	var tu: Dictionary=sim2.unit_of_monster(int(t2.uid))
	tu.charge=100.0
	sim2.step()
	var bound: int=sim2.units.filter(func(u):return u.side=="w" and float(u.status.bind)>0).size()
	check(bound==2,"大触手の絡め取りで2人を縛る（%d人）"%bound)
	# 7. 盗賊は後ろを狙い、戦士は縛られて少したつと引きちぎる
	var sim3=Sim.new()
	var fight3: Dictionary={"board":G.db.boards.open,"party":[mem("thief",Vector2i(6,3)),mem("warrior",Vector2i(5,4))]}
	var front: Dictionary=fake("carapace",40);var back: Dictionary=fake("slime",40)
	sim3.setup(fight3,[{"m":front,"pos":Vector2i(1,4)},{"m":back,"pos":Vector2i(0,4)}])
	check(sim3.pick_target(sim3.units[2]).id==sim3.units[1].id,"盗賊は一番後ろの魔物を狙う")
	sim3.units[3].status.bind=5.0;sim3.units[3].status.bound_for=0.0
	for i in int(ceil(2.0/Sim.TICK)):sim3.step()
	check(float(sim3.units[3].status.bind)==0.0,"戦士は縛られて2秒以内に引きちぎる")
	# 8. 連戦で体力が持ち越す
	var site2: Dictionary=Sites.story_site(G.db.regions[0],"foothill_2")
	var s1=Setup.start(site2,0,st.party)
	var r1: Dictionary=s1.run_all()
	for uid in r1.hp:st.monster(int(uid)).hp=int(r1.hp[uid])
	var s2=Setup.start(site2,1,st.party)
	var carried:=true
	for u in s2.units:
		if u.side=="m" and not u.minion and int(u.hp)!=int(r1.hp[int(u.ref)]):carried=false
	check(carried,"連戦の2戦目は1戦目の後の体力で始まる")
	roles_check()
	print("BATTLE_TEST_DONE bad=",bad)
	quit()

func fake(sp: String,v: float) -> Dictionary:
	var m: Dictionary=Make.base_monster(sp)
	m.uid=G.state.uid()
	for k in ["str","mag","spd","end"]:m.apt[k]=v;m.stats[k]=v
	m.name=sp
	m.hp=Stats.hp_max(m)
	return m

func mem(job: String,pos: Vector2i) -> Dictionary:
	var jd: Dictionary=G.db.jobs[job]
	var s: Dictionary={}
	for k in ["str","mag","spd","end"]:s[k]=float(jd.stats[k][1])
	return {"job":job,"named":"","name":job,"stats":s,"star":2,"pos":pos}

func dump(res: Dictionary) -> void:
	for l in res.log:print("   %5.1f %s"%[float(l.time),str(l.text)])
	for u in res.units:print("   %s %s hp %d/%d 与 %d 受 %d 技 %d"%[u.side,u.name,u.hp,u.max,u.dealt,u.taken,u.casts])

# ───────── 役割ごとの魔物 ─────────
func party_of(jobs: Array) -> Dictionary:
	var ps: Array=[]
	for i in jobs.size():ps.append(mem(str(jobs[i]),Vector2i(6,[3,4,2,5,1][i])))
	return {"board":G.db.boards.open,"party":ps}

func team_of(list: Array) -> Array:
	var out: Array=[]
	for i in list.size():out.append({"m":list[i],"pos":Vector2i(1 if i<2 else 0,[3,4,3,4][i])})
	return out

func roles_check() -> void:
	# 遠距離：射程4から撃つ（矢を飛ばす）
	var archer: Dictionary=fake("goblin_archer",60)
	var sa=Sim.new();sa.setup(party_of(["knight"]),team_of([fake("golem",60),archer]))
	var far_shot:=false
	while not sa.done and sa.t<20.0:
		sa.step()
		for e in sa.events:
			if str(e.k)=="shot" and int(e.u)==sa.unit_of_monster(int(archer.uid)).id and sa.dist(sa.unit(int(e.u)),sa.unit(int(e.t)))>3.0:far_shot=true
	check(far_shot,"弓兵は3マスより遠くから矢を射る")
	# 盾：守りの陣で仲間に盾を張り、近くの仲間への攻撃を代わりに受ける
	var golem: Dictionary=fake("golem",60);var weakling: Dictionary=fake("wisp",30)
	var sg=Sim.new();sg.setup(party_of(["warrior","warrior"]),team_of([golem,weakling]))
	var gu: Dictionary=sg.unit_of_monster(int(golem.uid));gu.charge=100.0
	var wu: Dictionary=sg.unit_of_monster(int(weakling.uid))
	while not sg.done and sg.t<5.0:sg.step()
	check(int(sg.stats[gu.id].casts)>0 and int(sg.stats[wu.id].taken)==0,"石像兵は守りの陣を張り、後ろの仲間への攻撃を引き受ける（後ろの鬼火の受けた痛手 %d）"%int(sg.stats[wu.id].taken))
	# 暗殺：始めは隠れて狙われず、一番弱った女へ跳んで刈る（弱っていると1.6倍）
	var kama: Dictionary=fake("kamaitachi",60)
	var sk=Sim.new();sk.setup(party_of(["warrior","priest","mage"]),team_of([kama]))
	var ku: Dictionary=sk.unit_of_monster(int(kama.uid))
	check(float(ku.status.hidden)>0 and sk.pick_target(sk.units[1]).id!=ku.id or sk.alive("m").size()==1,"鎌鼬は始め隠れている")
	var hidden_ok: bool=float(ku.status.hidden)>0
	for w in sk.alive("w"):
		if sk.pick_target(w).id==ku.id and sk.alive("m").size()>1:hidden_ok=false
	var mage_u: Dictionary=sk.units[3];mage_u.hp=int(mage_u.max*0.3)
	ku.charge=100.0;ku.pos=Vector2(4.5,3.5)
	var before: int=int(mage_u.hp)
	sk.step()
	check(int(sk.stats[ku.id].casts)==1 and int(mage_u.hp)<before,"鎌鼬の首狩りは一番弱った女（魔術師）を刈る")
	# 回復：周りの仲間を癒やす
	var myc: Dictionary=fake("myconid",60);var hurtm: Dictionary=fake("carapace",60)
	var sm=Sim.new();sm.setup(party_of(["villager"]),team_of([hurtm,myc]))
	var hu: Dictionary=sm.unit_of_monster(int(hurtm.uid));hu.hp=int(hu.max/3)
	var mu: Dictionary=sm.unit_of_monster(int(myc.uid));mu.charge=100.0
	var h0: int=int(hu.hp)
	sm.step()
	check(int(hu.hp)>h0,"茸人は弱った仲間を癒やす（%d→%d）"%[h0,int(hu.hp)])
	# 術：爆炎は溜まりが150要る
	var imp: Dictionary=fake("imp",60)
	var si=Sim.new();si.setup(party_of(["villager"]),team_of([imp]))
	var iu: Dictionary=si.unit_of_monster(int(imp.uid))
	iu.charge=100.0
	check(not si.ready(iu) and float(iu.full)>=150.0,"火の小鬼の爆炎は溜まりが1.5倍要る")
	# 支援：鬨の声で仲間が速まる
	var drum: Dictionary=fake("drum_ogre",60);var ally: Dictionary=fake("beast",60)
	var sd=Sim.new();sd.setup(party_of(["warrior"]),team_of([drum,ally]))
	var du: Dictionary=sd.unit_of_monster(int(drum.uid));var au: Dictionary=sd.unit_of_monster(int(ally.uid))
	du.charge=100.0
	var hasted:=false
	while not sd.done and sd.t<10.0 and not hasted:
		sd.step()
		if float(au.status.haste)>0:hasted=true
	check(hasted,"鬨の鬼の鬨の声で仲間が速まる")
	# 雑兵：魔物の前に並び、体力は持ち越さない。魔物が全員倒れたら雑兵が残っていても負け
	var site9: Dictionary=Sites.story_site(G.db.regions[1],"frontier_1")
	var s9=Setup.start(site9,0,G.state.party)
	var mins: Array=s9.units.filter(func(u):return u.minion)
	check(mins.size()==int(G.db.balance.minions.count) and not s9.result().hp.has(-1),"雑兵%d体が並び、結果の体力に入らない"%mins.size())
	for u in s9.alive_monsters():u.hp=0;u.alive=false
	s9.step()
	check(s9.done and not s9.won,"魔物が全員倒れたら、雑兵が残っていても負け")
	# 号令：狙え（全員がその女を狙う）・押し込め（速まる）。回数は限られる
	var s10=Setup.start(site9,0,G.state.party)
	var w10: Dictionary=s10.alive("w")[-1]
	check(s10.order("focus",w10.id),"号令「狙え」を出せる")
	s10.step()
	check(s10.alive("m").all(func(u):return s10.pick_target(u).id==w10.id),"狙えで全員が同じ女を狙う")
	check(s10.order("rally") and not s10.order("rally"),"号令は%d回まで"%int(G.db.balance.orders.count))
	s10.step()
	check(s10.alive("m").all(func(u):return float(u.status.haste)>0),"押し込めで全員が速まる")
	# 号令の記録を入れ直すと同じ結果
	var r10: Dictionary=s10.run_all()
	var s11=Setup.start(site9,0,G.state.party,r10.orders)
	var r11: Dictionary=s11.run_all()
	check(s11.signature()==s10.signature(),"号令の記録を再生すると同じ結果")
	# 種族ごとの働き（同じ能力60の4体で、中くらいの一行と戦う）
	if verbose:
		print("     種族（能力60×4体） 勝ち 秒 与えた 受けた 撃った")
		for sp in G.db.species:
			if G.db.species[sp].has("unique_of"):continue
			var team: Array=[fake(sp,60),fake(sp,60),fake(sp,60),fake(sp,60)]
			var pf: Dictionary=party_of(["knight","warrior","priest","mage","thief"])
			for pm in pf.party:
				for k in pm.stats:pm.stats[k]=float(pm.stats[k])*1.6
			var sv=Sim.new();sv.setup(pf,team_of(team))
			var r: Dictionary=sv.run_all()
			var dealt:=0;var taken:=0;var casts:=0
			for u in r.units:
				if u.side=="m":dealt+=int(u.dealt);taken+=int(u.taken);casts+=int(u.casts)
			print("     %-8s %s %5.1f %4d %4d %3d"%[G.db.species_name(sp),"勝" if r.won else "負",float(r.secs),dealt,taken,casts])
