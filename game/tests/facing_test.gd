extends SceneTree
const Anim=preload("res://game/core/anim.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1600,700)
	var bg:=ColorRect.new();bg.color=Color(0.1,0.1,0.12);bg.size=Vector2(1600,700);root.add_child(bg)
	var a=Anim.new();root.add_child(a)
	print("setup ",a.setup()," ",a.error)
	var w:=Node2D.new();w.scale=Vector2(1.6,1.6);root.add_child(w)
	a.attach(w)
	for i in 8:
		var id=a.acquire("four_knight");a.place(id,Vector2(60+i*110,160),i,"walk")
		var l:=Label.new();l.text=str(i);l.position=Vector2((60+i*110)*1.6,270);root.add_child(l)
	var acts=["down","down_struggle","bound","kneel","caged","rest","serve","rise"]
	for i in acts.size():
		var id=a.acquire("four_scout");a.place(id,Vector2(60+i*110,360),2,acts[i])
		var l:=Label.new();l.text=acts[i];l.position=Vector2((30+i*110)*1.6,590);root.add_child(l)
	for f in 40:
		a.advance(1.0/30.0);await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://game/tests/out_facing.png")
	quit()
