extends RefCounted
const Library=preload("res://mini/rig3d/library.gd")
const Spec=preload("res://mini/projected2d/b_cutout/spec.gd")
const Base=preload("res://mini/projected2d/pose_source.gd")
const Face=preload("res://mini/projected2d/b_cutout/face_parts.gd")
static func encode(value):
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Vector2:return [value.x,value.y]
	if value is Basis:return [encode(value.x),encode(value.y),encode(value.z)]
	if value is Color:return [value.r,value.g,value.b,value.a]
	if value is Dictionary:
		var out:Dictionary={}
		for key in value:out[str(key)]=encode(value[key])
		return out
	if value is Array or value is PackedStringArray:
		var out:Array=[]
		for item in value:out.append(encode(item))
		return out
	if value is float and not is_finite(value):return "nonfinite"
	return value
static func save(actor)->Dictionary:
	return encode({"version":1,"template":actor.template_path,"base_config":actor.base_config,"config":actor.config,
		"preset_id":actor.preset_id,"preset_report":actor.preset_report,"state":actor.save_state(),"face_state":actor.face_state(),
		"goals":actor.goal_overrides,"interpolate_views":actor.interpolate_views,"head_pitch_enabled":actor.head_pitch_enabled,
		"library":{"version":1,"characters":actor.library.profiles.values(),"poses":actor.library.poses,"clips":actor.library.clips.values()}})
static func restore(actor,data:Dictionary)->Dictionary:
	if data.get("version")!=1:return {"ok":false,"error":"Unsupported actor bundle version"}
	for field in ["base_config","config","library","state","goals","preset_report"]:
		if not data.get(field) is Dictionary:return {"ok":false,"error":"Missing bundle object: "+field}
	for field in ["template","preset_id"]:
		if not data.get(field) is String:return {"ok":false,"error":"Missing bundle string: "+field}
	for field in ["interpolate_views","head_pitch_enabled"]:
		if not data.get(field) is bool:return {"ok":false,"error":"Missing bundle flag: "+field}
	var spec:=Spec.new()
	if not spec.validate(data.base_config) or not spec.validate(data.config):return {"ok":false,"error":spec.error}
	var facial=data.get("face_state",{})
	if not facial is Dictionary:return {"ok":false,"error":"face_state must be an object"}
	var face_check:=Face.validate(facial,data.config)
	if not face_check.ok:return face_check
	var lib:=Library.new()
	if not lib.load_data(data.library,data.library):return {"ok":false,"error":lib.error}
	if not lib.profiles.has("explorer"):return {"ok":false,"error":"B cutout requires the explorer reference profile"}
	var probe:=Base.new();probe.library=lib
	if not probe.restore(data.state):return {"ok":false,"error":"Invalid playback state"}
	var goals:Dictionary={}
	for key in data.goals:
		if key not in ["hand_l","hand_r","foot_l","foot_r"] or not lib.vector(data.goals[key]):return {"ok":false,"error":"Invalid goal: "+str(key)}
		goals[key]=Library.vec(data.goals[key])
	actor.library=lib;actor.template_path=data.template
	actor.base_config=data.base_config.duplicate(true);actor.config=data.config.duplicate(true)
	actor.presets=load("res://mini/projected2d/b_cutout/presets.gd").new(actor.base_config)
	actor.preset_id=data.preset_id;actor.preset_report=data.preset_report.duplicate(true)
	actor.head_surface=load("res://mini/projected2d/b_cutout/head_surface.gd").new(actor.config.head_landmarks)
	actor.interpolate_views=data.interpolate_views;actor.head_pitch_enabled=data.head_pitch_enabled
	actor.restore(data.state);actor.goal_overrides=goals
	actor.expression=facial.get("expression","neutral");actor.face_parts=facial.get("face_parts",{}).duplicate(true);actor.overlays=facial.get("overlays",{}).duplicate(true)
	actor.evaluate()
	return {"ok":true}
