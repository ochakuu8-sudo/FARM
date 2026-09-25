extends RefCounted
const FaceComposer=preload("res://mini/layered2d/prepare/face_composer.gd")
var thread: Thread
var result: Dictionary={}
var handle:=Vector2i(-1,-1)
var recipe: Dictionary={}
var started_usec:=0

func start(target: Vector2i, requested: Dictionary, configs: Array) -> void:
	assert(thread==null)
	handle=target;recipe=requested.duplicate(true);started_usec=Time.get_ticks_usec()
	thread=Thread.new();thread.start(_compose.bind(configs.duplicate(true)))

func _compose(configs: Array) -> void:
	result=FaceComposer.compose(recipe,configs)

func poll() -> Dictionary:
	if thread==null or thread.is_alive():return {}
	thread.wait_to_finish();thread=null
	result.handle=handle;result.recipe=recipe;result.prepare_ms=(Time.get_ticks_usec()-started_usec)/1000.0
	return result

func stop() -> void:
	if thread!=null:thread.wait_to_finish();thread=null
