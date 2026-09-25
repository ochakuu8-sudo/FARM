extends SceneTree
## 牧場のシチュエーションづくりの確かめ（画面あり）：1マスの家具を詰めて置く・動かす・回す、施設ごとに場面・表情・服を選ぶ、飾り。
##   Godot_console --path . --script res://game/tests/ranch_scene_check.gd [-- --prof]（--prof で1フレームの内訳を測る）
const G=preload("res://game/core/g.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
var bad:=0
func _initialize():call_deferred("run")
func check(ok: bool,what: String) -> void:
	print(("OK   " if ok else "FAIL ")+what)
	if not ok:bad+=1

func run():
	var main: Node=load("res://game/main.tscn").instantiate()
	root.add_child(main)
	while G.main==null or G.main.current_name!="title":await create_timer(0.3).timeout
	if not G.anim.ready_ok:await G.anim.loaded
	G.state=load("res://game/core/state.gd").new();G.state.new_game(G.db,5)
	load("res://game/core/day.gd").first_morning()
	load("res://game/tests/debug_setup.gd").apply("mid")
	G.state.flags.help_seen={"ranch":true,"world":true,"prep":true,"battle":true}
	var st=G.state
	st.res.money=99999.0
	# 1マスの家具を詰めて並べる（隣どうし）
	var defs: Array=["bondage","table","pillory","post","sweet","trash"]
	var placed: Array=[]
	# 空いている所を探して、隣どうしに詰める
	var ox:=-1;var oy:=-1
	for yy in range(2,int(st.grid.h)-3):
		for xx in range(2,int(st.grid.w)-4):
			var ok:=true
			for dy in 2:
				for dx in 3:
					if st.place_block("bondage",xx+dx,yy+dy)!="":ok=false
			if ok:ox=xx;oy=yy;break
		if ox>=0:break
	for i in defs.size():
		var x: int=ox+i%3;var y: int=oy+i/3
		if st.place_block(defs[i],x,y)!="":print("   置けない ",defs[i]," ",st.place_block(defs[i],x,y));continue
		placed.append(st.add_facility(defs[i],x,y))
	check(placed.size()==defs.size(),"1マスの家具を隣どうしに%d個置ける"%placed.size())
	# 長い家具は1×2、回すと2×1
	var horse: Dictionary=st.add_facility("horse",20,3)
	check(st.fac_size(horse)==Vector2i(1,2),"三角木馬は1×2")
	var why: String=st.move_facility(horse,20,3,1)
	check(why=="" and st.fac_size(horse)==Vector2i(2,1),"回すと2×1（%s）"%why)
	check(st.move_facility(placed[0],int(placed[1].x),int(placed[1].y),0)!="","重なる所へは動かせない")
	check(st.move_facility(placed[0],ox,oy+2,0)=="" and st.move_facility(placed[0],ox,oy,0)=="","空いている所へ動かせる（戻せる）")
	# 飾り
	for d in ["candle","torch","chain_post","keg","brazier","banner","bones","crate","pillar"]:
		var fx: int=16+["candle","torch","chain_post","keg","brazier","banner","bones","crate","pillar"].find(d)
		if st.place_block(d,fx,7)=="":st.add_facility(d,fx,7)
	st.add_facility("rug",22,3)
	# 女と魔物を入れ、場面・表情・服を選ぶ
	var cw: Array=st.women_in("cell")
	var ms: Array=st.monsters.filter(func(m):return not int(m.uid) in st.party)
	var pair_ids: Array=Library.ids().filter(func(id):return not Library.solo(Library.load_scene(id)))
	var solo_ids: Array=Library.ids().filter(func(id):return Library.solo(Library.load_scene(id)))
	for i in placed.size():
		if i>=cw.size():break
		var f: Dictionary=placed[i]
		st.move_woman(cw[i],"house",f)
		var partner: bool=int(G.db.rooms[f.def].get("staff",0))>0 and i<ms.size()
		if partner:st.set_job(ms[i],"partner",f)
		f.scene=pair_ids[(i*5)%pair_ids.size()] if partner else solo_ids[(i*3)%solo_ids.size()]
		f.outfit=["","fc12_thorn_duelist","fc20_snow_botanist","std_knight","fc07_brass_clockmaker",""][i]
	# たくさんの施設で同時に流す（8を超えても全部動く）：もう1列、1人の場面の家具を並べて牢の女を入れる
	var many: Array=[]
	var rest: Array=st.women_in("cell")
	for i in 10:
		if i>=rest.size():break
		var x2: int=ox+i;var y2: int=oy+3
		if st.place_block("trash",x2,y2)!="":continue
		var f2: Dictionary=st.add_facility("trash",x2,y2)
		st.move_woman(rest[i],"house",f2)
		f2.scene=solo_ids[i%solo_ids.size()]
		many.append(f2)
	G.main.goto("ranch",{})
	await create_timer(1.5).timeout
	var scr=G.main.current;var map=scr.map
	map.cam=Vector2(ox+4.5,oy+2.0);map.zoom=1.6
	await create_timer(3.0).timeout
	var playing:=0
	for f in placed:
		var sc: Dictionary=map.scenes.get("f:%d"%int(f.uid),{})
		if not sc.is_empty() and str(sc.get("scene",""))==str(f.scene):playing+=1
	for f in placed:
		var sc2: Dictionary=map.scenes.get("f:%d"%int(f.uid),{})
		if sc2.is_empty() or str(sc2.get("scene",""))!=str(f.scene):
			print("   流れていない ",f.def," 場面=",f.scene," 女=",f.woman," 魔物=",f.monster," 1人の場面=",Library.solo(Library.load_scene(str(f.scene)))," 流れている=",sc2.get("scene","なし"))
	check(playing>=placed.size()-1,"選んだ場面が流れている（%d / %d）"%[playing,placed.size()])
	var all_facs: Array=placed+many
	var playing_all:=0
	for f in all_facs:
		if map.scenes.has("f:%d"%int(f.uid)):playing_all+=1
	check(all_facs.size()>8 and playing_all==all_facs.size(),"8を超える施設（%d）で全部の場面が同時に動く（%d）"%[all_facs.size(),playing_all])
	await create_timer(3.0).timeout
	print("   同時に流れている場面 %d、FPS %d"%[map.scenes.size(),Engine.get_frames_per_second()])
	if OS.get_cmdline_user_args().has("--prof"):
		var t0:=Time.get_ticks_usec();var n:=0
		while Time.get_ticks_usec()-t0<3000000:
			await process_frame;n+=1
		print("   平均フレーム %.1fms（process %.1fms）"%[3000.0/n,Performance.get_monitor(Performance.TIME_PROCESS)*1000.0])
		var br=G.anim.bridge
		var u:=Time.get_ticks_usec()
		for k in 10:br.advance(0.0)
		print("   bridge.advance %.2fms"%[(Time.get_ticks_usec()-u)/10000.0])
		u=Time.get_ticks_usec()
		for k in 10:br.world.state_dirty=true;br.world.update_world(0,false)
		print("   world.update_world %.2fms"%[(Time.get_ticks_usec()-u)/10000.0])
		u=Time.get_ticks_usec()
		for k in 10:
			for key in br.pairs:br.pairs[key].node.update_frame(0.3,false)
		print("   pair update_frame 全部 %.2fms（%d組）"%[(Time.get_ticks_usec()-u)/10000.0,br.pairs.size()])
		for key in br.pairs:
			var nd=br.pairs[key].node
			u=Time.get_ticks_usec()
			for k in 10:nd.update_effects(0.3)
			var ef:=(Time.get_ticks_usec()-u)/10.0
			print("     組 %s effects %.0fus"%[key,ef]);break
		var nodes_total:=0
		for key in br.pairs:nodes_total+=br.pairs[key].node.nodes.size()
		print("   場面の描画ノード %d（%d組）、役者 %d"%[nodes_total,br.pairs.size(),br.rows.size()])
		var all_mesh: Array=root.find_children("*","MeshInstance2D",true,false)
		var by_parent: Dictionary={}
		for mi in all_mesh:
			var pn: String=str(mi.get_parent().get_script().resource_path.get_file()) if mi.get_parent().get_script()!=null else mi.get_parent().get_class()
			by_parent[pn]=int(by_parent.get(pn,0))+1
		print("   MeshInstance2D 全部 %d %s"%[all_mesh.size(),by_parent])
		u=Time.get_ticks_usec()
		for k in 10:map.sync()
		print("   ranch_map.sync %.2fms"%[(Time.get_ticks_usec()-u)/10000.0])
		u=Time.get_ticks_usec()
		for k in 10:map._process(0.0)
		print("   ranch_map._process（advance込み） %.2fms"%[(Time.get_ticks_usec()-u)/10000.0])
		var layers: Dictionary={"床のマス":map.tile_layer,"施設":map.floor_layer,"名札":map.tags,"手前の格子":map.front}
		for lname in layers:
			layers[lname].visible=false
			t0=Time.get_ticks_usec();n=0
			while Time.get_ticks_usec()-t0<2000000:
				await process_frame;n+=1
			print("   %sを消すと %.1fms"%[lname,2000.0/n])
			layers[lname].visible=true
		var ap: bool=map.is_processing();map.set_process(false)
		t0=Time.get_ticks_usec();n=0
		while Time.get_ticks_usec()-t0<2000000:
			await process_frame;n+=1
		print("   地図の _process を止めると %.1fms"%[2000.0/n])
		map.set_process(ap)
		map.zoom=4.4;map.cam=Vector2(ox+0.5,oy+0.5)
		await create_timer(3.0).timeout
		print("   寄ったとき 場面 %d、FPS %d（process %.1fms）"%[map.scenes.size(),Engine.get_frames_per_second(),Performance.get_monitor(Performance.TIME_PROCESS)*1000.0])
		map.zoom=1.6;map.cam=Vector2(ox+4.5,oy+2.0)
		await create_timer(2.0).timeout
	var dressed:=0
	for f in placed:
		if str(f.outfit)!="" and str(map.dressed.get("w:%d"%int(f.woman),""))==str(f.outfit):dressed+=1
	check(dressed>=2,"選んだ服に着替えている（%d）"%dressed)
	# 施設の詳細に場面・表情・服の欄が出る
	scr.select_fac(int(placed[0].uid))
	await create_timer(0.8).timeout
	var opts: int=scr.right_box.find_children("*","OptionButton",true,false).size()
	check(opts>=2,"施設の詳細に場面・服の選び欄が出る（%d）"%opts)
	map.selected=-1;scr.refresh_right()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://game/tests/out_ranch_situations.png")
	map.zoom=3.4;map.cam=Vector2(ox+1.5,oy+1.0)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://game/tests/out_ranch_situations_close.png")
	print("RANCH_SCENE_CHECK bad=",bad)
	quit()
