extends SceneTree
## 捕らえた女と卵の確かめ（設計書 11章）。画面なし。
##   Godot_console --headless --path . --script res://game/tests/breed_test.gd
##   房の夜・段階・仕込みの上限・相手役の伸び・搾り場・苗床の素質と継承・召喚陣の抽選表と天井・予想の幅が本番の範囲を外れないか。
const G=preload("res://game/core/g.gd")
const Db=preload("res://game/core/db.gd")
const State=preload("res://game/core/state.gd")
const Day=preload("res://game/core/day.gd")
const Make=preload("res://game/core/make.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Stats=preload("res://game/monsters/stats.gd")
const STATS:=["str","mag","spd","end"]
var bad:=0

func _initialize():call_deferred("run")

func check(ok: bool,what: String) -> void:
	print(("OK   " if ok else "FAIL ")+what)
	if not ok:bad+=1

func run():
	G.db=Db.new()
	if not G.db.load_all():
		print("DB_PROBLEMS ",G.db.problems);quit(1);return
	G.state=State.new();G.state.new_game(G.db,11)
	Day.first_morning()
	var st=G.state
	st.chapter=1   # 本編の日数で確かめる
	var r:=Make.rng([1])
	var w: Dictionary=st.add_woman(Make.woman_from(Make.mob_member("knight",1.5,r),"試験"))
	check(str(w.use)=="cell" and st.cell_count()==1,"獲得した女は牢に入る")
	# 房（耐）に入れ、相手役を付ける
	var house: Dictionary=st.first_of("house")
	check(Captive.to_use(w,"house",house)=="","房へ入れられる")
	var partner: Dictionary=st.monsters[0]
	for k in STATS:partner.apt[k]=90.0
	var before: float=float(partner.stats.end)
	st.set_job(partner,"partner",house)
	check(str(partner.job)=="partner" and int(house.monster)==int(partner.uid),"相手役を付けられる")
	w.weak=str(G.db.rooms[house.def].house);w.weak_known=true
	Day.end_day(false)
	check(float(w.shikomi[str(G.db.rooms[house.def].house)])>0,"房の夜で仕込みが伸びる")
	check(float(partner.stats.end)>before,"相手役の耐が伸びる（%d → %d）"%[int(before),int(partner.stats.end)])
	check(int(w.stage)==1,"弱点の房なら本編でも1晩で段階が1つ進む（%d）"%int(w.stage))
	for i in 12:Day.end_day(false)
	var tot:=0.0
	for k in STATS:tot+=float(w.shikomi[k])
	check(tot<=Captive.stage_cap(int(w.stage))+0.01,"仕込みの合計は段階の上限まで（%d / %d）"%[int(tot),int(Captive.stage_cap(int(w.stage)))])
	check(int(w.stage)==4,"段階は心酔で止まる")
	# 苗床：父と同じ種族、素質は母で決まる
	var father: Dictionary=st.monsters[1]
	father.inherited=["grit","toxin"]
	var nursery: Dictionary=st.first_of("nursery")
	st.move_woman(w,"cell")
	check(Captive.to_use(w,"nursery",nursery)=="","従順以上なら苗床へ入れられる")
	st.set_job(father,"father",nursery)
	var pred: Dictionary=Eggs.predict_apt(w)
	var left_before: int=int(w.eggs_left)
	var hp_before: int=int(father.hp)
	father.hp=hp_before-10
	for i in Eggs.lay_nights():Day.end_day(false)
	check(int(w.eggs_left)==left_before-1,"苗床で卵を1つ産む（残り %d）"%int(w.eggs_left))
	check(int(father.hp)==hp_before-10,"父を務めた晩は体力が戻らない")
	var egg: Dictionary=st.eggs[-1] if not st.eggs.is_empty() else {}
	check(not egg.is_empty() and str(egg.species)==str(father.species),"卵の種族は父と同じ")
	var inside:=true
	for k in STATS:
		if float(egg.apt[k])<float(pred[k][0])-0.01 or float(egg.apt[k])>float(pred[k][1])+0.01:inside=false
	check(inside,"素質は予想の幅の中")
	for id in egg.inherited:check(id in Stats.passives(father),"継いだパッシブは父のもの（%s）"%id)
	for i in Eggs.hatch_nights()+1:Day.end_day(false)
	var kid: Dictionary=st.monster(w.children[0]) if not w.children.is_empty() else {}
	check(not kid.is_empty(),"卵が孵る")
	if not kid.is_empty():
		check(absf(float(kid.stats.str)-roundf(float(kid.apt.str)*float(G.db.balance.hatch_ratio)))<0.01,"孵った子の能力は素質の決まった割合（%d / %d）"%[int(kid.stats.str),int(kid.apt.str)])
		check(int(kid.generation)==int(father.generation)+1,"世代が1つ進む")
	# 弱い女の子は弱い（量産できない）
	var weak_w: Dictionary=Make.woman_from(Make.mob_member("villager",1.0,r),"試験")
	var strong_w: Dictionary=Make.woman_from(Make.named_member("rina"),"試験")
	var pw: Dictionary=Eggs.predict_apt(weak_w);var ps: Dictionary=Eggs.predict_apt(strong_w)
	check(float(pw.end[1])<float(ps.end[0]),"素質は母で決まる（村娘の耐 %d〜%d・リーナ %d〜%d）"%[int(pw.end[0]),int(pw.end[1]),int(ps.end[0]),int(ps.end[1])])
	check(Make.eggs_for(5)<Make.eggs_for(1),"★が高いほど産める数が少ない")
	# 召喚陣：抽選表の合計は1、名前付きは固有の種族が表に出る
	var table: Array=Eggs.altar_table(strong_w)
	var sum:=0.0
	for t in table:sum+=float(t.p)
	check(absf(sum-1.0)<0.001,"召喚陣の抽選表の合計が1")
	check(table.any(func(t):return t.species=="vow_shell"),"名前付きの卵からは固有の種族が出うる")
	var g: Array=Eggs.grade_table(strong_w)
	var g1: Array=Eggs.grade_table(weak_w)
	check(float(g[2])+float(g[3])>float(g1[2])+float(g1[3]),"★と段階が高いほど稀以上が出やすい")
	# 天井：図鑑にない種族だけになる
	st.altar_miss=int(G.db.balance.altar.pity)
	var fresh: Array=Eggs.altar_table(weak_w)
	check(fresh.all(func(t):return not t.species in st.unlocked.species),"天井に届くと図鑑にない種族だけで引く")
	# 召喚陣で実際に産ませる（精気を払う）
	st.altar_miss=0
	var w2: Dictionary=st.add_woman(Make.woman_from(Make.mob_member("priest",1.6,r),"試験"))
	w2.stage=2
	var altar: Dictionary=st.first_of("altar")
	check(Captive.to_use(w2,"altar",altar)=="","召喚陣へ入れられる")
	st.res.essence=500.0
	var ess: float=float(st.res.essence)
	for i in Eggs.lay_nights():Day.end_day(false)
	check(float(st.res.essence)<ess or int(w2.eggs_done)==1,"召喚陣は精気を払って卵を産む")
	var e2: Dictionary={}
	for e in st.eggs:
		if int(e.mother)==int(w2.uid):e2=e
	check(not e2.is_empty() and int(e2.grade)>=0,"召喚陣の卵には等級がある")
	# 搾り場
	var w3: Dictionary=st.add_woman(Make.woman_from(Make.mob_member("villager",1.0,r),"試験"))
	var press: Dictionary=st.first_of("press")
	Captive.to_use(w3,"press",press)
	Day.end_day(false)
	check(st.report.any(func(e):return str(e.kind)=="income" and "搾り場" in str(e.text)),"搾り場で精気が入る（%d）"%int(Captive.press_amount(w3)))
	# 巣で休むと体力が戻る
	var m: Dictionary=st.monsters[2]
	st.set_job(m,"rest")
	m.hp=5
	Day.end_day(false)
	check(int(m.hp)>5,"巣で休んだ晩は体力が戻る（%d）"%int(m.hp))
	m.hp=0
	check(Stats.heal_cost(m)>Stats.hp_max(m),"体力0からすぐ全快させるのは高い（金 %d）"%Stats.heal_cost(m))
	print("BREED_TEST_DONE bad=",bad)
	quit()
