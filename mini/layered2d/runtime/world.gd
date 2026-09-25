extends Node2D
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const DrawPlans = preload("res://mini/layered2d/render/draw_plan_cache.gd")
var store
var plans := DrawPlans.new()
var meshes: Array[MeshInstance2D] = []
var recipes: Array = []
var track_ids := PackedInt32Array()
var next_ids := PackedInt32Array()
var phases := PackedFloat64Array()
var next_phases := PackedFloat64Array()
var speeds := PackedFloat32Array()
var directions := PackedInt32Array()
var cursors := PackedInt32Array()
var next_cursors := PackedInt32Array()
var last_orders: Array = []
var blend := 0.0
var paused := false
var cpu_ms := 0.0
var state_dirty := true
var selected := 0
var inspect := false
var yaw_free := 0.0
var generation := 0
var head_only:=false
var body_only:=false
var external_rows: Dictionary={}
## 単体の役者を見下ろす角度（ラジアン）。既定は15度。ゲームの牧場では視点に合わせて変える。
var pitch:=PI/12
## 使い終わった描画ノードの置き場（次の World で使い回す。spare_holder.gd）。
const Spare = preload("res://mini/layered2d/runtime/spare_holder.gd")

func _notification(what: int) -> void:
	if what==NOTIFICATION_ENTER_TREE:Spare.ensure()
	elif what==NOTIFICATION_PREDELETE:
		for node in meshes:
			if is_instance_valid(node):Spare.park_mesh(node)
		meshes.clear()
var count: int:
	get: return meshes.size()

func install(bundle: Dictionary) -> void:
	var previous: Dictionary={}
	for i in range(count):previous[recipes[i].seed]=[phases[i],speeds[i],directions[i]]
	# 描画ノードは捨てずに取っておく（GLES3 はシェーダーのインスタンス変数の枠を返さないため）。
	for node in meshes:
		if is_instance_valid(node) and not Spare.park_mesh(node):node.queue_free()
	meshes.clear()
	store=bundle.store
	store.commit()
	# Mesh topology is prepared before publishing actors, including all layer intervals.
	var unique_orders: Dictionary={}
	# 呼び出し側で作ってある（Bridge.prepare_data）なら繰り返さない。
	for track in ([] if bundle.get("warmed",false) else store.tracks):
		for direction in track.orders:
			for order in direction:
				var key:=str(order)
				if not unique_orders.has(key):unique_orders[key]=true;plans.get_mesh(order)
	recipes=bundle.recipes
	track_ids=PackedInt32Array(bundle.handles)
	next_ids=PackedInt32Array(bundle.next_handles)
	phases.resize(recipes.size());next_phases.resize(recipes.size());speeds.resize(recipes.size())
	directions.resize(recipes.size());cursors.resize(recipes.size());next_cursors.resize(recipes.size())
	last_orders.resize(recipes.size())
	for i in range(recipes.size()):
		phases[i]=fposmod(i*0.61803398875,1.0)
		next_phases[i]=phases[i]
		speeds[i]=0.65+fposmod(i*0.143,0.7)
		directions[i]=i%8
		if previous.has(recipes[i].seed):
			phases[i]=previous[recipes[i].seed][0];speeds[i]=previous[recipes[i].seed][1];directions[i]=previous[recipes[i].seed][2]
		cursors[i]=0;next_cursors[i]=0
		last_orders[i]=PackedInt32Array()
		var reused=Spare.take_mesh()
		var node: MeshInstance2D=reused if reused!=null else MeshInstance2D.new()
		node.material=store.material_for(i);node.visible=true;node.modulate=Color.WHITE;node.mesh=null
		add_child(node)
		RenderingServer.canvas_item_set_custom_rect(node.get_canvas_item(),true,Rect2(-180,-420,360,520))
		meshes.append(node)
	blend=0
	generation+=1
	state_dirty=true
	layout()
	update_world(0)

func handle(index: int) -> Vector2i:
	return Vector2i(index,generation)

func valid_handle(value: Vector2i) -> bool:
	return value.y==generation and value.x>=0 and value.x<count

