extends SceneTree
## 戦闘の面白さの物差し（画面なし）。構成と配置で勝ちがどれだけ変わるかを測る。
##   Godot_console --headless --path . --script res://game/tests/battle_balance.gd [-- --regions=0,1,2 --n=24]
## 地方ごとに：
##   1. 何も考えない構成（ランダムな4種・決まった並べ方）で勝ちが5割になる能力の値 L を探す（その地方の「適正」）。
##   2. L で、考えた構成（COMPS）それぞれの勝ちの割合。一番よい構成と、ランダムとの差。
##   3. 一番よい構成を、置き場の中でランダムに並べ替えたときの勝ちの割合の幅（配置の効き）。
## 目安：ランダム5割に対して、よい構成は8割以上、配置で2割以上の差が出るとよい。
const G=preload("res://game/core/g.gd")
const Db=preload("res://game/core/db.gd")
const State=preload("res://game/core/state.gd")
const Day=preload("res://game/core/day.gd")
const Setup=preload("res://game/battle/setup.gd")
const Sim=preload("res://game/battle/sim.gd")
const Sites=preload("res://game/world/sites.gd")
const Stats=preload("res://game/monsters/stats.gd")
const Make=preload("res://game/core/make.gd")
## 考えた構成（前から順に置く想定）。
const COMPS:=[
	["golem","myconid","goblin_archer","imp"],
	["carapace","drum_ogre","kamaitachi","goblin_archer"],
	["golem","goblin_archer","goblin_archer","myconid"],
	["tentacle","serpent","imp","myconid"],
	["carapace","kamaitachi","kamaitachi","wisp"],
	["golem","holy","imp","wisp"],
	["beast","kamaitachi","drum_ogre","myconid"],
	["slime","tentacle","imp","goblin_archer"],
]
var normal: Array=[]
var n_fights:=24

func _initialize():call_deferred("run")

func run():
	G.db=Db.new();G.db.load_all();G.state=State.new();G.state.new_game(G.db,7);Day.first_morning()
	normal=G.db.species.keys().filter(func(s):return not G.db.species[s].has("unique_of"))
	var regions: Array=[0,1,2,3,4,5,6]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--regions="):regions=Array(a.substr(10).split(",")).map(func(x):return int(x))
		if a.begins_with("--n="):n_fights=int(a.substr(4))
	print("地方        適正L  ランダム  よい構成（一番）            差    配置の幅  秒（平均）")
	for ri in regions:
		G.state.chapter=ri
		var fights: Array=fights_of(ri)
		var lo:=10.0;var hi:=100.0
		for it in 7:
			var mid: float=(lo+hi)*0.5
			if rate_random(fights,mid,11)<0.5:lo=mid
			else:hi=mid
		var L: float=snappedf((lo+hi)*0.5,1.0)
		var rnd: float=rate_random(fights,L,23)
		var best:=0.0;var best_c: Array=[];var secs:=0.0
		for c in COMPS:
			var r: Array=rate_comp(fights,L,c)
			if r[0]>best:best=r[0];best_c=c
			secs+=r[1]
		var spread: Array=placement_spread(fights,L,best_c)
		print("%-10s %5.0f  %5.0f%%   %5.0f%% %-26s %+5.0f  %3.0f%%〜%3.0f%%  %5.1f"%[G.db.regions[ri].name,L,rnd*100,best*100,"・".join(best_c.map(func(s):return G.db.species_name(s))),(best-rnd)*100,spread[0]*100,spread[1]*100,secs/COMPS.size()])
	quit()

func fights_of(ri: int) -> Array:
	var r: Dictionary=G.db.regions[ri]
	var out: Array=[]
	var sites: Array=[]
	for h in r.hunts:sites.append(Sites.hunt_site(r,h))
	for s in r.story:sites.append(Sites.story_site(r,s))
	for s in sites:
		for k in s.chain.size():out.append({"site":s,"k":k})
	return out

func fake(sp: String,v: float) -> Dictionary:
	var m: Dictionary=Make.base_monster(sp);m.uid=G.state.uid()
	for k in ["str","mag","spd","end"]:m.apt[k]=v;m.stats[k]=v
	m.name=G.db.species_name(sp);m.hp=Stats.hp_max(m)
	return m

## 決まった並べ方：前の列から順に（盾・前衛が前、後ろほど後衛の想定）。
func default_cells(board: Array) -> Array:
	return [Vector2i(3,3),Vector2i(3,4),Vector2i(1,3),Vector2i(1,4)]

func battle(f: Dictionary,team: Array,cells: Array) -> Dictionary:
	var tm: Array=[]
	for i in team.size():tm.append({"m":team[i],"pos":cells[i]})
	var sim=Sim.new()
	sim.setup(Setup.fight(f.site,f.k),tm+Setup.minions(f.site.board,tm))
	return sim.run_all()

func rate_random(fights: Array,v: float,seed_v: int) -> float:
	var rng:=RandomNumberGenerator.new();rng.seed=seed_v
	var w:=0;var n:=0
	for i in n_fights:
		var f: Dictionary=fights[i%fights.size()]
		var team: Array=[]
		for j in 4:team.append(fake(normal[rng.randi()%normal.size()],v))
		if battle(f,team,default_cells(f.site.board)).won:w+=1
		n+=1
	return float(w)/n

func rate_comp(fights: Array,v: float,comp: Array) -> Array:
	var w:=0;var n:=0;var secs:=0.0
	for i in n_fights:
		var f: Dictionary=fights[i%fights.size()]
		var team: Array=comp.map(func(s):return fake(s,v))
		var r: Dictionary=battle(f,team,default_cells(f.site.board))
		if r.won:w+=1
		n+=1;secs+=float(r.secs)
	return [float(w)/n,secs/n]

## 同じ構成を、置き場の中で12通りにランダムに並べたときの勝ちの割合の最小と最大。
func placement_spread(fights: Array,v: float,comp: Array) -> Array:
	var rng:=RandomNumberGenerator.new();rng.seed=77
	var rates: Array=[]
	for p in 12:
		var cells: Array=Setup.home_cells(fights[0].site.board)
		for i in range(cells.size()-1,0,-1):
			var j: int=rng.randi()%(i+1);var tmp=cells[i];cells[i]=cells[j];cells[j]=tmp
		var w:=0
		for i in n_fights/2:
			var f: Dictionary=fights[i%fights.size()]
			var team: Array=comp.map(func(s):return fake(s,v))
			var hc: Array=Setup.home_cells(f.site.board)
			var use: Array=cells.slice(0,4).filter(func(c):return c in hc)
			while use.size()<4:use.append(hc[use.size()])
			if battle(f,team,use).won:w+=1
		rates.append(float(w)/(n_fights/2))
	return [rates.min(),rates.max()]
