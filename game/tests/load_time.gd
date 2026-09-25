extends SceneTree
## 読み込み時間の内訳（画面あり）：起動（動作データ）→ タイトル → 牧場（役者を着せる）。ブラウザ版の暗転の長さの目安。
##   Godot_console --path . --script res://game/tests/load_time.gd [-- --baked-looks] [--prof]（--prof は prof.gd で測っている所の内訳）
const G=preload("res://game/core/g.gd")
func _initialize():call_deferred("run")
func ms(t0: int) -> String:
	return "%.0fms"%((Time.get_ticks_usec()-t0)/1000.0)
func run():
	var t0:=Time.get_ticks_usec()
	var main: Node=load("res://game/main.tscn").instantiate()
	root.add_child(main)
	while G.anim==null:await process_frame
	if not G.anim.ready_ok:await G.anim.loaded
	print("  動作データの準備 ",ms(t0))
	G.state=load("res://game/core/state.gd").new();G.state.new_game(G.db,5)
	load("res://game/core/day.gd").first_morning()
	load("res://game/tests/debug_setup.gd").apply("mid")
	G.state.flags.help_seen={"ranch":true,"world":true,"prep":true,"battle":true}
	var store=G.anim.bridge.resources
	# 1フレームずつ、牧場に入ってから役者が揃うまで
	var Prof=load("res://mini/layered2d/prepare/prof.gd");Prof.on="--prof" in OS.get_cmdline_user_args();Prof.reset()
	var t1:=Time.get_ticks_usec()
	G.main.goto("ranch",{})
	var worst:=0;var frames:=0;var last:=Time.get_ticks_usec()
	var commits_before: int=store.uploads
	while Time.get_ticks_usec()-t1<4000000:
		await process_frame
		var now:=Time.get_ticks_usec();worst=maxi(worst,now-last);last=now;frames+=1
	var map=G.main.current.map
	if Prof.on:print(Prof.report());Prof.on=false
	print("  牧場：役者 %d 場面 %d  いちばん長いフレーム %.0fms  %d フレーム/4秒"%[map.actors.size(),map.scenes.size(),worst/1000.0,frames])
	# 着せ替えの内訳：役者1人を新しく借りて着せる時間（見た目の読み込みを含む）
	var Look=load("res://game/map/look.gd")
	var ids: Array=[]
	var t2:=Time.get_ticks_usec()
	for w in G.state.women.slice(0,6):
		var id: String=Look.dress(Look.woman(w),1.0)
		if id!="":ids.append(id)
	print("  6人を着せる（見た目は読み込み済み） ",ms(t2))
	var t3:=Time.get_ticks_usec()
	G.anim.bridge.sync_stream()
	print("  GPU へ送る（commit） ",ms(t3))
	for id in ids:G.anim.release(id)
	print("LOAD_TIME done")
	quit()
