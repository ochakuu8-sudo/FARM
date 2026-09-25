extends RefCounted
## 一日の進行（企画書 第3章・設計書 第9章）。
##   朝：孵化 → 報告 → 狩場を組む → 自動保存。昼：牧場と出撃（スタミナの許す限り）。夜：房・搾り場・産む・休む → スタミナを戻す → 次の朝。
const G=preload("res://game/core/g.gd")
const Save=preload("res://game/core/save.gd")
const Captive=preload("res://game/breed/captive.gd")
const Eggs=preload("res://game/breed/eggs.gd")
const Sites=preload("res://game/world/sites.gd")

## 新しいゲームの最初の朝（出撃先だけ作る）。
static func first_morning() -> void:
	var st=G.state
	st.world.sites_today=Sites.make_today()
	st.world.chain={};st.world.done=[]
	st.stamina.max=st.stamina_max();st.stamina.now=st.stamina.max
	st.phase="day"

## 「一日を終える」：夜の計算 → 次の朝。孵った魔物の uid を返す。
static func end_day(save: bool=true) -> Array:
	var st=G.state
	st.report=[]
	Captive.night_pass()
	# スタミナを戻す（全部か一定量。企画書で未決）
	st.stamina.max=st.stamina_max()
	var regen=G.db.balance.stamina.regen
	if str(regen)=="full":st.stamina.now=int(st.stamina.max)
	else:st.stamina.now=mini(int(st.stamina.max),int(st.stamina.now)+int(regen))
	st.day+=1
	st.phase="morning"
	var hatched: Array=hatch_due()
	if st.cell_count()>int(st.caps.cell):
		st.log_event("warn","牢があふれている（%d/%d）。あふれた分の使い道を決めるまで出撃できない"%[st.cell_count(),int(st.caps.cell)])
	st.world.sites_today=Sites.make_today()
	st.world.chain={};st.world.done=[]
	st.phase="day"
	if save:Save.save(Save.AUTO)
	return hatched

static func hatch_due() -> Array:
	var st=G.state
	var out: Array=[]
	var due: Array=st.eggs.filter(func(e):return int(e.hatch_day)<=st.day)
	due.sort_custom(func(a,b):return int(a.uid)<int(b.uid))
	for e in due:
		var m: Dictionary=Eggs.hatch(e)
		out.append(int(m.uid))
		st.log_event("hatch","%sが孵った（%s）"%[m.name,G.db.species_name(str(m.species))],{"monster":int(m.uid)})
	return out

static func victory() -> bool:
	return bool(G.state.flags.get("victory",false))

## 出撃できない理由（できるなら ""）。
static func sortie_block() -> String:
	var st=G.state
	if st.cell_count()>int(st.caps.cell):return "牢があふれている（使い道を決める）"
	return ""
