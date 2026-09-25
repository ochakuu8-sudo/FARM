extends RefCounted
## 確認用の途中の状態（--setup=mid）。自動の遊び手で何日か回し、女・魔物・卵・子がそろった昼にする。
##   early：3日  mid：14日  late：30日
const G=preload("res://game/core/g.gd")
const Day=preload("res://game/core/day.gd")
const Auto=preload("res://game/tests/auto_play.gd")

static func apply(kind: String) -> void:
	var days: int={"early":3,"mid":14,"late":30}.get(kind,14)
	for i in days:
		Auto.play_day()
		if Day.victory():break
		Day.end_day(false)
	Auto.build();Auto.assign_women();Auto.assign_monsters()
	G.state.party=Auto.pick_party()
	G.state.flags.milestones=[]
	G.state.report=[]
