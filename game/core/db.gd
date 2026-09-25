extends RefCounted
## 静的データ（game/data/*.json）の読み込みと検証。読み取り専用（設計書 2.1）。
const DIR:="res://game/data/"
const Profiles=preload("res://game_v2/animation/profiles.gd")
const STATS:=["str","mag","spd","end"]
const EFFECTS:=["damage","heal","shield","status","cleanse","jump","drain_charge"]
const STATUSES:=["bind","slow","weak","stun","taunt","guard","last_stand","haste"]
const MODS:=["armor","hp_pct","str_pct","mag_pct","spd_pct","end_pct","move","reach","start_charge","charge_mul","regen","lifesteal","thorns",
	"last_stand","first_strike","bind_tick","status_bonus","skill_targets","area_bonus","on_hit_slow","on_hit_weak","on_hit_poison","anti_heal","evade_first","cleave","atk_speed","start_hidden","kill_charge","aura_heal"]
const AIS:=["basic","guard","healer","flank","caster","bruiser"]
var balance: Dictionary={}
var jobs: Dictionary={}
var women: Dictionary={}
var mob: Dictionary={}
var species: Dictionary={}
var skills: Dictionary={}
var inherit_pool: Dictionary={}
var rooms: Dictionary={}
var world: Dictionary={}
var regions: Array=[]
var stages: Dictionary={}
var boards: Dictionary={}
var texts: Dictionary={}
var problems: Array=[]

func load_all() -> bool:
	problems=[]
	balance=read("balance");jobs=read("jobs");women=read("women");mob=read("mob_rules")
	species=read("species");skills=read("skills");inherit_pool=read("inherit_pool");rooms=read("rooms")
	world=read("world");texts=read("texts")
	regions=world.get("regions",[]);stages=world.get("stages",{});boards=world.get("boards",{})
	validate()
	return problems.is_empty()

func read(name: String) -> Dictionary:
	var path:=DIR+name+".json"
	if not FileAccess.file_exists(path):problems.append("ファイルがありません: "+path);return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:problems.append("JSONの形が不正: "+path);return {}
	data.erase("_note")
	return data

