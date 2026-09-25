extends RefCounted
const Store = preload("res://mini/layered2d/prepare/resource_store.gd")
const Compiler = preload("res://mini/layered2d/prepare/motion_compiler.gd")
var thread: Thread
var mutex := Mutex.new()
var progress := 0
var total := 0
var result: Dictionary = {}
var revision := 0
var cancelled := false

func start(recipes: Array, clips: Array, next_clips: Array = []) -> void:
	assert(thread==null)
	revision+=1
	cancelled=false
	progress=0
	total=recipes.size()
	# Shader loading and GPU resources belong to the main thread.
	var store := Store.new()
	thread=Thread.new()
	thread.start(_build.bind(store,recipes.duplicate(true),clips.duplicate(),next_clips.duplicate(),revision))

func _build(store, recipes: Array, clips: Array, next_clips: Array, request: int) -> void:
	var started := Time.get_ticks_usec()
	var compiler := Compiler.new()
	var handles: Array = []
	var next_handles: Array = []
	for i in range(recipes.size()):
		mutex.lock()
		var stop := cancelled
		mutex.unlock()
		if stop: return
		var error: String=store.catalog.validate(recipes[i])
		if not error.is_empty(): result={"ok":false,"error":error,"revision":request};return
		var r: Dictionary=recipes[i]
		var config: Dictionary=store.catalog.configs[int(r.get("prototype_index",r.modules.head))]
		var motion_options:Dictionary={"secondary":store.catalog.secondary_for(r)}
		var track: Dictionary=compiler.compile(config,r.profile,clips[i],motion_options)
		var index: int=store.add_track(track)
		if index<0: result={"ok":false,"error":store.last_error,"diagnostic":compiler.last_diagnostic,"revision":request};return
		handles.append(index)
		store.bind_actor(i,r,track.rest_radii)
		if not next_clips.is_empty():
			var next: Dictionary=compiler.compile(config,r.profile,next_clips[i],motion_options)
			var n: int=store.add_track(next)
			if n<0:result={"ok":false,"error":store.last_error,"revision":request};return
			next_handles.append(n)
		mutex.lock()
		progress=i+1
		mutex.unlock()
	var capacity_error: String=store.validate_capacity()
	if not capacity_error.is_empty():result={"ok":false,"error":capacity_error,"revision":request};return
	result={"ok":true,"store":store,"handles":handles,"next_handles":next_handles,"recipes":recipes,"revision":request,"prepare_ms":(Time.get_ticks_usec()-started)/1000.0}

func poll() -> Dictionary:
	if thread==null or thread.is_alive():return {}
	thread.wait_to_finish()
	thread=null
	return result

func status() -> Vector2i:
	mutex.lock()
	var value:=Vector2i(progress,total)
	mutex.unlock()
	return value

func stop() -> void:
	mutex.lock()
	cancelled=true
	mutex.unlock()
	if thread!=null:
		thread.wait_to_finish()
		thread=null
