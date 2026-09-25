extends SceneTree
## 牧場のタッチ操作の確かめ（画面あり）：タップで施設を選ぶ・1本指でずらす（選ばない）・2本指でつまんで拡大縮小・＋－ボタン。
##   Godot_console --path . --script res://game/tests/touch_check.gd [-- --touch]
const G=preload("res://game/core/g.gd")
var bad:=0
func _initialize():call_deferred("run")
func check(ok: bool,what: String) -> void:
	print(("OK   " if ok else "FAIL ")+what)
	if not ok:bad+=1

func win(at: Vector2) -> Vector2:
	return root.get_final_transform()*at

func touch(index: int,at: Vector2,pressed: bool) -> void:
	var e:=InputEventScreenTouch.new();e.index=index;e.position=win(at);e.pressed=pressed
	Input.parse_input_event(e)
	await process_frame

func drag(index: int,from: Vector2,to: Vector2,steps: int=6) -> void:
	for i in range(1,steps+1):
		var e:=InputEventScreenDrag.new();e.index=index;e.position=win(from.lerp(to,float(i)/steps));e.relative=win(to-from)/steps
		Input.parse_input_event(e)
		await process_frame

func run():
	var main: Node=load("res://game/main.tscn").instantiate()
	root.add_child(main)
	while G.main==null or G.main.current_name!="title":await create_timer(0.3).timeout
	if not G.anim.ready_ok:await G.anim.loaded
	G.state=load("res://game/core/state.gd").new();G.state.new_game(G.db,5)
	load("res://game/core/day.gd").first_morning()
	load("res://game/tests/debug_setup.gd").apply("mid")
	G.state.flags.help_seen={"ranch":true,"world":true,"prep":true,"battle":true}
	G.main.goto("ranch",{})
	await create_timer(2.0).timeout
	var scr=G.main.current;var map=scr.map
	map.zoom=1.6;await create_timer(0.3).timeout
	# タップ：施設の上を押して離すと選ぶ
	var f: Dictionary=G.state.facilities.filter(func(x):return G.state.kind_of(x)=="house")[0]
	var at: Vector2=map.to_screen(G.state.fac_center(f))
	await touch(0,at,true);await touch(0,at,false)
	await create_timer(0.3).timeout
	check(map.selected==int(f.uid),"タップで施設を選ぶ（%d）"%map.selected)
	scr.cancel();await create_timer(0.4).timeout
	# 1本指でずらす：地図が動き、選ばない
	var cam0: Vector2=map.cam
	await touch(0,at,true);await drag(0,at,at+Vector2(-300,-120));await touch(0,at+Vector2(-300,-120),false)
	await create_timer(0.2).timeout
	check(map.cam.distance_to(cam0)>0.5,"1本指でずらす（カメラ %s → %s）"%[str(cam0),str(map.cam)])
	check(map.selected==-1,"ずらしたときは選ばない")
	# 2本指でつまむ：広げると拡大、指の間の地点は動かない
	var z0: float=map.zoom
	var mid:=Vector2(950,520)
	var cell_mid: Vector2=map.cell_at_screen(mid)
	await touch(0,mid-Vector2(80,0),true);await touch(1,mid+Vector2(80,0),true)
	for i in range(1,7):
		var e1:=InputEventScreenDrag.new();e1.index=0;e1.position=win(mid-Vector2(80+i*25,0));Input.parse_input_event(e1)
		var e2:=InputEventScreenDrag.new();e2.index=1;e2.position=win(mid+Vector2(80+i*25,0));Input.parse_input_event(e2)
		await process_frame
	await touch(1,mid+Vector2(230,0),false);await touch(0,mid-Vector2(230,0),false)
	await create_timer(0.2).timeout
	check(map.zoom>z0*1.5,"2本指で広げると拡大（%.2f → %.2f）"%[z0,map.zoom])
	check(map.cell_at_screen(mid).distance_to(cell_mid)<0.15,"指の間の地点がずれない（%.3f）"%map.cell_at_screen(mid).distance_to(cell_mid))
	check(map.selected==-1,"つまんだあとは選ばない")
	# ＋－ボタン（タッチの端末だけ）
	if scr.zoom_box!=null:
		var z1: float=map.zoom
		(scr.zoom_box.get_child(1) as Button).pressed.emit()
		check(map.zoom<z1,"－ボタンで縮小（%.2f → %.2f）"%[z1,map.zoom])
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://game/tests/out_touch.png")
	print("TOUCH_CHECK bad=",bad)
	quit()
