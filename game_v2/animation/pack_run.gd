extends SceneTree
## packs/ を作り直す（pack.gd）。焼き込み（bake.gd）の最後でも自動で呼ばれる。
##   --headless --path . --script res://game_v2/animation/pack_run.gd
func _initialize():call_deferred("run")
func run():
	var result: Dictionary=preload("res://game_v2/animation/pack.gd").build()
	print("PACK ",result)
	quit(0 if result.ok else 1)
