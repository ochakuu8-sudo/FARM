extends SceneTree
## 本物のクリックで操作できるか（画面あり）：施設を建てる・選ぶ・右クリックでやめる・窓の行を押す・出撃先を選ぶ・
## 魔物を置く。戦闘は自動（リアルタイム）なので、始めたら時間が進み、役者がマス目にとらわれず動くかを見る。
##   Godot_console --path . --script res://game/tests/input_check.gd
const G=preload("res://game/core/g.gd")
var bad:=0
func _initialize():call_deferred("run")
func check(ok: bool,what: String) -> void:
	print(("OK   " if ok else "FAIL ")+what)
	if not ok:bad+=1

func click(at: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
	var win: Vector2=root.get_final_transform()*at
	var mv:=InputEventMouseMotion.new();mv.position=win;mv.global_position=win
	Input.parse_input_event(mv)
	await process_frame
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=pressed;e.position=win;e.global_position=win
		if pressed:e.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		Input.parse_input_event(e)
		await process_frame
	await process_frame

func run():
	var main: Node=load("res://game/main.tscn").instantiate()
	root.add_child(main)
	while G.main==null or G.main.current_name!="title":await create_timer(0.3).timeout
	if not G.anim.ready_ok:await G.anim.loaded
	G.state=load("res://game/core/state.gd").new();G.state.new_game(G.db,5)
	load("res://game/core/day.gd").first_morning()
	G.state.flags.help_seen={"ranch":true,"world":true,"prep":true,"battle":true}
	G.state.res.money=3000.0
	G.main.goto("ranch",{})
	await create_timer(1.5).timeout
	var scr=G.main.current
	var map=scr.map
	map.zoom=2.0;map.cam=Vector2(12,9)
	await create_timer(0.5).timeout
	var st=G.state
	# 施設を建てる
	scr.set_mode("build");scr.build_def="trash"
	var n: int=st.facilities.size()
	await click(map.to_screen(Vector2(12.5,8.5)))
	check(st.facilities.size()==n+1,"建てるモードで床を押すと施設が建つ")
	await click(map.to_screen(Vector2(12.5,8.5)),MOUSE_BUTTON_RIGHT)
	check(scr.mode=="view","右クリックで見るモードに戻る（%s）"%scr.mode)
	# 施設を押すと選べる
	var f: Dictionary=st.fac_at(12,8)
	await click(map.to_screen(st.fac_center(f)))
	check(not f.is_empty() and map.selected==int(f.uid),"施設を押すと選べて右に詳細が出る")
	check(scr.right_panel.visible,"右の欄が出ている")
	# 窓の中の行を押す
	load("res://game/tests/debug_setup.gd").apply("early")
	for wn in ["captives","monsters","eggs","book"]:
		G.main.open_window(wn)
		await create_timer(0.4).timeout
		var pressed:=0
		for i in 3:
			var top: Control=G.main.top_overlay()
			var rows: Array=top.find_children("*","PanelContainer",true,false).filter(func(c):return c.mouse_filter==Control.MOUSE_FILTER_STOP and not c.gui_input.get_connections().is_empty())
			if rows.size()<=i:break
			var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
			rows[rows.size()-1-i].gui_input.emit(e)
			pressed+=1
			await create_timer(0.2).timeout
		check((pressed>0 or wn in ["book","eggs"]) and G.main.has_overlay(),"%sの窓を開いて行を押せる（%d回）"%[wn,pressed])
		G.main.close_all_overlays()
		await create_timer(0.3).timeout
	# 牧場：女の札を地図の施設へ引きずって入れる／魔物を選んで光る施設を押す
	G.main.goto("ranch",{})
	await create_timer(1.5).timeout
	scr=G.main.current;map=scr.map
	var Cards=load("res://game/ui/parts/cards.gd")
	var cw: Array=st.women_in("cell")
	var house: Dictionary=st.first_of("house")
	if not cw.is_empty() and not house.is_empty():
		var w0: Dictionary=cw[0]
		scr.tab="woman";scr.refresh_left()
		await process_frame
		var tile: Control=null
		var found:=false
		for c in scr.left_box.get_children():
			if c is PanelContainer and c.tooltip_text==Cards.woman_title(w0):tile=c;found=true;break
		map.cam=st.fac_center(house);map.zoom=1.6
		await create_timer(0.4).timeout
		if tile!=null:
			var from: Vector2=root.get_final_transform()*tile.get_global_rect().get_center()
			var to: Vector2=root.get_final_transform()*map.to_screen(st.fac_center(house))
			var e1:=InputEventMouseButton.new();e1.button_index=MOUSE_BUTTON_LEFT;e1.pressed=true;e1.position=from;e1.global_position=from;e1.button_mask=MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(e1);await process_frame
			for i in 8:
				var mv:=InputEventMouseMotion.new();mv.position=from.lerp(to,(i+1)/8.0);mv.global_position=mv.position;mv.button_mask=MOUSE_BUTTON_MASK_LEFT
				Input.parse_input_event(mv);await process_frame
			var e2:=InputEventMouseButton.new();e2.button_index=MOUSE_BUTTON_LEFT;e2.pressed=false;e2.position=to;e2.global_position=to
			Input.parse_input_event(e2);await process_frame;await process_frame
		check(found and str(w0.use)=="house","女の札を房へ引きずって落とすと入る（%s）"%str(w0.use))
		var mon: Dictionary={}
		for m in st.monsters:
			if not int(m.uid) in st.party and int(house.monster)!=int(m.uid):mon=m;break
		if mon.is_empty():mon=st.monsters[-1]
		scr.hold("monster",int(mon.uid))
		await create_timer(0.3).timeout
		check(map.highlight.has(int(house.uid)),"魔物を選ぶと房が光る")
		await click(map.to_screen(st.fac_center(house)))
		check(str(mon.job)=="partner" and int(house.monster)==int(mon.uid),"光る房を押すと相手役になる（%s）"%str(mon.job))
	# 大陸の地図で出撃先を押す
	G.main.goto("world",{})
	await create_timer(1.2).timeout
	var ws=G.main.current
	var hit: Dictionary=ws.canvas.hits[-1] if not ws.canvas.hits.is_empty() else {}
	if not hit.is_empty():
		await click(ws.canvas.get_global_transform()*(hit.rect.get_center()))
	check(not hit.is_empty() and ws.selected==str(hit.id),"地図の出撃先を押すと選べる")
	# 編成：一覧の魔物を外して置き直す
	ws.go()
	await create_timer(1.5).timeout
	var ps=G.main.current
	var u: int=int(st.party[0])
	ps.pick(u);ps.pick(u)
	check(not u in st.party,"選んだ魔物をもう一度押すと外れる")
	ps.pick(u)
	var cell: Vector2i=ps.home[-1]
	await click(ps.view.to_screen(Vector2(cell)+Vector2(0.5,0.5)))
	await create_timer(0.2).timeout
	var p=st.placement.get(str(u),[-1,-1])
	check(u in st.party and Vector2i(int(p[0]),int(p[1]))==cell,"盤の青いマスを押すと置ける（%s）"%str(p))
	# 戦闘：自動で時間が進み、役者が途中の位置を通って動く。Space で止まる
	ps.start()
	await create_timer(2.0).timeout
	var bs=G.main.current
	check(bs.sim.t>0.5,"戦闘の時間が進む（%.1f秒）"%bs.sim.t)
	var off:=false
	for x in bs.sim.units:
		var fp: Vector2=(x.pos as Vector2)-Vector2(0.5,0.5)
		if absf(fp.x-round(fp.x))>0.05 or absf(fp.y-round(fp.y))>0.05:off=true
	check(off,"役者がマス目にとらわれず動く")
	var sp:=InputEventKey.new();sp.keycode=KEY_SPACE;sp.pressed=true
	Input.parse_input_event(sp);await process_frame;await process_frame
	var t0: float=bs.sim.t
	await create_timer(0.5).timeout
	check(bs.paused and is_equal_approx(bs.sim.t,t0),"Space で止まる")
	print("INPUT_CHECK_DONE bad=",bad)
	quit()
