extends SceneTree
## ブラウザ版に入れる素材の洗い出し：ゲームが実行中に読むファイル（packs の原型のレシピが指す画像など）を並べる。
##   Godot_console --headless --path . --script res://game/tests/web_assets.gd
const Pack=preload("res://game_v2/animation/pack.gd")
func _initialize():call_deferred("run")
func walk(v: Variant,out: Dictionary) -> void:
	if v is Dictionary:
		for k in v:walk(v[k],out)
	elif v is Array:
		for x in v:walk(x,out)
	elif v is String and (v.ends_with(".png") or v.ends_with(".json") or v.ends_with(".bin")) and v.begins_with("res://"):
		out[v]=true
	elif v is String and v.begins_with("res://") and DirAccess.dir_exists_absolute(v):
		out[v+"/"]=true
func run():
	var rf:=FileAccess.open(Pack.DIR+"recipes.pack",FileAccess.READ)
	var recipes: Dictionary=rf.get_var() if rf!=null else {}
	var out: Dictionary={}
	walk(recipes,out)
	var dirs: Dictionary={}
	for p in out:dirs[p.get_base_dir()]=int(dirs.get(p.get_base_dir(),0))+1
	var keys: Array=dirs.keys();keys.sort()
	for d in keys:print(d,"  ",dirs[d])
	print("WEB_ASSETS files=",out.size())
	quit()
