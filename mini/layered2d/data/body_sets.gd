extends RefCounted
## Shape selection is independent of artwork. No additional render slots or track fields.
const PATH="res://mini/layered2d/data/body_sets.json"
const UPPER=["neck","chest","abdomen","upper_arm","forearm","hand","elbow"]
const LOWER=["pelvis","thigh","shin","boot","knee"]
const UPPER_KEYS=["torso","shoulder","upper_arm","forearm","neck","shoulder_depth","shoulder_drop"]
const LOWER_KEYS=["thigh","shin","hip_width","hip_height"]

static func presets()->Array:
	var value=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value.sets if value is Dictionary else []

static func find(id:String)->Dictionary:
	for entry in presets():
		if entry.id==id:return entry.duplicate(true)
	return {}

static func selection(upper:String,lower:String)->Dictionary:
	return {"version":1,"upper":find(upper),"lower":find(lower)}

static func apply(recipe:Dictionary,configs:Array)->Dictionary:
	if not recipe.has("body_sets"):return {"ok":true,"recipe":recipe}
	var selected:Dictionary=recipe.body_sets
	if selected.get("version")!=1:return {"ok":false,"error":"上下セットの版が未対応です"}
	var result:=recipe.duplicate(true)
	var surface:Dictionary={};var reference:Dictionary={}
	var profile:Dictionary=recipe.profile.duplicate(true)
	var waist:Array=[];var clearance:=0.0
	var centers:Dictionary={};var profile_reference:Dictionary=profile.duplicate(true)
	for role in ["upper","lower"]:
		var shape:Dictionary=selected.get(role,{})
		if shape.get("role")!=role:return {"ok":false,"error":"上下セットの種類が違います: "+role}
		var source:int=int(shape.get("geometry_source",-1))
		if source<0 or source>=configs.size():return {"ok":false,"error":"形の基準が見つかりません"}
		var config:Dictionary=configs[source]
		var values:Dictionary=config.profile.duplicate(true)
		values.shoulder_depth=float(config.profile.get("shoulder_depth",0))
		values.shoulder_drop=float(config.profile.get("shoulder_drop",.04))
		for key in shape.get("profile",{}):
			if key=="shoulder_drop":
				var drop=float(shape.profile[key])
				if not is_finite(drop) or drop<0 or drop>.4:return {"ok":false,"error":"肩の高さの範囲外"}
				values[key]=drop
				continue
			if key=="shoulder_depth":
				var depth=float(shape.profile[key])
				if not is_finite(depth) or absf(depth)>.25:return {"ok":false,"error":"肩の前後位置の範囲外"}
				values[key]=depth
				continue
			if not values.has(key):return {"ok":false,"error":"不明な体格項目: "+key}
			var v:float=float(shape.profile[key])
			if not is_finite(v) or v<=0 or v>float(config.profile[key])*1.8:return {"ok":false,"error":"体格の範囲を確認してください: "+key}
			values[key]=v
		for key in (UPPER_KEYS if role=="upper" else LOWER_KEYS):
			profile[key]=values[key]
		# Explicitly authored dimensions are their own baseline, not random variation of legacy art.
		var ref:Dictionary=config.profile.duplicate(true)
		if shape.get("authored_dimensions",false):
			ref.merge(values,true)
			for key in (UPPER_KEYS if role=="upper" else LOWER_KEYS):profile_reference[key]=values[key]
		if role=="upper":
			for key in shape.get("centers",{}):
				var fraction=float(shape.centers[key])
				if key not in ["chest","abdomen"] or not is_finite(fraction) or fraction<0 or fraction>1:return {"ok":false,"error":"胴の基準位置が不正です"}
				centers[key]=fraction
		for group in (UPPER if role=="upper" else LOWER):
			var part:Dictionary=config.surface[group].duplicate(true)
			part.merge(shape.get("surface",{}).get(group,{}),true)
			for field in ["radii","scale","multiplier"]:
				if not part.has(field):continue
				if not part[field] is Array or part[field].size()!=3:return {"ok":false,"error":"部位寸法を確認してください: "+group}
				for v in part[field]:
					if not (v is float or v is int) or not is_finite(float(v)) or float(v)<=0 or float(v)>4:return {"ok":false,"error":"部位寸法の範囲外: "+group}
			if part.has("joint_anchor"):
				var join=part.joint_anchor
				if not join is Dictionary:return {"ok":false,"error":"接合点の形式が不正です: "+group}
				for name in ["proximal","distal"]:
					var point=join.get(name,[])
					if not point is Array or point.size()!=2:return {"ok":false,"error":"接合点は2要素です: "+group}
					for v in point:
						if not (v is int or v is float) or not is_finite(float(v)) or float(v)<0 or float(v)>1:return {"ok":false,"error":"接合点の範囲外: "+group}
				if not (join.get("strength") is float or join.get("strength") is int) or not is_finite(float(join.strength)) or join.strength<0 or join.strength>1:return {"ok":false,"error":"接合強度の範囲外: "+group}
				var mode=join.get("mode")
				if not (mode is int or mode is float) or not is_finite(float(mode)) or float(mode)!=floorf(float(mode)) or int(mode) not in [1,2,3]:return {"ok":false,"error":"接合方式が不正です: "+group}
			surface[group]=part
			if part.has("proximal_radii"):
				var radii=part.proximal_radii
				if not radii is Array or radii.size()!=2:return {"ok":false,"error":"付け根寸法は幅・厚みの2要素です"}
				for v in radii:
					if not (v is float or v is int) or not is_finite(float(v)) or v<=0 or v>1:return {"ok":false,"error":"付け根寸法の範囲外"}
			reference[group]=ref.duplicate(true)
		var w:Array=shape.get("waist",[])
		if w.size()!=4:return {"ok":false,"error":"腰の幅・厚みの許容範囲が必要です"}
		for v in w:
			if not (v is float or v is int) or not is_finite(float(v)) or float(v)<=0:return {"ok":false,"error":"腰の範囲が不正です"}
		if w[0]>w[1] or w[2]>w[3]:return {"ok":false,"error":"腰の最小値が最大値を超えています"}
		waist.append(w)
		if role=="upper":clearance=clampf(float(shape.get("arm_clearance",0)),0,.2)
	var xmin:float=maxf(waist[0][0],waist[1][0]);var xmax:float=minf(waist[0][1],waist[1][1])
	var zmin:float=maxf(waist[0][2],waist[1][2]);var zmax:float=minf(waist[0][3],waist[1][3])
	if xmin>xmax or zmin>zmax:return {"ok":false,"error":"腰の接続は要調整です。上下の許容範囲が重なっていません"}
	result.profile=profile
	result.resolved_shape={"version":1,"surface":surface,"reference":reference,"waist":[(xmin+xmax)*.5,(zmin+zmax)*.5],"arm_clearance":clearance,"centers":centers,"profile_reference":profile_reference}
	return {"ok":true,"recipe":result}

static func actor_config(recipe:Dictionary,configs:Array)->Dictionary:
	var c:Dictionary=configs[int(recipe.get("prototype_index",recipe.modules.head))].duplicate(true)
	if recipe.has("resolved_shape"):c.shape_motion={"arm_clearance":recipe.resolved_shape.arm_clearance,"centers":recipe.resolved_shape.get("centers",{})}
	return c
