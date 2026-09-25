extends SceneTree
## 動作の置き場を小さくして、使っていない原型・場面を外して入れ替えられるか確かめる（画面あり）。
## 見た目だけの原型（"rig": "0"）は骨格 "0" の動作を借りる：骨格を外すのは、それを使う見た目がいなくなってから。
##   Godot_console --path . --script res://game/tests/stream_evict.gd
func _initialize():call_deferred("run")
func run():
	var a=load("res://game/core/anim.gd").new();root.add_child(a)
	a.begin_setup();a.bridge.motion_pages=5
	a.data_ok=a.load_data();a.finish_setup()
	print("setup ",a.ready_ok," stream=",a.stream)
	var w:=Node2D.new();w.scale=Vector2(1.6,1.6);root.add_child(w);a.attach(w)
	var profiles:=["std_knight","std_mage2","0","std_rogue","std_mage3","std_scholar"]
	var scenes:=["restrain_grope","mating_press","dog_walk","spanking","standing_back","milking","face_sit","pony_ride","grope_knead","fellatio","full_nelson"]
	var bad:=0
	for round in 3:
		for i in profiles.size():
			var wid=a.acquire(profiles[i]);var gid=a.acquire("1")
			if wid=="" or gid=="":print("FAIL acquire ",profiles[i]," ",a.bridge.error);bad+=1;continue
			a.place(wid,Vector2(300,400),4,"idle");a.place(gid,Vector2(300,400),4,"idle")
			var h: int=a.bridge.play_pair_scene(wid,gid,scenes[(i+round*6)%scenes.size()],"default",Vector2(100+140*i,420),3600)
			if h<0:print("FAIL scene ",profiles[i]," ",scenes[(i+round*6)%scenes.size()]);bad+=1
			for f in 5:a.advance(1.0/30.0);await process_frame
			if round==2 and i==profiles.size()-1:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://game/tests/out_evict.png")
			# 借りている原型の骨格の動作は必ず載っている
			if not a.bridge.tracks.has("0"):print("FAIL 骨格0の動作がない");bad+=1
			print("round ",round," ",profiles[i]," handle=",h," loaded=",a.bridge.loaded_profiles.keys()," pairs=",a.bridge.loaded_pairs.size()," free=",a.bridge.resources.free_texels())
			a.release(wid);a.release(gid)
	# 使う役者がいなくなったら、見た目だけの原型 → 骨格の順に外れる（使っている見た目の骨格は外さない）
	a.release_all();a.bridge.latest.clear()
	var keep=a.acquire("std_mage3");a.place(keep,Vector2(300,400),4,"idle")
	while a.bridge.evict_one():pass
	var left: Array=a.bridge.loaded_profiles.keys()
	print("外した後に残った原型 ",left)
	if not ("0" in left and "std_mage3" in left and "1" in left and left.size()==3):print("FAIL 外し方");bad+=1
	a.act(keep,"walk");for f in 3:a.advance(1.0/30.0);await process_frame
	print("STREAM_EVICT bad=",bad)
	quit()
