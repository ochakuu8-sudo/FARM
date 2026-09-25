extends RefCounted
## Pure expression state: does not own a pose, skeleton, or render geometry.
const Registered=preload("res://mini/projected2d/b_cutout/registered_face.gd")
const PRESETS={"neutral":[],"calm":["open","closed"],"relaxed":["half","closed"],"strained":["closed","clenched"],"surprised":["wide","large"],"speaking":["open","small"]}
const EYES=["open","half","closed","wide"]
const MOUTHS=["closed","small","large","clenched"]
static func validate(state:Dictionary,config:Dictionary={})->Dictionary:
	if config.get("face",{}).has("registered"):return Registered.validate_state(state,config.face)
	if not state.get("expression","neutral") is String:return {"ok":false,"error":"expression must be a string"}
	var id:String=state.get("expression","neutral")
	if not PRESETS.has(id) and id!="custom":return {"ok":false,"error":"Unknown expression: "+id}
	var parts=state.get("face_parts",{})
	if not parts is Dictionary:return {"ok":false,"error":"face_parts must be an object"}
	if not parts.is_empty() and (parts.get("eyes") not in EYES or parts.get("mouth") not in MOUTHS or parts.size()!=2):return {"ok":false,"error":"Expected valid eyes and mouth"}
	if id=="custom" and parts.is_empty():return {"ok":false,"error":"Custom expression requires eyes and mouth"}
	var overlays=state.get("overlays",{})
	if not overlays is Dictionary:return {"ok":false,"error":"overlays must be an object"}
	for key in overlays:
		var value=overlays[key]
		if key not in ["blush","tears"] or not (value is float or value is int) or not is_finite(float(value)) or value<0 or value>1:return {"ok":false,"error":"Overlay must be blush/tears with finite strength 0..1"}
	return {"ok":true}
static func render_data(config:Dictionary,id:String,custom:Dictionary,overlays:Dictionary)->Dictionary:
	if not config.has("face"):return {}
	var definition:Dictionary=config.face
	if definition.has("registered"):return Registered.render_data(definition,id,custom,overlays)
	var active:Array=PRESETS.get(id,[])
	if id=="custom":active=[custom.get("eyes","open"),custom.get("mouth","closed")]
	var blush:=clampf(float(overlays.get("blush",0)),0,1)
	var tears:=clampf(float(overlays.get("tears",0)),0,1)
	if definition.has("continuous"):
		if active.is_empty():active=["open","small"]
		return {"atlas_path":definition.atlas_path,"blank":int(definition.blank_row),"eyes":-1,"mouth":-1,
			"continuous":definition.continuous,"continuous_row":int(definition.composite_heads[active[0]+"/"+active[1]]),
			"blush":int(definition.blush_row),"tears":int(definition.tears_row),"blush_strength":blush,"tears_strength":tears}
	if active.is_empty() and blush==0 and tears==0:return {}
	# Registered patches are compiled before texture filtering / view morphing.
	# One head row contains both selected parts, so there is no second face layer
	# drifting over a different direction's baked features during rotation.
	if definition.has("composite_heads"):
		var row:int=-1 if active.is_empty() else int(definition.composite_heads[active[0]+"/"+active[1]])
		return {"atlas_path":definition.atlas_path,"blank":row,"eyes":-1,"mouth":-1,
			"blush":int(definition.blush_row),"tears":int(definition.tears_row),"blush_strength":blush,"tears_strength":tears}
	return {"atlas_path":definition.atlas_path,"blank":int(definition.blank_row) if not active.is_empty() else -1,
		"eyes":int(definition.eyes[active[0]]) if not active.is_empty() else -1,
		"mouth":int(definition.mouths[active[1]]) if not active.is_empty() else -1,
		"blush":int(definition.blush_row),"tears":int(definition.tears_row),"blush_strength":blush,"tears_strength":tears}
