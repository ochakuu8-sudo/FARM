extends RefCounted
const Spec=preload("res://mini/projected2d/b_cutout/spec.gd")
const PATH="res://mini/projected2d/b_cutout/presets.json"
const PROFILE_KEYS=["hip_height","torso","neck","thigh","shin","upper_arm","forearm","shoulder","hip_width","head_center_height"]
var definitions:Dictionary={}
func _init(base:Dictionary={})->void:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and parsed.get("version")==1 and parsed.get("presets") is Dictionary:definitions=parsed.presets
	if base.is_empty():return
	# Built-in body variants describe ratios relative to the original template.
	# Preserve another character's baseline scale and proportions when applying them.
	var reference:Dictionary=Spec.new().data
	for id in definitions:
		var patch:Dictionary=definitions[id]
		if patch.has("display_scale") and base.display_scale!=reference.display_scale:patch.display_scale*=base.display_scale/reference.display_scale
		for key in patch.get("profile",{}):
			if base.profile[key]!=reference.profile[key]:patch.profile[key]*=base.profile[key]/reference.profile[key]
func bounded(value,base:float,low:float,high:float,name:String,clamp_limits:bool,report:Dictionary):
	if not (value is int or value is float) or not is_finite(float(value)):
		report.errors.append(name+": expected a finite number");return base
	if value<base*low or value>base*high:
		var effective:=clampf(float(value),base*low,base*high)
		if clamp_limits:report.warnings.append({"field":name,"requested":value,"effective":effective,"reason":"clamped_to_declared_range"})
		else:report.errors.append(name+": outside declared range")
		return effective
	return float(value)
func compose(base:Dictionary,patch:Dictionary,clamp_limits:bool=false)->Dictionary:
	var report:={"ok":false,"errors":[],"warnings":[],"config":base.duplicate(true)}
	var candidate:Dictionary=report.config
	for key in patch:
		if key not in ["label","profile","surface","display_scale"]:report.errors.append("Unknown preset field: "+str(key))
	if patch.has("display_scale"):candidate.display_scale=bounded(patch.display_scale,base.display_scale,.75,1.25,"display_scale",clamp_limits,report)
	if patch.has("profile"):
		if not patch.profile is Dictionary:report.errors.append("profile must be an object")
		else:
			for key in patch.profile:
				if key not in PROFILE_KEYS or not base.profile.has(key):report.errors.append("Unsupported profile field: "+str(key));continue
				candidate.profile[key]=bounded(patch.profile[key],base.profile[key],.75,1.25,"profile."+key,clamp_limits,report)
	if patch.has("surface"):
		if not patch.surface is Dictionary:report.errors.append("surface must be an object")
		else:
			for group in patch.surface:
				if not base.surface.has(group) or not patch.surface[group] is Dictionary:report.errors.append("Unknown surface: "+str(group));continue
				for field in patch.surface[group]:
					if field not in ["radii","scale"] or not base.surface[group].has(field):report.errors.append("Unsupported surface field: "+group+"."+field);continue
					var v=patch.surface[group][field]
					if not v is Array or v.size()!=3:report.errors.append("Expected three dimensions: "+group+"."+field);continue
					for i in range(3):
						candidate.surface[group][field][i]=bounded(v[i],base.surface[group][field][i],.8,1.2,"surface."+group+"."+field+"["+str(i)+"]",clamp_limits,report)
	var spec:=Spec.new()
	if not spec.validate(candidate):report.errors.append("Combined body rejected: "+spec.error)
	report.ok=report.errors.is_empty()
	return report
