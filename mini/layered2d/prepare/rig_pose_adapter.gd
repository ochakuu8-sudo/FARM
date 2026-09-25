extends "res://mini/projected2d/pose_source.gd"
## Canonical, pre-art coordinates. No texture offsets, palette, display_scale or face composition.
const Retarget = preload("res://mini/projected2d/b_cutout/retarget.gd")
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const Secondary=preload("res://mini/layered2d/prepare/secondary_motion.gd")
var target_profile: Dictionary = {}
var reference_pose: Dictionary = {}
var retarget := Retarget.new()
var body_scale := 1.0
var secondary_settings:Dictionary={}
var secondary_track:Array=[]
var secondary_phase:float=0.0
var arm_clearance:=0.0
var centers:Dictionary={}

func render_scale() -> float:
	return body_scale

func configure(config: Dictionary, requested_profile: Dictionary) -> void:
	arm_clearance=float(config.get("shape_motion",{}).get("arm_clearance",0))
	centers=config.get("shape_motion",{}).get("centers",{}).duplicate(true)
	secondary_settings=config.get("secondary",{}).duplicate(true)
	secondary_track=[]
	target_profile = library.profiles.explorer.duplicate(true)
	target_profile.merge(requested_profile, true)
	for key in config.neutral_stand:
		library.poses.stand[key] = config.neutral_stand[key].duplicate()
	pouch = false
	# Common defaults for built-in motions; scene-authored wrist/contact settings override these.
	for name in ["stand","squat","sit","kneel","cross","wave","reach"]:
		if not library.poses.has(name):continue
		for side in ["l","r"]:
			library.poses[name]["hand_follow_"+side]=1.0
			library.poses[name]["wrist_"+side]=[8,0,0] if name=="squat" else [0,0,0]
	if library.poses.has("squat"):library.poses.squat.pelvis_pitch=12.0
	if library.poses.has("all_fours"):
		for side in ["l","r"]:library.poses.all_fours["palm_normal_"+side]=[0,-1,0]

func prepare_pose(pose: Dictionary) -> Dictionary:
	reference_pose = pose.duplicate(true)
	profile = target_profile
	var adjusted:Dictionary=retarget.pose_for(pose, library.profiles.explorer, target_profile)
	# Contact overrides are solved afterwards. Only widen unsupported hands close
	# to the torso, leaving reaching and planted-hand poses unchanged.
	if arm_clearance>0 and pose.get("support","")!="hands_knees":
		for side in ["l","r"]:
			var key:String="hand_"+side
			if not adjusted.has(key):continue
			var hand:Array=adjusted[key].duplicate()
			var proximity:float=1.0-smoothstep(.25,.65,absf(float(hand[2])))
			proximity*=1.0-smoothstep(float(target_profile.hip_height)+float(target_profile.torso)*.25,float(target_profile.hip_height)+float(target_profile.torso)*.75,float(hand[1]))
			proximity*=1.0-smoothstep(float(target_profile.shoulder)+.12,float(target_profile.shoulder)+.30,absf(float(hand[0])))
			hand[0]+=arm_clearance*proximity*(1.0 if side=="l" else -1.0)
			adjusted[key]=hand
	return adjusted

func evaluate() -> Array:
	var raw: Array = super.evaluate()
	var out: Array = []
	var world:=Basis(Vector3.UP,deg_to_rad(world_yaw))
	var by_id:Dictionary={}
	for part in raw:by_id[part.id]=part
	for side in ["l","r"]:
		var hand:Dictionary=by_id["hand_"+side]
		var wrist:Vector3=solver.joints["wrist_"+side]
		var follow:Basis=world.inverse()*by_id["fore_"+side].basis
		var axis:Vector3=solver.directions["hand_"+side]
		var normal:Vector3=Library.vec(solver.control.get("palm_normal_"+side,[0,0,1]))
		var y:Vector3=-axis
		var z:Vector3=normal-y*normal.dot(y)
		if z.length_squared()<0.0001:
			z=follow.z-y*follow.z.dot(y)
			if z.length_squared()<0.0001:z=Vector3.RIGHT-y*y.x
		z=z.normalized()
		var explicit_basis:=Basis(y.cross(z).normalized(),y,z)
		var local_rotation:=Basis.from_euler(Library.vec(solver.control.get("wrist_"+side,[0,0,0]))*PI/180)
		var orientation:=Basis(explicit_basis.get_rotation_quaternion().slerp(follow.get_rotation_quaternion(),float(solver.control.get("hand_follow_"+side,0))))*local_rotation
		var direction:Vector3=-orientation.y
		hand.basis=world*orientation
		hand.center=world*(wrist+direction*.12)+root
		solver.directions["hand_"+side]=direction
		solver.joints["hand_"+side]=wrist+direction*.15*profile.head
	for part in raw:
		if not Catalog.SLOTS.has(part.id): continue
		var joint:String=""
		for side in ["l","r"]:
			for entry in [["upper_","shoulder_"],["fore_","elbow_"],["hand_","wrist_"],["thigh_","hip_"],["shin_","knee_"],["boot_","ankle_"],["elbow_","elbow_"],["knee_","knee_"]]:
				if part.id==entry[0]+side:joint=entry[1]+side
		part.anchor=world*solver.joints[joint]+root if not joint.is_empty() else part.center
		if part.id=="chest":
			part.center=world*solver.torso_point(float(centers.get("chest",.64)))+root
		if part.id=="abdomen":
			part.center=world*solver.torso_point(float(centers.get("abdomen",.19)))+root
		if part.id in ["pelvis", "abdomen"]:
			part.basis = world*solver.pelvis_basis
			if part.id=="pelvis":part.center = world * solver.joints.pelvis + root
		# Long-axis coverage follows the actual bone, with a small shared seam allowance.
		# The old radius-sized allowance overwhelmed short chibi limbs.
		for side in ["l","r"]:
			for chain in [["upper_","shoulder_","elbow_"],["fore_","elbow_","wrist_"],["thigh_","hip_","knee_"],["shin_","knee_","ankle_"]]:
				if part.id==chain[0]+side:
					part.radii.y=solver.joints[chain[1]+side].distance_to(solver.joints[chain[2]+side])*0.5+0.035
		part.center=root+(part.center-root)*body_scale
		part.anchor=root+(part.anchor-root)*body_scale
		part.radii*=body_scale
		out.append(part)
	# Three disjoint UV regions share one pelvis artwork and transform.
	# Their layer depths can straddle the near and far thighs without adding textures.
	for side in ["l","r"]:
		var region:Dictionary=out[0].duplicate(true);region.id="pelvis_"+side;out.append(region)
	var offsets:=Secondary.sample(secondary_track,secondary_phase)
	for part in out:
		var id:String="pelvis" if part.id in ["pelvis_l","pelvis_r"] else part.id
		if offsets.has(id):
			part.center+=offsets[id];part.anchor+=offsets[id]
		# 胸・尻の左右の遅れ。親の回転の逆で親ローカルへ、体格倍率で割って部位座標と同じ単位にする。
		# 胸は chest.soft、尻は pelvis.soft_butt（pelvis_l/r は上で複製済みなので持たない）。
		for kind in [["chest","breast","soft"],["pelvis","butt","soft_butt"]]:
			if part.id==kind[0] and (offsets.has(kind[1]+"_l") or offsets.has(kind[1]+"_r")):
				var inverse:Basis=part.basis.orthonormalized().inverse()
				part[kind[2]]=[inverse*offsets.get(kind[1]+"_l",Vector3.ZERO)/body_scale,inverse*offsets.get(kind[1]+"_r",Vector3.ZERO)/body_scale]
	append_props(out)
	return out

