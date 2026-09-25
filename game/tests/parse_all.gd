extends SceneTree
func _initialize():call_deferred("run")
func run():
	var bad:=0
	for f in files("res://game"):
		if f.ends_with(".gd") and not f.begins_with("res://game/tests"):
			var s=load(f)
			if s==null or not s.can_instantiate():print("PARSE_FAIL ",f);bad+=1
	print("PARSE_DONE bad=",bad);quit()
func files(dir:String)->Array:
	var out:=[];var d=DirAccess.open(dir)
	for f in d.get_files():out.append(dir+"/"+f)
	for sub in d.get_directories():out+=files(dir+"/"+sub)
	return out
