extends RefCounted
const Adapter = preload("res://mini/layered2d/prepare/rig_pose_adapter.gd")
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const LayerCompiler = preload("res://mini/layered2d/prepare/layer_compiler.gd")
const VERSION = 7
var last_diagnostic: Dictionary = {}

func compile(config: Dictionary, profile: Dictionary, clip: String, options: Dictionary = {}) -> Dictionary:
	var key := Catalog.fingerprint([VERSION, config.neutral_stand, config.get("secondary",{}), config.get("shape_motion",{}), profile, clip, options,
		FileAccess.get_modified_time("res://mini/rig3d/data/motions.json"), FileAccess.get_modified_time("res://mini/rig3d/solver.gd"),
		FileAccess.get_modified_time("res://mini/layered2d/prepare/rig_pose_adapter.gd"),
		FileAccess.get_modified_time("res://mini/rig3d/library.gd"),
		FileAccess.get_modified_time("res://mini/projected2d/b_cutout/retarget.gd"),
		FileAccess.get_modified_time("res://mini/layered2d/prepare/secondary_motion.gd"),
		FileAccess.get_modified_time("res://mini/layered2d/prepare/layer_compiler.gd")])
	var path := "user://layered2d/motion_" + key + ".bin"
	if not options.get("no_cache", false) and FileAccess.file_exists(path):
		var cached = FileAccess.open(path, FileAccess.READ).get_var()
		if cached is Dictionary and cached.get("version") == VERSION: return cached
	var actor := Adapter.new()
	# Optional game-owned motion library; existing authoring defaults are unchanged.
	if options.has("motion_source"):
		if not actor.library.load_files(actor.library.CHARACTER_PATH, str(options.motion_source)):
			return failure("MOTION_SOURCE_INVALID", {"error":actor.library.error})
	actor.configure(config, profile)
	if clip not in Catalog.CLIPS and not actor.library.clips.has(clip): return failure("CLIP_MISSING", {"clip": clip})
	actor.clip = clip
	var duration := actor.duration()
	actor.secondary_settings=options.get("secondary",actor.secondary_settings).duplicate(true)
	var baked:=actor.bake_secondary(duration)
	if not baked.ok:return failure(baked.code,baked)
	var count := maxi(1, ceili(duration * 24.0))
	var times: Array[float] = []
	for i in range(count + 1): times.append(float(i) / count)
	for k in actor.library.clips.get(clip, {}).get("keys", []):
		if not times.has(float(k.t)): times.append(float(k.t))
	# Authored and analytic cycle extrema are mandatory, not inferred from frame cadence.
	for p in options.get("mandatory_phases", [0.0, 0.25, 0.5, 0.75, 1.0]):
		if not times.has(float(p)): times.append(float(p))
	for rule in options.get("layer_rules",[]):
		for field in ["start","end"]:
			var t: float=rule.get(field,0.0 if field=="start" else 1.0)
			if not times.has(t):times.append(t)
	times.sort()
	var samples: Dictionary = {}
	for t in times: samples[t] = actor.sample(t)
	var threshold: float = options.get("error_world", 0.009)
	var failures: Array = []
	var max_error := 0.0
	var i := 0
	while i < times.size() - 1:
		var a: float = times[i]
		var b: float = times[i + 1]
		var worst := {"error": 0.0}
		for f in [0.25, 0.5, 0.75]:
			var t: float = lerpf(a, b, f)
			if not samples.has(t): samples[t] = actor.sample(t)
			var err := compare(samples[a], samples[b], samples[t], f)
			if err.error > worst.error:
				worst = err
				worst.phase = t
		if worst.error > threshold:
			if (b-a)*duration > 1.0/96.0 + 0.000001:
				times.insert(i+1, (a+b)*0.5)
				continue
			worst.merge({"clip": clip, "interval_seconds": [a*duration,b*duration], "limit_world": threshold,
				"profile": profile, "phase_offset": 0.0, "display_height": 350, "error_px_conservative": worst.error*100.0,
				"camera_yaw": null, "camera_pitch": null, "samples": times.size(), "code": "INTERPOLATION_ERROR_LIMIT"})
			failures.append(worst)
		max_error = maxf(max_error, worst.error)
		i += 1
	if not failures.is_empty():
		failures.sort_custom(func(a,b): return a.error > b.error)
		return failure("INTERPOLATION_ERROR_LIMIT", {"clip": clip, "failure_count": failures.size(), "details": failures.slice(0,32), "max_error": max_error})
	var frames: Array = []
	for t in times: frames.append(samples[t])
	var result := {"ok": true, "version": VERSION, "key": key, "clip": clip, "duration": duration,
		"times": PackedFloat32Array(times), "frames": frames, "max_error_world": max_error, "max_playback_speed": 1.9,
		"validation_speeds": [0.55,1.0,1.1,1.9], "rest_radii": [], "orders": []}
	actor.clip = "idle"
	var reference := actor.sample(0.0)
	for part in reference.parts: result.rest_radii.append(part.radii)
	# Freeze layer order intervals during preparation, never sort parts at runtime.
	for direction in range(8):
		var plans: Array = []
		var yaw := deg_to_rad(direction*45.0)
		var view := Vector3(sin(yaw)*cos(PI/12), sin(PI/12), cos(yaw)*cos(PI/12))
		for frame in range(frames.size()):
			var sample: Dictionary=frames[frame]
			var order: Array = range(sample.parts.size())
			order.sort_custom(func(x,y):
				var dx: float = LayerCompiler.depth(x,sample.parts,view)
				var dy: float = LayerCompiler.depth(y,sample.parts,view)
				return dx < dy if absf(dx-dy) > 0.00001 else x < y)
			var layer_result:=LayerCompiler.resolve(order,Catalog.ALL_SLOTS,options.get("layer_rules",[]),times[frame],direction)
			if not layer_result.ok:return failure(layer_result.code,layer_result)
			plans.append(layer_result.order)
		result.orders.append(plans)
	DirAccess.make_dir_recursive_absolute("user://layered2d")
	FileAccess.open(path + ".tmp", FileAccess.WRITE).store_var(result)
	DirAccess.rename_absolute(path + ".tmp", path)
	return result

