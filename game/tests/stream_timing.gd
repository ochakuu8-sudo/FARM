extends SceneTree
const G=preload("res://game/core/g.gd")
func _initialize():call_deferred("run")
func run():
	var a=load("res://game/core/anim.gd").new();root.add_child(a)
	var t=Time.get_ticks_msec()
	print("setup ",a.setup()," stream=",a.stream," ms=",Time.get_ticks_msec()-t," err=",a.error)
	var w:=Node2D.new();w.scale=Vector2(1.6,1.6);root.add_child(w);a.attach(w)
	t=Time.get_ticks_msec()
	var ids:=[]
	for p in ["four_knight","1","four_healer","four_scout","0","four_mixed","four_warrior","1"]:
		var id=a.acquire(p);ids.append(id)
	print("acquire 8 (first binds) ms=",Time.get_ticks_msec()-t)
	for i in ids.size():a.place(ids[i],Vector2(60+i*110,160),2,"walk")
	# 2体場面
	var wid=a.acquire("four_knight");var gid=a.acquire("1")
	a.place(wid,Vector2(300,400),4,"idle");a.place(gid,Vector2(300,400),4,"idle")
	t=Time.get_ticks_msec()
	var h=a.present({"kind":"ranch.room","a":wid,"b":gid,"room":"pleasure"},Vector2(300,420),true)
	print("pair handle=",h," load ms=",Time.get_ticks_msec()-t)
	for f in 30:
		a.advance(1.0/30.0);await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://game/tests/out_stream.png")
	print("free texels=",a.bridge.resources.free_texels()," loaded profiles=",a.bridge.loaded_profiles.keys())
	quit()
