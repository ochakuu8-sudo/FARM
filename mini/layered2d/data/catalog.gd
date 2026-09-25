extends RefCounted
## Stable authoring IDs. Render slots never contain a character ID.
const SLOTS = ["pelvis", "abdomen", "chest", "neck", "head", "upper_l", "fore_l", "hand_l", "thigh_l", "shin_l", "boot_l", "elbow_l", "knee_l", "upper_r", "fore_r", "hand_r", "thigh_r", "shin_r", "boot_r", "elbow_r", "knee_r", "pelvis_l", "pelvis_r"]
const GROUPS = ["pelvis", "abdomen", "chest", "neck", "head", "upper_arm", "forearm", "hand", "thigh", "shin", "boot", "elbow", "knee", "upper_arm", "forearm", "hand", "thigh", "shin", "boot", "elbow", "knee", "pelvis", "pelvis"]
const MODULES = ["lower_body", "lower_body", "upper_body", "head", "head", "arms", "arms", "arms", "legs", "legs", "legs", "arms", "legs", "arms", "arms", "arms", "legs", "legs", "legs", "arms", "legs", "lower_body", "lower_body"]
const ROOT = "res://mini/projected2d/b_cutout/"
const TEMPLATES = [ROOT + "expressions/simple_face/adventurer/template.json", ROOT + "expressions/simple_face/goblin/template.json"]
const CLIPS = ["idle", "squat_cycle", "reach_cycle", "wave", "cross", "all_fours", "sit", "kneel", "twist_test", "unseen"]
const NAMES = ["待機", "しゃがむ", "手を伸ばす", "手を振る", "腕組み", "四つん這い", "座る", "両膝", "ひねる", "自由動作"]
## 付属物（docs/素材制作テンプレート/付属物の規格.md）。体の23枠の後ろの枠23〜27。動作データは1体32枠ぶんあるので形式は変わらない。
const PROP_SLOTS = ["weapon_r", "weapon_l", "ears", "tail", "groin"]
const ALL_SLOTS = SLOTS + PROP_SLOTS
const PROP_BASE = 23
const STRIDE = 32
const CAPACITY = 256
const VERSION = 1
var configs: Array = []
var templates: Array = []

func _init() -> void:
	var registry = JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/catalog.json"))
	templates = registry.get("templates",TEMPLATES) if registry is Dictionary else TEMPLATES.duplicate()
	for path in templates:
		var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var error:=preload("res://mini/layered2d/data/source_views.gd").validate(config)
		assert(error.is_empty(),path+": "+error)
		configs.append(config)

