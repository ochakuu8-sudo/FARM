extends SceneTree
## 何十日か自動で回す（設計書 11章）。戦闘の勝ち負け・獲得・資源・世代・種族・章を1日1行で出す。
##   Godot_console --headless --path . --script res://game/tests/play_test.gd -- --days=40 [--seed=7]
const G=preload("res://game/core/g.gd")
const Db=preload("res://game/core/db.gd")
const State=preload("res://game/core/state.gd")
const Day=preload("res://game/core/day.gd")
const Auto=preload("res://game/tests/auto_play.gd")
const Stats=preload("res://game/monsters/stats.gd")
func _initialize():call_deferred("run")
func run():
	var args: Dictionary={}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv: PackedStringArray=a.substr(2).split("=",true,1);args[kv[0]]=kv[1]
		elif a.begins_with("--"):args[a.substr(2)]="1"
	G.db=Db.new()
	if not G.db.load_all():
		print("DB_PROBLEMS ",G.db.problems);quit(1);return
	G.state=State.new();G.state.new_game(G.db,int(args.get("seed","7")))
	Day.first_morning()
	var days: int=int(args.get("days","40"))
	var t0:=Time.get_ticks_msec()
	for i in days:
		var st=G.state
		var sum: Dictionary=Auto.play_day()
		var gen:=0;var best:=0.0
		for m in st.monsters:
			gen=maxi(gen,int(m.generation));best=maxf(best,Stats.power(m))
		var uses: Dictionary={}
		for w in st.women:uses[str(w.use)]=int(uses.get(str(w.use),0))+1
		print("DAY %2d ch%d 戦%d 勝%d 捕%d | 女%d %s 卵%d | 魔%d 世代%d 最強%d 種%d | 金%d 精%d スタ%d %s"%[
			st.day,st.chapter,int(sum.fights),int(sum.wins),int(sum.captured),st.women.size(),str(uses),st.eggs.size(),
			st.monsters.size(),gen,int(best),st.unlocked.species.size(),int(st.res.money),int(st.res.essence),int(st.stamina.now),
			("【%s】"%sum.story) if str(sum.story)!="" else ""])
		if Day.victory():print("VICTORY day=",st.day);break
		Day.end_day(false)
	# 保存と読み込みの往復：JSON にして戻しても同じ中身で、続けて遊べる
	var before: String=JSON.stringify(G.state.to_dict())
	var again=State.new();again.from_dict(JSON.parse_string(before))
	G.state=again
	var after: String=JSON.stringify(G.state.to_dict())
	# 整数と小数の書き方（6 と 6.0）の違いは読み直してそろえてから比べる
	var same: bool=JSON.stringify(JSON.parse_string(before))==JSON.stringify(JSON.parse_string(after))
	print("SAVE_ROUNDTRIP ",("OK" if same else "DIFF")," bytes=",before.length())
	for i in 3:
		Auto.play_day()
		if Day.victory():break
		Day.end_day(false)
	var st=G.state
	var sp: Dictionary={}
	for m in st.monsters:sp[m.species]=int(sp.get(m.species,0))+1
	print("PLAY_DONE days=%d ms=%d women=%d monsters=%d born=%d captured=%d chapter=%d wins=%d losses=%d species=%s"%[st.day,Time.get_ticks_msec()-t0,st.women.size(),st.monsters.size(),int(st.records.born),int(st.records.captured),st.chapter,int(st.records.wins),int(st.records.losses),str(sp)])
	quit()