func validate() -> void:
	var profiles: Array=Profiles.ids()
	for id in skills:
		var s: Dictionary=skills[id]
		if not str(s.get("kind","")) in ["active","passive"]:problems.append("スキルの種類が不正: "+id)
		for e in s.get("effects",[]):
			if not str(e.get("t","")) in EFFECTS:problems.append("スキルの効果が不正: %s %s"%[id,str(e.get("t",""))])
			if str(e.get("t",""))=="status" and not str(e.get("status","")) in STATUSES:problems.append("スキルの状態が不正: %s %s"%[id,str(e.get("status",""))])
		for k in s.get("mods",{}):
			if not k in MODS:problems.append("パッシブの値が不正: %s %s"%[id,k])
	for id in species:
		var d: Dictionary=species[id]
		if not str(d.get("profile","")) in profiles:problems.append("種族の原型が未登録: "+id)
		if not skills.has(str(d.get("active",""))):problems.append("種族のアクティブが未登録: "+id)
		if d.get("passives",[]).size()!=3:problems.append("種族のパッシブは3つ: "+id)
		for p in d.get("passives",[]):
			if not skills.has(str(p.skill)):problems.append("種族のパッシブが未登録: %s %s"%[id,str(p.skill)])
			for k in p.get("need",{}):
				if not k in STATS:problems.append("パッシブの条件が不正: %s %s"%[id,k])
		if d.has("unique_of") and not women.has(str(d.unique_of)):problems.append("固有の種族の母が未登録: "+id)
	for id in inherit_pool:
		if not skills.has(id):problems.append("継承のパッシブが未登録: "+id)
	for id in jobs:
		var j: Dictionary=jobs[id]
		if not str(j.get("ai","")) in AIS:problems.append("職の動き方が不正: "+id)
		if str(j.get("skill",""))!="" and not skills.has(str(j.skill)):problems.append("職のスキルが未登録: "+id)
		for k in STATS:
			if not j.get("stats",{}).has(k):problems.append("職の能力が足りない: %s %s"%[id,k])
		for sp in j.get("altar",{}):
			if not species.has(sp):problems.append("召喚陣の種族が未登録: %s %s"%[id,sp])
	for id in women:
		var w: Dictionary=women[id]
		if not jobs.has(w.get("job","")):problems.append("女の職が未登録: "+id)
		if not str(w.get("weak","")) in STATS:problems.append("女の弱点が不正: "+id)
		if not skills.has(str(w.get("unique",""))):problems.append("女の固有スキルが未登録: "+id)
		if not species.has(str(w.get("species",""))):problems.append("女の固有の種族が未登録: "+id)
		for rel in w.get("relations",[]):
			if not women.has(rel.to):problems.append("関係の相手が未登録: "+id+" → "+str(rel.to))
	for id in rooms:
		var r: Dictionary=rooms[id]
		if not str(r.get("kind","")) in ["cell","den","house","nursery","altar","press","deco"]:problems.append("施設の種類が不正: "+id)
		if r.get("kind","")=="house" and not str(r.get("house","")) in STATS:problems.append("房の能力が不正: "+id)
	for b in boards:
		var rows: Array=boards[b]
		var bw: int=int(balance.get("board",[14,8])[0]);var bh: int=int(balance.get("board",[14,8])[1])
		if rows.size()!=bh:problems.append("地形の行数が%dでない: %s"%[bh,b])
		for row in rows:
			if str(row).length()!=bw:problems.append("地形の列数が%dでない: %s「%s」"%[bw,b,str(row)])
			elif str(row).substr(0,4)!="....":problems.append("地形の左の4列（置き場）が床でない: %s「%s」"%[b,str(row)])
			elif str(row).substr(0,2)!="..":problems.append("地形の左2列は床にする: "+b)
	for r in regions:
		for h in r.get("hunts",[]):
			if not boards.has(str(h.get("board",""))):problems.append("狩場の地形が未登録: "+str(h.id))
			for j in h.get("jobs",{}):
				if not jobs.has(j):problems.append("狩場の職が未登録: %s %s"%[str(h.id),j])
		for s in r.get("story",[]):
			if not stages.has(s):problems.append("ストーリー戦が未登録: "+str(s))
	for id in stages:
		var s: Dictionary=stages[id]
		if not boards.has(str(s.get("board",""))):problems.append("ストーリー戦の地形が未登録: "+id)
		for fight in s.get("chain",[]):
			for m in fight.party:
				if not jobs.has(str(m.job)):problems.append("ストーリー戦の職が未登録: %s %s"%[id,str(m.job)])
				if m.has("named") and not women.has(str(m.named)):problems.append("ストーリー戦の名前付きが未登録: %s %s"%[id,str(m.named)])

# ───────── よく使う引き ─────────
func region(i: int) -> Dictionary:
	return regions[clampi(i,0,regions.size()-1)]

func region_index(id: String) -> int:
	for i in regions.size():
		if str(regions[i].id)==id:return i
	return -1

## 章ごとの配列から今の章の値を引く（[序章, 1章, …]）。
func pick(a: Array,ch: int):
	return a[clampi(ch,0,a.size()-1)]

func woman_name(id: String) -> String:
	return str(women.get(id,{}).get("name",id))

func stat_name(k: String) -> String:
	return {"str":"力","mag":"魔","spd":"速","end":"耐"}.get(k,k)

func skill(id: String) -> Dictionary:
	return skills.get(id,{})

func skill_name(id: String) -> String:
	return str(skills.get(id,{}).get("name",id))

func species_name(id: String) -> String:
	return str(species.get(id,{}).get("name",id))

## 能力の条件を満たしているか（{str: 60, end: 60} など）。
static func meets(stats: Dictionary,need: Dictionary) -> bool:
	for k in need:
		if float(stats.get(k,0))<float(need[k]):return false
	return true
