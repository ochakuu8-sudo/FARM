extends RefCounted
## 重さの計測（起動の引数 --debug=bench --setup=mid）。ブラウザ版の計測（game_v2/tools/web_bench.py）でも使う。
## 結果は1行ずつ "BENCH 名前 値…" で出す：起動までの時間、牧場に入る時間、牧場・引いた牧場・戦闘のフレームの時間。
const G=preload("res://game/core/g.gd")

## フレームの時間と、その内訳（スクリプトの処理・描画の CPU 側・描画の準備）。
static func frames(tree: SceneTree,label: String,secs: float) -> void:
	var vp: RID=tree.root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp,true)
	var t0:=Time.get_ticks_usec();var last:=t0;var worst:=0;var n:=0
	var proc:=0.0;var render:=0.0;var setup:=0.0;var draws:=0.0;var items:=0.0
	while Time.get_ticks_usec()-t0<int(secs*1000000.0):
		await tree.process_frame
		var now:=Time.get_ticks_usec();worst=maxi(worst,now-last);last=now;n+=1
		proc+=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
		render+=RenderingServer.viewport_get_measured_render_time_cpu(vp)
		setup+=RenderingServer.get_frame_setup_time_cpu()
		draws+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		items+=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	n=maxi(n,1)
	print("BENCH %s frame_ms=%.1f worst_ms=%.0f fps=%.1f process_ms=%.1f render_cpu_ms=%.1f setup_ms=%.1f draw_calls=%.0f"%[label,(Time.get_ticks_usec()-t0)/1000.0/n,worst/1000.0,n/secs,proc/n,render/n,setup/n,draws/n])

## 画面を切り替えて、次のフレームが描けるまで（読み込み・着せ替えで止まる時間）。
static func enter(tree: SceneTree,main: Node,screen: String,params: Dictionary) -> void:
	var t0:=Time.get_ticks_usec()
	main.goto(screen,params)
	await tree.process_frame
	await tree.process_frame
	var first:=Time.get_ticks_usec()-t0
	# 役者・場面の読み込みは最初の数フレームに散らばるので、1秒のうちいちばん長いフレームも出す
	var worst:=0;var last:=Time.get_ticks_usec()
	while Time.get_ticks_usec()-t0<1500000:
		await tree.process_frame
		var now:=Time.get_ticks_usec();worst=maxi(worst,now-last);last=now
	print("BENCH enter_%s first_ms=%.0f worst_ms=%.0f"%[screen,first/1000.0,worst/1000.0])

static func run(main: Node) -> void:
	var tree: SceneTree=main.get_tree()
	print("BENCH startup_ms=%d lite=%s"%[int(main.anim_ready_ms),str(preload("res://game/core/perf.gd").lite)])
	# タイトルで待っている間の先読み（main.warm_up）と同じ：画面のスクリプトを読む時間
	var tw:=Time.get_ticks_usec()
	for path in main.SCREENS.values():load(path)
	print("BENCH warm_up_ms=%.0f"%[(Time.get_ticks_usec()-tw)/1000.0])
	await enter(tree,main,"ranch",{})
	await frames(tree,"ranch",5.0)
	var map=main.current.map
	map.zoom=0.9
	await frames(tree,"ranch_wide",4.0)
	print("BENCH ranch_scenes=%d actors=%d"%[map.scenes.size(),map.actors.size()])
	# 内訳：UI（一覧・上下の帯）を隠したとき
	var hidden: Array=[]
	for c in main.current.get_children():
		if c is Control and c.visible:c.visible=false;hidden.append(c)
	await frames(tree,"ranch_no_ui",2.0)
	for c in hidden:c.visible=true
	var Sites=load("res://game/world/sites.gd")
	var params: Dictionary=main.debug_site(Sites)
	if G.state.party.is_empty():load("res://game/tests/auto_play.gd").pick_party()
	await enter(tree,main,"battle",params)
	main.auto_battle()
	await frames(tree,"battle",5.0)
	print("BENCH done")
	if not OS.has_feature("web"):tree.quit()
