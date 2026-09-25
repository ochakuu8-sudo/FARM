extends RefCounted
const Library := preload("res://mini/rig3d/library.gd")
const Solver := preload("res://mini/rig3d/solver.gd")
const STEP := 1.0 / 120.0
var library := Library.new()
var solver := Solver.new()
var clip := "squat_cycle"
var phase := 0.0
var speed := 1.0
var accumulator := 0.0
var ticks := 0
var parts: Array = []
var profile: Dictionary = {}
var root := Vector3.ZERO
var world_yaw:=0.0
var goal_overrides:Dictionary={}
var secondary_enabled:=false
var secondary_offset:=Vector3.ZERO
var secondary_velocity:=Vector3.ZERO
var anchor_previous:=Vector3.ZERO
var anchor_previous2:=Vector3.ZERO
var anchor_initialized:=false
var twist := 0.0
var pouch := true
var deformation := 1.0
var contacts_error := 0.0
func _init() -> void:
	var loaded:=library.load_files();assert(loaded, library.error)
	profile = library.profiles.explorer.duplicate(true)
func advance(dt: float) -> void:
	accumulator += dt
	# Never discard elapsed simulation time. Rendering is separate from the clock.
	while accumulator + 1e-10 >= STEP:
		phase = fposmod(phase + STEP * speed / duration(), 1.0)
		accumulator -= STEP
		ticks += 1
		if secondary_enabled:update_secondary(STEP)
	accumulator=maxf(accumulator,0.0)
func duration() -> float:
	return float(library.clips.get(clip, {"duration": 4.0}).duration)
func save_state() -> Dictionary:
	return {"version":1,"clip":clip,"phase":phase,"speed":speed,"accumulator":accumulator,"ticks":ticks,"twist":twist,"pouch":pouch,"deformation":deformation,"root":[root.x,root.y,root.z],"world_yaw":world_yaw,"secondary_enabled":secondary_enabled,"secondary_offset":[secondary_offset.x,secondary_offset.y,secondary_offset.z],"secondary_velocity":[secondary_velocity.x,secondary_velocity.y,secondary_velocity.z],"anchor_previous":[anchor_previous.x,anchor_previous.y,anchor_previous.z],"anchor_previous2":[anchor_previous2.x,anchor_previous2.y,anchor_previous2.z],"anchor_initialized":anchor_initialized}
func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or (not str(data.get("clip", "")) in clip_ids() and not library.clips.has(data.get("clip"))): return false
	for key in ["phase", "speed", "accumulator", "twist", "deformation"]:
		if not data.get(key) is float and not data.get(key) is int: return false
		if not is_finite(float(data[key])): return false
	if not data.get("ticks") is int and not data.get("ticks") is float:return false
	if not data.get("pouch") is bool:return false
	if data.phase<0 or data.phase>1 or data.speed<0 or data.speed>4 or data.accumulator<0 or data.accumulator>STEP or data.ticks<0:return false
	for key in ["root","secondary_offset","secondary_velocity","anchor_previous","anchor_previous2"]:
		if data.has(key) and not library.vector(data[key]):return false
	if data.has("world_yaw") and not library.number(data.world_yaw):return false
	for key in ["secondary_enabled","anchor_initialized"]:
		if data.has(key) and not data[key] is bool:return false
	clip = data.clip; phase = data.phase; speed = data.speed; accumulator = data.accumulator
	ticks = int(data.ticks); twist = data.twist; pouch = bool(data.pouch); deformation = data.deformation
	root=Library.vec(data.get("root",[0,0,0]));world_yaw=data.get("world_yaw",0.0)
	secondary_enabled=data.get("secondary_enabled",false);anchor_initialized=data.get("anchor_initialized",false)
	secondary_offset=Library.vec(data.get("secondary_offset",[0,0,0]));secondary_velocity=Library.vec(data.get("secondary_velocity",[0,0,0]))
	anchor_previous=Library.vec(data.get("anchor_previous",[0,0,0]));anchor_previous2=Library.vec(data.get("anchor_previous2",[0,0,0]))
	return true
func clip_ids() -> Array:
	return ["squat_cycle", "reach_cycle", "wave", "cross", "all_fours", "sit", "kneel", "idle", "twist_test", "unseen"]
