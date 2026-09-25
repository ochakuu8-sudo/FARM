extends RefCounted
## Stable topological ordering; author edits data, not renderer conditionals.
static func resolve(base: Array, names: Array, rules: Array, phase: float, direction: int) -> Dictionary:
	var edges: Dictionary={};var degrees: Dictionary={}
	for id in base:edges[id]=[];degrees[id]=0
	var active: Array=[]
	for rule in rules:
		if phase>=float(rule.get("start",0)) and phase<=float(rule.get("end",1)) and (not rule.has("directions") or rule.directions.has(direction)):active.append(rule)
	for rule in active.duplicate():
		var before:Array=[rule.get("before","")];var after:Array=[rule.get("after","")]
		for item in [before,after]:
			if str(item[0]).get_slice(".",str(item[0]).get_slice_count(".")-1)=="pelvis":
				for side in ["l","r"]:
					if names.has(str(item[0])+"_"+side):item.append(str(item[0])+"_"+side)
		for a in before:
			for b in after:
				if a==before[0] and b==after[0]:continue
				var expanded:Dictionary=rule.duplicate();expanded.before=a;expanded.after=b;active.append(expanded)
	var prefixes: Dictionary={}
	for name in names:
		var prefix: String=str(name).get_slice(".",0)+"." if str(name).contains(".") else ""
		prefixes[prefix]=true
	# Seam covers are below adjacent limb surfaces; the waist band overlays the coat.
	# Explicit author rules for a pair take priority over these local defaults.
	var pairs: Array=[["chest","abdomen"],["pelvis","abdomen"],["pelvis_l","abdomen"],["pelvis_r","abdomen"],["neck","head"],["neck","chest"]]
	for side in ["l","r"]:
		pairs.append_array([["elbow_"+side,"upper_"+side],["elbow_"+side,"fore_"+side],["knee_"+side,"thigh_"+side],["knee_"+side,"shin_"+side]])
	var combined:=active.duplicate()
	for prefix in prefixes:
		for pair in pairs:
			var a: String=prefix+pair[0];var b: String=prefix+pair[1]
			if not names.has(a) or not names.has(b):continue
			var overridden:=false
			for rule in active:
				if (rule.get("before")==a and rule.get("after")==b) or (rule.get("before")==b and rule.get("after")==a):overridden=true
			if not overridden:combined.append({"before":a,"after":b})
	for rule in combined:
		if phase<float(rule.get("start",0)) or phase>float(rule.get("end",1)):continue
		if rule.has("directions") and not rule.directions.has(direction):continue
		var a:=names.find(str(rule.get("before","")));var b:=names.find(str(rule.get("after","")))
		if a<0 or b<0 or a==b:return {"ok":false,"code":"LAYER_UNKNOWN_OR_SELF","rule":rule}
		if not edges[a].has(b):edges[a].append(b);degrees[b]+=1
	var result: Array=[]
	while result.size()<base.size():
		var found:=-1
		for id in base:
			if degrees[id]==0 and not result.has(id):found=id;break
		if found<0:return {"ok":false,"code":"LAYER_CYCLE","phase":phase,"direction":direction}
		result.append(found)
		for other in edges[found]:degrees[other]-=1
	return {"ok":true,"order":PackedInt32Array(result)}

static func depth(slot:int,parts:Array,view:Vector3)->float:
	if slot not in [21,22]:return parts[slot].center.dot(view)
	var pelvis:Dictionary=parts[0]
	var right:=Vector3(view.z,0,-view.x).normalized()
	var basis:=Basis(pelvis.rotation)
	var projection:=basis.x.dot(right)
	var dl:float=Vector3(parts[8].anchor).dot(view)
	var dr:float=Vector3(parts[16].anchor).dot(view)
	var screen_left:float=dr if projection>=0 else dl
	var screen_right:float=dl if projection>=0 else dr
	# At profile both visible halves belong to the near hip; avoid a side-view seam.
	var d:float=screen_left if slot==21 else screen_right
	return lerpf(maxf(dl,dr),d,absf(projection))+0.002
