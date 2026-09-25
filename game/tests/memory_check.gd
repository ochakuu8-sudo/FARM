extends SceneTree
## GPU に載せている画像と動作データの量を出す（画面あり）。main.tscn と同じ引数を渡す。
##   Godot_console --path . --script res://game/tests/memory_check.gd -- --debug=screen:map --setup=mid
const G=preload("res://game/core/g.gd")
func _initialize():call_deferred("run")
func run():
	var main: Node=load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(14.0).timeout
	var r=G.anim.bridge.resources
	var body: int=r.body_images.size()*2048*2048*4
	var face: int=r.face_images.size()*512*512*4
	var motion: int=maxi(r.motion_images.size(),r.page_bytes.size())*256*256*r.motion_texel_bytes()
	print("MEM body_pages=%d (%.0fMB) body_cells=%d  face_pages=%d (%.0fMB) face_cells=%d  motion_pages=%d (%.0fMB)  total=%.0fMB"%[r.body_images.size(),body/1048576.0,r.body_cell,r.face_images.size(),face/1048576.0,r.face_cell,maxi(r.motion_images.size(),r.page_bytes.size()),motion/1048576.0,r.memory_bytes/1048576.0])
	quit()