func evaluate() -> Array:
	var pose: Dictionary
	if clip in ["reach_cycle", "twist_test", "unseen"]:
		pose = Library.mix(library.poses.stand, library.poses.reach, (1.0 - cos(phase * TAU)) * 0.5)
		if clip == "twist_test": pose = library.poses.reach.duplicate(true)
		if clip == "unseen":
			pose.head_yaw = sin(phase * TAU) * 28.0
			pose.hand_l = [0.66, 2.5 + 0.55 * sin(phase * TAU), 0.55]
	else: pose = library.sample(clip, phase)
	pose=prepare_pose(pose)
	solver.overrides=goal_overrides.duplicate(true)
	solver.solve(profile, pose)
	contacts_error = solver.maximum_error()
	var j: Dictionary = solver.joints
	parts.clear()
	# 胸から上（胸・首・腕の付け根）は背骨の曲げを含む chest_basis。曲げが0なら torso_basis と同じ。
	var b: Basis = solver.chest_basis
	add("pelvis", "waist", j.pelvis + Vector3(0,-0.03,0), Basis.IDENTITY, Vector3(.37,.23,.25))
	add("abdomen", "coat", solver.torso_point(.28), solver.torso_basis, Vector3(.32,.29,.23))
	add("chest", "coat", solver.torso_point(.74), b, Vector3(.46,.34,.24))
	add("neck", "neck", j.chest.lerp(j.neck,.6), b, Vector3(.145,.17,.14))
	add("head", "head", j.head, solver.head_basis, Vector3(.47,.51,.39))
	# Hair is a removable attachment with the same depth contract.
	add("hair", "hair", j.head + solver.head_basis * Vector3(0,.05,-.29), solver.head_basis, Vector3(.46,.48,.13))
	for side in ["l", "r"]:
		var sign_side := 1.0 if side == "l" else -1.0
		var spin := deg_to_rad(twist + (sin(phase * TAU) * 170.0 if clip == "twist_test" else 0.0)) * sign_side
		limb("upper_"+side,"sleeve",j["shoulder_"+side],j["elbow_"+side],.175,.155, b.z, 0)
		limb("fore_"+side,"sleeve",j["elbow_"+side],j["wrist_"+side],.145,.135, b.z, spin)
		var hand_dir: Vector3 = solver.directions["hand_"+side]
		limb("hand_"+side,"hand",j["wrist_"+side],j["wrist_"+side]+hand_dir*.24,.135,.09, b.z, spin)
		limb("thigh_"+side,"trouser",j["hip_"+side],j["knee_"+side],.215,.20,Vector3.BACK,0)
		limb("shin_"+side,"trouser",j["knee_"+side],j["ankle_"+side],.17,.16,Vector3.BACK,0)
		var ankle: Vector3 = j["ankle_"+side]
		var foot_center := ankle + Vector3(0,-.10,.08)
		add("boot_"+side,"boot",foot_center,Basis.IDENTITY,Vector3(.19,.105,.30))
		# Joint caps overlap the sprite ends; they carry image + depth, not opaque screen circles.
		add("elbow_"+side,"sleeve",j["elbow_"+side],b,Vector3(.158,.158,.15))
		add("knee_"+side,"trouser",j["knee_"+side],Basis.IDENTITY,Vector3(.192,.192,.185))
	if pouch: add("pouch", "pouch", j.pelvis + Vector3(.35,-.02,.18), b, Vector3(.17,.22,.12))
	return parts
func prepare_pose(pose:Dictionary)->Dictionary:
	return pose
func render_scale()->float:
	return 1.0
func solver_to_world(point:Vector3)->Vector3:
	return root+Basis(Vector3.UP,deg_to_rad(world_yaw))*point*render_scale()
func world_to_solver(point:Vector3)->Vector3:
	return Basis(Vector3.UP,deg_to_rad(world_yaw)).transposed()*(point-root)/render_scale()
func world_of(joint_name:String)->Vector3:
	evaluate()
	assert(solver.joints.has(joint_name),"Unknown joint: "+joint_name)
	return solver_to_world(solver.joints[joint_name])