static func interpolate(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var q: Quaternion = b.rotation
	if a.rotation.dot(q) < 0: q = -q
	return {"center": a.center.lerp(b.center,t), "rotation": (a.rotation*(1.0-t)+q*t).normalized(), "radii": a.radii.lerp(b.radii,t),"anchor":Vector3(a.get("anchor",a.center)).lerp(b.get("anchor",b.center),t)}

static func compare(a: Dictionary, b: Dictionary, actual: Dictionary, t: float) -> Dictionary:
	var worst := {"error": 0.0, "socket": "", "expected": Vector3.ZERO, "actual": Vector3.ZERO}
	for socket in actual.joints:
		if not actual.joints[socket] is Vector3 or not a.joints.has(socket) or not b.joints.has(socket): continue
		var guess: Vector3 = a.joints[socket].lerp(b.joints[socket],t)
		var err := guess.distance_to(actual.joints[socket])
		if err > worst.error: worst = {"error": err, "socket": "joint:"+socket, "expected": actual.joints[socket], "actual": guess}
	for p in range(actual.parts.size()):
		var guess := interpolate(a.parts[p],b.parts[p],t)
		for axis in [Vector3.ZERO, Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
			var point: Vector3 = guess.center + Basis(guess.rotation)*(axis*guess.radii)
			var source: Dictionary = actual.parts[p]
			var target: Vector3 = source.center + Basis(source.rotation)*(axis*source.radii)
			var err := point.distance_to(target)
			if err > worst.error: worst = {"error": err,"socket":"part:"+Catalog.ALL_SLOTS[p],"expected":target,"actual":point}
	return worst

func failure(code: String, detail: Dictionary) -> Dictionary:
	last_diagnostic = {"ok": false,"code":code,"details":detail,"version":VERSION}
	DirAccess.make_dir_recursive_absolute("user://layered2d")
	FileAccess.open("user://layered2d/last_compile_failure.json",FileAccess.WRITE).store_string(JSON.stringify(last_diagnostic,"\t"))
	return last_diagnostic
