extends RefCounted
## 出撃先の k 戦目と、編成・配置から戦闘を組む（設計書 3章）。
const G=preload("res://game/core/g.gd")
const Sites=preload("res://game/world/sites.gd")
const Sim=preload("res://game/battle/sim.gd")
const Stats=preload("res://game/monsters/stats.gd")
const HOME_ROWS:=[3,4,2,5,1,6,0,7]
## こちらの置き場の列（前から）。
const HOME_COLS:=[3,2,1,0]

## 一行を並べた戦闘の中身 {board, party}（出撃先の記録は書き換えない）。
static func fight(site: Dictionary,k: int) -> Dictionary:
	var party: Array=site.chain[k].party.duplicate(true)
	for m in party:
		var st: Dictionary={}
		for s in m.stats:st[s]=float(m.stats[s])
		m.stats=st;m.star=int(m.star)
	Sites.place_party(party,site.board)
	return {"board":site.board,"party":party}

## 置き場のマス（左の4列）。
static func home_cells(board: Array) -> Array:
	var out: Array=[]
	for x in HOME_COLS:
		for y in HOME_ROWS:
			if str(board[y]).substr(x,1)!="#":out.append(Vector2i(x,y))
	return out

## 編成（魔物の uid）と配置から、戦闘に出す [{m, pos}]。配置が無い・重なる者は空いている置き場へ。
static func team(uids: Array,board: Array) -> Array:
	var st=G.state
	var out: Array=[]
	var used: Dictionary={}
	var cells: Array=home_cells(board)
	var list: Array=[]
	for u in uids:
		var m: Dictionary=st.monster(int(u))
		if m.is_empty() or not Stats.can_fight(m):continue
		list.append(m)
	for m in list:
		var p=st.placement.get(str(int(m.uid)),null)
		var c:=Vector2i(-1,-1)
		if p!=null:c=Vector2i(int(p[0]),int(p[1]))
		if c.x<0 or used.has(c) or not c in cells:
			c=Vector2i(-1,-1)
			for cc in cells:
				if not used.has(cc):c=cc;break
		used[c]=true
		out.append({"m":m,"pos":c})
	return out

static func start(site: Dictionary,k: int,uids: Array,script: Array=[]):
	var f: Dictionary=fight(site,k)
	var sim=Sim.new()
	var tm: Array=team(uids,site.board)
	sim.setup(f,tm+minions(site.board,tm),script)
	return sim

## 雑兵（こちらが連れて行く名前のない兵。数は balance.minions、強さは章で上がる）。魔物の前の空いている置き場に並ぶ。
## 雑兵は戦闘の中だけの者で、体力も記録も持ち越さない。魔物が全員倒れたら逃げ散る（負け）。
static func minions(board: Array,tm: Array) -> Array:
	var b: Dictionary=G.db.balance.get("minions",{})
	var n: int=int(b.get("count",0))
	if n<=0:return []
	var used: Dictionary={}
	for t in tm:used[t.pos]=true
	var v: float=float(b.get("base",16))+float(b.get("per_chapter",6))*float(G.state.chapter if G.state!=null else 0)
	var out: Array=[]
	for c in home_cells(board):
		if out.size()>=n:break
		if used.has(c):continue
		used[c]=true
		out.append({"minion":{"name":"雑兵","stats":{"str":v,"mag":v*0.5,"spd":v,"end":v},"hp_base":float(b.get("hp_base",20)),"atk":float(b.get("atk",3))},"pos":c})
	return out