## 付属物の枠（武器・盾・耳・尻尾・男性器、Catalog.PROP_SLOTS）。親の部位の位置と向きから求める。
## 絵の大きさは描画の設定（束縛表）で決まるので、ここの radii は補間の誤差を測るための小さな値。
## weapon_*：手のひらの中心。+Y が刃の向き（握りの軸＝手の横方向）、+Z が手のひらの向き。
## ears：頭と同じ位置と向き（描画で頭の絵の上へ広げた枠に描く）。tail / groin：腰の背中側・前側の付け根。向きは腰と同じ。
const PROP_RADII:=Vector3(0.05,0.05,0.05)
const TAIL_ROOT:=Vector3(0,-0.03,-0.17)
const GROIN_ROOT:=Vector3(0,-0.12,0.14)
func append_props(out:Array)->void:
	var by:Dictionary={}
	for part in out:by[part.id]=part
	for side in ["r","l"]:
		var hand:Dictionary=by["hand_"+side]
		var b:Basis=hand.basis.orthonormalized()
		var y:Vector3=b.x*(-1.0 if side=="r" else 1.0)
		var z:Vector3=b.z
		var basis:=Basis(y.cross(z).normalized(),y,z)
		out.append({"id":"weapon_"+side,"center":hand.center,"basis":basis,"radii":PROP_RADII*body_scale,"anchor":hand.center})
	var head:Dictionary=by["head"]
	out.append({"id":"ears","center":head.center,"basis":head.basis,"radii":PROP_RADII*body_scale,"anchor":head.center})
	var pelvis:Dictionary=by["pelvis"]
	var pb:Basis=pelvis.basis.orthonormalized()
	for entry in [["tail",TAIL_ROOT],["groin",GROIN_ROOT]]:
		var root_point:Vector3=pelvis.center+pb*(entry[1]*body_scale)
		out.append({"id":entry[0],"center":root_point,"basis":pb,"radii":PROP_RADII*body_scale,"anchor":root_point})

func bake_secondary(duration_seconds:float)->Dictionary:
	secondary_track=[]
	var check:=Secondary.validate(secondary_settings)
	if not check.ok:return check
	if not Secondary.enabled(secondary_settings):return {"ok":true}
	var count:=maxi(2,ceili(duration_seconds*Secondary.HZ))
	var frames:Array=[]
	for i in range(count+1):
		phase=float(i)/count
		var frame:Dictionary={}
		for part in evaluate():
			if part.id in Secondary.PARTS:frame[part.id]=part.center
			for soft in Secondary.SOFT_PARTS:
				if part.id==Catalog.SLOTS[Secondary.soft_slot(soft)]:
					var a:Array=secondary_settings.get(soft,{}).get("anchor",[0,0,0])
					frame[soft]=part.center+part.basis*Vector3(a[0],a[1],a[2])*body_scale
		frames.append(frame)
	var result:=Secondary.bake(frames,secondary_settings,duration_seconds,body_scale)
	if result.ok:secondary_track=result.frames
	return result

func sample(at: float, effect_at:float=NAN) -> Dictionary:
	phase = clampf(at, 0.0, 1.0)
	secondary_phase=phase if is_nan(effect_at) else clampf(effect_at,0,1)
	var raw := evaluate()
	var frames: Array = []
	for part in raw:
		frames.append({"center": part.center, "rotation": part.basis.get_rotation_quaternion().normalized(), "radii": part.radii,"anchor":part.anchor})
		if part.has("soft"):frames[-1].soft=part.soft
		if part.has("soft_butt"):frames[-1].soft_butt=part.soft_butt
	return {"parts": frames, "joints": solver.joints.duplicate(true), "contact_error": contacts_error}
