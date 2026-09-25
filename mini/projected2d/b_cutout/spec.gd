extends RefCounted
const Registered=preload("res://mini/projected2d/b_cutout/registered_face.gd")
var data:Dictionary={}
var error:=""
func _init(path:String="res://mini/projected2d/b_cutout/template.json")->void:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and validate(parsed):data=parsed
	elif not parsed is Dictionary:error="template JSON is missing or invalid"
func finite(v)->bool:return (v is float or v is int) and is_finite(float(v))
func vector(v,n:int)->bool:
	if not v is Array or v.size()!=n:return false
	for x in v:
		if not finite(x):return false
	return true
func fail(reason:String)->bool:error=reason;return false
func validate(c:Dictionary)->bool:
	error=""
	if c.get("version")!=2 or c.get("tile_size")!=256:return fail("version/tile_size")
	if not c.get("sources") is Dictionary:return fail("sources")
	for key in ["heads","upper_body","lower_body","arms","legs"]:
		if not c.sources.get(key) is String or not c.sources[key].begins_with("res://"):return fail("source path")
	if not c.get("atlas_path") is String or not c.atlas_path.begins_with("res://") or not c.atlas_path.ends_with(".png"):return fail("atlas_path")
	if c.get("source_directions")!=["front","front_three_quarter_left","left","back"]:return fail("4 source directions required")
	if not finite(c.get("display_scale")) or c.display_scale<=0:return fail("display_scale")
	if not c.get("profile") is Dictionary:return fail("profile")
	for key in ["head","hip_height","torso","neck","thigh","shin","upper_arm","forearm","shoulder","hip_width"]:
		if not finite(c.profile.get(key)) or c.profile[key]<=0:return fail("profile/"+key)
	if c.profile.head!=1 or c.profile.hip_height-.2>c.profile.thigh+c.profile.shin:return fail("unsupported head unit or unreachable standing feet")
	if c.profile.has("head_center_height") and (not finite(c.profile.head_center_height) or c.profile.head_center_height<=0):return fail("head_center_height")
	if not c.get("surface") is Dictionary:return fail("surface")
	if c.has("neck_sample"):
		if not vector(c.neck_sample,4):return fail("neck_sample")
		var n:Array=c.neck_sample
		if n[0]<0 or n[1]<0 or n[2]<=0 or n[3]<=0 or n[0]+n[2]>1 or n[1]+n[3]>1:return fail("neck_sample bounds")
	for key in ["head","chest","abdomen","pelvis","upper_arm","forearm","hand","thigh","shin","boot","elbow","knee","neck"]:
		if not c.surface.get(key) is Dictionary:return fail("surface/"+key)
		var s:Dictionary=c.surface[key]
		if not finite(s.get("row")) or s.row<0 or s.row>=15 or s.row!=floorf(s.row):return fail("atlas row")
		if not s.has("radii") and not s.has("scale"):return fail("surface dimensions")
		for field in ["radii","scale","offset"]:
			if not s.has(field):continue
			if not vector(s[field],3):return fail("surface vector")
			if field!="offset":
				for value in s[field]:
					if value<=0:return fail("positive dimensions")
	if not c.get("head_landmarks") is Array or c.head_landmarks.size()!=4:return fail("four head correspondence sets")
	for marks in c.head_landmarks:
		if not vector(marks,9):return fail("head landmarks")
		for x in marks:
			if x<=0 or x>=1:return fail("landmark range")
		if marks[0]>=marks[1] or not (.27<marks[2] and marks[2]<marks[4] and marks[4]<marks[6] and marks[6]<marks[8]):return fail("folded landmark grid")
	if not c.get("slices") is Dictionary:return fail("slices")
	for key in c.slices:
		var b=c.slices[key]
		if not c.surface.has(key) or not vector(b,2) or b[0]<0 or b[1]>1 or b[0]>=b[1]:return fail("invalid crop")
	if not c.get("neutral_stand") is Dictionary:return fail("neutral_stand")
	for k in ["hand_l","hand_r","pole_arm_l","pole_arm_r"]:
		if not vector(c.neutral_stand.get(k),3):return fail("neutral_stand/"+k)
	if not c.get("head_pitch_warp") is Dictionary:return fail("head_pitch_warp")
	for k in ["reference","strength","maximum"]:
		if not finite(c.head_pitch_warp.get(k)):return fail("pitch parameters")
	if c.head_pitch_warp.strength<0 or c.head_pitch_warp.strength>.8 or c.head_pitch_warp.maximum<0 or c.head_pitch_warp.maximum>90:return fail("pitch warp bounds")
	if c.has("face"):
		var face=c.face
		if not face is Dictionary or not face.get("atlas_path") is String or not face.atlas_path.begins_with("res://") or not face.atlas_path.ends_with(".png"):return fail("face atlas_path")
		if face.has("registered"):
			if not finite(face.get("row_count")) or face.row_count<1 or face.row_count>34 or face.row_count!=floorf(face.row_count):return fail("Registered atlas rows")
			if not finite(face.get("blank_row")) or face.blank_row<0 or face.blank_row>=face.row_count or face.blank_row!=floorf(face.blank_row):return fail("Registered base row")
			var registered_check:=Registered.validate_definition(face)
			return true if registered_check.ok else fail(registered_check.error)
		var rows:Array=[]
		for key in ["blank_row","blush_row","tears_row"]:rows.append(face.get(key))
		for pair in [["eyes",["open","half","closed","wide"]],["mouths",["closed","small","large","clenched"]]]:
			if not face.get(pair[0]) is Dictionary:return fail("face parts")
			for key in pair[1]:rows.append(face[pair[0]].get(key))
		var row_count=face.get("row_count",11)
		if not finite(row_count) or row_count<1 or row_count>34 or row_count!=floorf(row_count):return fail("face row_count 1..34")
		if face.has("composite_heads"):
			if not face.composite_heads is Dictionary or face.composite_heads.size()!=16:return fail("16 composite heads required")
			for eye in ["open","half","closed","wide"]:
				for mouth in ["closed","small","large","clenched"]:rows.append(face.composite_heads.get(eye+"/"+mouth))
		for row in rows:
			if not finite(row) or row<0 or row>=row_count or row!=floorf(row):return fail("face row outside row_count")
		if face.has("continuous"):
			var definition=face.continuous
			if not face.has("composite_heads") or not definition is Dictionary:return fail("continuous face definition")
			if not finite(definition.get("reference_pitch")):return fail("continuous reference pitch")
			var angles=definition.get("angles")
			if not angles is Array or angles.size()<2:return fail("continuous angles")
			if angles[0]!=0 or angles[-1]!=180:return fail("continuous coverage 0..180")
			for i in range(angles.size()):
				if not finite(angles[i]) or (i>0 and angles[i]<=angles[i-1]):return fail("ordered continuous angles")
			var features=definition.get("features")
			if not features is Array or features.size()!=5:return fail("five frontal parts")
			for feature in features:
				if not feature is Dictionary or not vector(feature.get("source"),4):return fail("frontal source rectangle")
				var src:Array=feature.source
				if src[0]<0 or src[1]<0 or src[2]<=0 or src[3]<=0 or src[0]+src[2]>256 or src[1]+src[3]>256:return fail("frontal source bounds")
				if not feature.get("targets") is Array or feature.targets.size()!=angles.size():return fail("continuous anchor count")
				for rect in feature.targets:
					if not vector(rect,4) or rect[2]<0 or rect[3]<=0:return fail("continuous target bounds")
	return true