func socket_position(socket:String,evaluated:Array=[])->Dictionary:
	var current:Array=evaluate() if evaluated.is_empty() else evaluated
	if socket.begins_with("joint:"):
		var joint:=socket.trim_prefix("joint:")
		if not solver.joints.has(joint):return {"ok":false,"error":"Unknown joint: "+joint}
		return {"ok":true,"position":solver_to_world(solver.joints[joint]),"space":"render_world"}
	if socket in ["sole_l","sole_r"]:
		var ankle:Vector3=solver.joints["ankle_"+socket.right(1)]
		return {"ok":true,"position":solver_to_world(ankle-Vector3(0,.2*profile.head,0)),"space":"render_world"}
	var name:=socket.trim_prefix("part:")
	for part in current:
		if part.id==name:return {"ok":true,"position":part.center,"space":"render_world"}
	return {"ok":false,"error":"Unknown part/socket: "+socket}
func target_for_socket(goal:String,socket:String,target:Vector3,evaluated:Array=[])->Dictionary:
	if goal not in ["hand_l","hand_r","foot_l","foot_r"] or not target.is_finite():
		return {"ok":false,"error":"Invalid IK goal or position: "+goal}
	var current:Array=evaluate() if evaluated.is_empty() else evaluated
	var side:=goal.right(1)
	var allowed:Array=["part:hand_"+side,"joint:wrist_"+side,"joint:hand_"+side] if goal.begins_with("hand") else ["sole_"+side,"joint:ankle_"+side,"joint:foot_"+side,"part:boot_"+side]
	if not socket.contains(":") and socket.begins_with("hand_"):socket="part:"+socket
	if socket not in allowed:return {"ok":false,"error":"Socket does not belong to goal: "+socket+" / "+goal}
	if goal.begins_with("foot") and solver.control.support!="feet" and (not str(solver.control.support).begins_with("half_kneel") or str(solver.control.support).ends_with(side)):
		return {"ok":false,"error":"Foot IK is supported only by support=feet; knee support has fixed knees"}
	var point:=socket_position(socket,current)
	if not point.ok:return point
	var joint:String=("wrist_" if goal.begins_with("hand") else "ankle_")+side
	var local_offset:Vector3=world_to_solver(point.position)-Vector3(solver.joints[joint])
	return {"ok":true,"target":world_to_solver(target)-local_offset,"space":"solver","socket":socket}
func set_pose(pose:Dictionary)->Dictionary:
	if not library.validate_pose(pose):return {"ok":false,"error":library.error}
	library.poses["__external"]=pose.duplicate(true)
	library.clips["__external"]={"id":"__external","name":"External pose","duration":1.0,"keys":[{"t":0.0,"pose":"__external"},{"t":1.0,"pose":"__external"}]}
	clip="__external";phase=0.0
	return {"ok":true}
func limb(id: String, kind: String, a: Vector3, end: Vector3, rx: float, rz: float, normal: Vector3, spin: float) -> void:
	var y := (a-end).normalized()
	var z := normal - y * normal.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.UP - y * y.y
		if z.length_squared() < 0.0001: z = Vector3.RIGHT - y * y.x
	z = z.normalized()
	var basis := Basis(y.cross(z).normalized(), y, z) * Basis(Vector3.UP, spin)
	add(id, kind, (a+end)*.5, basis, Vector3(rx, a.distance_to(end)*.5 + rx*.55, rz))
func add(id: String, kind: String, center: Vector3, basis: Basis, radii: Vector3) -> void:
	var world:=Basis(Vector3.UP,deg_to_rad(world_yaw))
	var location:=world*center+root
	if id=="hair" and secondary_enabled:location+=secondary_offset
	parts.append({"id":id,"kind":kind,"center":location,"basis":world*basis,"radii":radii,"warp":sin(phase*TAU)*.022*deformation if kind == "coat" else 0.0})
func update_secondary(h:float)->void:
	# Evaluate anchors at the simulation tick, never from a camera or render frame.
	evaluate()
	var anchor:Vector3=Basis(Vector3.UP,deg_to_rad(world_yaw))*solver.joints.head+root
	if not anchor_initialized:
		anchor_previous=anchor;anchor_previous2=anchor;anchor_initialized=true
	var acceleration:Vector3=(anchor-2*anchor_previous+anchor_previous2)/(h*h)
	secondary_velocity+=(-70.0*secondary_offset-12.0*secondary_velocity-.20*acceleration)*h
	secondary_offset+=secondary_velocity*h
	if secondary_offset.length()>.06:
		secondary_offset=secondary_offset.normalized()*.06
		var normal:=secondary_offset.normalized()
		secondary_velocity-=normal*maxf(0,secondary_velocity.dot(normal))
	anchor_previous2=anchor_previous;anchor_previous=anchor