func recipe(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var modules: Dictionary = {}
	for id in ["head", "upper_body", "lower_body", "arms", "legs"]:
		modules[id] = rng.randi_range(0, configs.size()-1)
	var profile: Dictionary = configs[modules.head].profile.duplicate(true)
	for key in ["torso", "thigh", "shin", "upper_arm", "forearm", "shoulder", "hip_width"]:
		profile[key] *= rng.randf_range(0.9, 1.1)
	var base: Dictionary = configs[modules.head].profile
	profile.hip_height *= (profile.thigh + profile.shin) / (base.thigh + base.shin)
	var face: Dictionary = {}
	var donors:=face_donors()
	if configs[modules.head].face.get("mode","registered")!="baked":
		for id in ["eye_l", "eye_r", "brow_l", "brow_r", "mouth"]:
			face[id] = donors[rng.randi_range(0,donors.size()-1)]
	return {"version": VERSION, "seed": seed_value, "modules": modules, "face": face, "profile": profile,
		"height": rng.randf_range(0.85, 1.15), "thickness": rng.randf_range(0.85, 1.15), "head_scale": rng.randf_range(0.95, 1.05), "registration": {}}

func validate(r: Dictionary) -> String:
	if r.get("version") != VERSION: return "RECIPE_VERSION"
	if r.has("neck_attachment"):
		var attachment=r.neck_attachment
		var sockets=preload("res://mini/layered2d/data/neck_attachment.gd")
		if not attachment is Dictionary or attachment.get("version")!=2:return "NECK_ATTACHMENT_VERSION"
		if not sockets.validate_points(attachment.get("head"),9) or not sockets.validate_points(attachment.get("collar"),9):return "NECK_ATTACHMENT_POINTS"
	for group in r.get("part_sources",{}):
		var source=int(r.part_sources[group])
		if not GROUPS.has(group) or source<0 or source>=configs.size():return "PART_SOURCE_INVALID: "+str(group)
	var secondary_check:Dictionary=preload("res://mini/layered2d/prepare/secondary_motion.gd").validate(r.get("secondary",{}))
	if not secondary_check.ok:return str(secondary_check.code)
	for key in ["modules", "face", "profile", "registration"]:
		if not r.get(key) is Dictionary: return "RECIPE_FIELD: " + key
	for key in ["head", "upper_body", "lower_body", "arms", "legs"]:
		if int(r.modules.get(key, -1)) < 0 or int(r.modules.get(key, -1)) >= configs.size(): return "ASSET_MISSING: " + key
	if configs[int(r.modules.head)].face.get("mode","registered")=="baked" and (not r.face.is_empty() or not r.get("expression",{}).is_empty()):return "BAKED_FACE_NO_PARTS"
	for seam in [["head","upper_body","neck"],["upper_body","arms","shoulder"],["upper_body","lower_body","waist"],["lower_body","legs","hip"]]:
		var a: String=configs[int(r.modules[seam[0]])].get("seam_families",{}).get(seam[2],"b_cutout_v1")
		var b: String=configs[int(r.modules[seam[1]])].get("seam_families",{}).get(seam[2],"b_cutout_v1")
		if a!=b:return "SEAM_INCOMPATIBLE: "+seam[2]+" / "+a+" / "+b
	for key in ["height", "thickness", "head_scale"]:
		if not r.get(key) is float and not r.get(key) is int: return "NUMBER: " + key
		if not is_finite(float(r[key])): return "NUMBER: " + key
	if r.height < 0.75 or r.height > 1.25 or r.thickness < 0.8 or r.thickness > 1.2 or r.head_scale < 0.8 or r.head_scale > 1.2: return "BODY_RANGE"
	var prototype_index:=int(r.get("prototype_index",r.modules.head))
	if prototype_index<0 or prototype_index>=configs.size():return "PROTOTYPE_MISSING"
	var base: Dictionary = configs[prototype_index].profile
	if r.has("body_sets"):
		var resolved:=preload("res://mini/layered2d/data/body_sets.gd").apply(r,configs)
		if not resolved.ok:return "BODY_SETS: "+str(resolved.error)
		base=resolved.recipe.resolved_shape.profile_reference
	for key in base:
		if key=="shoulder_depth":continue # Signed offset validated by BodySets.
		var n: float = float(r.profile.get(key, -1))
		if not is_finite(n) or n < float(base[key]) * 0.75 or n > float(base[key]) * 1.25: return "PROFILE_RANGE: " + key
	for slot in r.face:
		if slot not in ["eye_l", "eye_r", "brow_l", "brow_r", "mouth"] or int(r.face[slot]) < 0 or int(r.face[slot]) >= configs.size(): return "FACE_ASSET"
		if configs[int(r.face[slot])].face.get("mode","registered")=="baked":return "FACE_DONOR_NOT_REGISTERED"
	if not r.get("expression",{}) is Dictionary:return "EXPRESSION_FORMAT"
	var baked_expression:bool=r.get("asset_face",{}).get("mode")=="baked" and not r.get("expression",{}).is_empty()
	if baked_expression:
		# 一枚絵の顔：{"baked": 名前}（expression_atlases の名前）か、旧来の目閉じ {"eye_l":"closed","eye_r":"closed"}。
		var atlases: Dictionary=r.asset_face.get("expression_atlases",{})
		var named: bool=r.expression.size()==1 and r.expression.has("baked") and atlases.has(str(r.expression.baked))
		var closed: bool=r.expression=={"eye_l":"closed","eye_r":"closed"} and atlases.has("closed")
		if not named and not closed:return "BAKED_EXPRESSION_MISSING"
	for id in r.get("expression",{}):
		if baked_expression:continue
		var found:=false
		var source:=int(r.face.get(id,r.modules.head))
		for slot in r.get("asset_face",configs[source].face).registered.slots:
			if slot.id==id and slot.variants.has(r.expression[id]):found=true
		if not found:return "EXPRESSION_ASSET_MISSING: "+id
	for slot in r.registration:
		if not SLOTS.has(slot): return "REGISTRATION_SLOT"
		var values = r.registration[slot]
		if not values is Array or values.size() != 5: return "REGISTRATION_FORMAT"
		for value in values:
			if not (value is float or value is int) or not is_finite(float(value)): return "REGISTRATION_NUMBER"
		if values[3] <= 0 or values[4] <= 0: return "REGISTRATION_SCALE"
	return ""

static func fingerprint(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

func face_donors() -> Array:
	var result: Array=[]
	for i in range(configs.size()):
		if configs[i].face.get("mode","registered")!="baked":result.append(i)
	return result

func source_for(r: Dictionary, slot: int) -> int:
	if r.get("part_sources",{}).has(GROUPS[slot]):return int(r.part_sources[GROUPS[slot]])
	return int(r.modules[MODULES[slot]])

func secondary_for(r:Dictionary)->Dictionary:
	var result:Dictionary={}
	for part in preload("res://mini/layered2d/prepare/secondary_motion.gd").PARTS:
		var registered:Dictionary=configs[source_for(r,SLOTS.find(part))].get("secondary",{})
		if registered.has(part):result[part]=registered[part].duplicate(true)
	for part in r.get("secondary",{}):
		var entry:Dictionary=result.get(part,{}).duplicate(true)
		entry.merge(r.secondary[part],true);result[part]=entry
	# 胸・尻の揺れ（soft.breast / soft.butt）。左右で anchor の x を反転する。
	for kind in ["breast","butt"]:
		var soft:Dictionary=r.get("soft",{}).get(kind,{})
		if soft.is_empty():continue
		for side in ["l","r"]:
			var entry:Dictionary={}
			for key in ["lag","damping","amount","max_offset"]:
				if soft.has(key):entry[key]=soft[key]
			var anchor:Array=soft.get("anchor",[0.09,0.05,0.12] if kind=="breast" else [0.08,-0.06,-0.12])
			entry.anchor=[float(anchor[0])*(1.0 if side=="l" else -1.0),float(anchor[1]),float(anchor[2])]
			result[kind+"_"+side]=entry
	return result
