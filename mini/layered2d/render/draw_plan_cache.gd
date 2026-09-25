extends RefCounted
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
var meshes: Dictionary = {}
## 部位ごとの格子（頂点・UV・部位番号・添字）は形が決まっているので、一度だけ作って使い回す。
static var slot_blocks: Dictionary = {}
## 添字は前に積んだ頂点の数だけずらす。ずらし量ごとに作った添字も使い回す（重ね順が違っても同じずらし量はよく出る）。
static var shifted: Dictionary = {}

static func block(slot: int) -> Dictionary:
	if slot_blocks.has(slot): return slot_blocks[slot]
	# 胸と骨盤（尻）は領域の変形（揺れ・潰れ）があるので細かくする。粗いと輪郭が尖って見える。
	var n := 11 if slot==2 else (9 if slot in [0,21,22] else (7 if slot in [4,25,26] else (5 if slot in [8,16,27] else 3)))
	var vertices := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()
	for y in range(n):
		for x in range(n):
			var point := Vector2(x,y)/float(n-1)
			if slot==0:point.y*=0.5
			if slot in [21,22]:point=Vector2(point.x*0.5+(0.5 if slot==22 else 0.0),0.5+point.y*0.5)
			vertices.append(point)
			custom.append_array(PackedFloat32Array([slot,y*n+x,0,0]))
	for y in range(n-1):
		for x in range(n-1):
			var a := y*n+x
			indices.append_array(PackedInt32Array([a,a+1,a+n+1,a,a+n+1,a+n]))
	var result := {"vertices":vertices,"custom":custom,"indices":indices}
	slot_blocks[slot] = result
	return result

static func shifted_indices(slot: int, offset: int) -> PackedInt32Array:
	var key := slot*1000000+offset
	if shifted.has(key): return shifted[key]
	var source: PackedInt32Array = block(slot).indices
	var out := PackedInt32Array()
	out.resize(source.size())
	for i in range(source.size()): out[i] = source[i]+offset
	shifted[key] = out
	return out

func get_mesh(order: PackedInt32Array) -> ArrayMesh:
	var key := str(order)
	if meshes.has(key): return meshes[key]
	var vertices := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()
	for slot in order:
		var b: Dictionary = block(slot)
		var start := vertices.size()
		vertices.append_array(b.vertices)
		custom.append_array(b.custom)
		indices.append_array(shifted_indices(slot,start))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = vertices
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	meshes[key] = mesh
	return mesh
