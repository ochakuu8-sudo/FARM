extends SceneTree
const Session=preload("res://mini/layered2d/authoring/session.gd")
const Compiler=preload("res://mini/layered2d/prepare/scene_compiler.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
func _initialize():call_deferred("run")
func run():
	var defs=JSON.parse_string(FileAccess.get_file_as_string("res://game_v2/content/game_clips.json"))
	for clip in ["struggle","bound","kneel_idle","caged_sit","rest_lie","serve_bow","rise"]:
		var s=Session.new()
		var r=s.load_scene({"version":1,"duration":defs[clip].duration,"clips":defs,"actors":[{"id":"actor","recipe":Profiles.recipe("0"),"clip":clip}]})
		if not r.ok:print("FAIL load ",clip," ",r);continue
		var c=Compiler.new().compile(s)
		print(clip," ok=",c.ok," ",("" if c.ok else str(c).substr(0,300)))
	quit()