func layout() -> void:
	if store==null:return
	var area:=get_viewport_rect().size
	var width:=maxf(500,area.x-340)
	var columns:=maxi(1,floori(width/88))
	for i in range(count):
		if inspect:
			meshes[i].visible=i==selected
			meshes[i].position=Vector2(width*0.48,minf(area.y-100,610))
		else:
			meshes[i].visible=true
			meshes[i].position=Vector2(48+(i%columns)*88,175+(i/columns)*85)
		meshes[i].z_index=i
	state_dirty=true

static func locate(times: PackedFloat32Array, phase: float, cursor: int) -> int:
	var i:=clampi(cursor,0,times.size()-2)
	if phase < times[i]:
		var lo:=0;var hi:=times.size()-1
		while lo+1<hi:
			var mid: int=(lo+hi)/2
			if times[mid]<=phase:lo=mid
			else:hi=mid
		return mini(lo,times.size()-2)
	while i<times.size()-2 and times[i+1]<=phase:i+=1
	return i

func frame_state(track: Dictionary, phase: float, cursor: int) -> Vector4:
	var t: PackedFloat32Array=track.times
	var mix_value:=inverse_lerp(t[cursor],t[cursor+1],phase)
	return Vector4(track.base+cursor*128,track.base+(cursor+1)*128,clampf(mix_value,0,1),track.layer)

func update_world(delta: float, upload: bool=true) -> void:
	if store==null:return
	if paused and not state_dirty:return
	var started:=Time.get_ticks_usec()
	if not next_ids.is_empty() and not paused:blend=minf(1,blend+delta/0.2)
	for i in range(count):
		# 見えていない役者は計算しない（見えるようになったフレームで計算し直す）。
		if external_rows.has(i) or not meshes[i].visible:continue
		var track: Dictionary=store.tracks[track_ids[i]]
		if not paused:phases[i]=fposmod(phases[i]+delta*speeds[i]/track.duration,1.0)
		cursors[i]=locate(track.times,phases[i],cursors[i])
		store.set_state(i,0,frame_state(track,phases[i],cursors[i]))
		var visible_track: Dictionary=track
		var visible_cursor:=cursors[i]
		if not next_ids.is_empty():
			var next: Dictionary=store.tracks[next_ids[i]]
			if not paused:next_phases[i]=fposmod(next_phases[i]+delta*speeds[i]/next.duration,1.0)
			next_cursors[i]=locate(next.times,next_phases[i],next_cursors[i])
			store.set_state(i,1,frame_state(next,next_phases[i],next_cursors[i]))
			if blend>=0.5:visible_track=next;visible_cursor=next_cursors[i]
		var height: float=350.0 if inspect else 82.0
		# Existing B display_scale is absorbed into the fixed standing reference, never fitted per pose.
		var scale_value: float=height/2.45*recipes[i].height
		store.set_state(i,2,Vector4(blend,scale_value,deg_to_rad(directions[i]*45.0),pitch))
		store.set_state(i,3,Vector4(i,0,0,0))
		store.apply_face_track(i,next_ids[i] if blend>=0.5 and not next_ids.is_empty() else track_ids[i],next_phases[i] if blend>=0.5 and not next_ids.is_empty() else phases[i])
		var order: PackedInt32Array=visible_track.orders[directions[i]][visible_cursor]
		if head_only:order=PackedInt32Array([4])
		elif body_only:
			order=order.duplicate();order.remove_at(order.find(4))
		if order!=last_orders[i]:
			meshes[i].mesh=plans.get_mesh(order)
			last_orders[i]=order
	if upload:store.upload_state()
	if blend>=1:
		track_ids=next_ids;next_ids=PackedInt32Array()
		phases=next_phases.duplicate();cursors=next_cursors.duplicate();blend=0
	state_dirty=false
	cpu_ms=(Time.get_ticks_usec()-started)/1000.0

func seek(phase: float) -> void:
	for i in range(count):phases[i]=clampf(phase,0,0.999999);next_phases[i]=phases[i]
	state_dirty=true
	update_world(0)

func set_speed(value: float) -> Dictionary:
	if not is_finite(value) or absf(value)>1.9:return {"ok":false,"code":"SPEED_OUT_OF_VALIDATED_RANGE"}
	speeds.fill(value)
	return {"ok":true}
