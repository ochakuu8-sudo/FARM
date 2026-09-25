extends Node
## 使い回す描画ノードの置き場（World の役者メッシュ、Bridge の2体場面）。
## GLES3 は捨てた描画ノードのシェーダーのインスタンス変数の枠を返さないので、捨てずにここへ預ける。
## 木（root）の中に置くので、終了時には木と一緒に解放され、「leaked at exit」が出ない。
const PATH:="res://mini/layered2d/runtime/spare_holder.gd"
static var instance: Node
var meshes: Array=[]
var pairs: Array=[]

## 置き場を用意する（木の組み立て中でないときに呼ぶ）。
static func ensure() -> Node:
	if instance!=null and is_instance_valid(instance):return instance
	var tree:=Engine.get_main_loop() as SceneTree
	if tree==null or tree.root==null:return null
	instance=load(PATH).new()
	instance.name="SpareDrawNodes"
	tree.root.add_child.call_deferred(instance)
	return instance

static func usable() -> bool:
	return instance!=null and is_instance_valid(instance) and not instance.is_queued_for_deletion()

## 預ける。預けられなければ false（呼び出し側はそのまま解放させる）。
static func park_mesh(node: Node) -> bool:
	if not usable() or not is_instance_valid(node):return false
	if node.get_parent()!=null:node.get_parent().remove_child(node)
	instance.add_child(node);node.visible=false
	instance.meshes.append(node)
	return true

static func park_pair(node: Node) -> bool:
	if not usable() or not is_instance_valid(node):return false
	if node.get_parent()!=null:node.get_parent().remove_child(node)
	instance.add_child(node);node.visible=false
	instance.pairs.append(node)
	return true

## 取り出す（無ければ null）。取り出したノードは親から外して返す。
static func take_mesh() -> Node:
	return take(instance.meshes) if usable() else null

static func take_pair() -> Node:
	return take(instance.pairs) if usable() else null

static func take(list: Array) -> Node:
	while not list.is_empty():
		var node: Node=list.pop_back()
		if is_instance_valid(node):
			instance.remove_child(node)
			return node
	return null

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:
		# 2体場面の効果の画像も終了時に手放す。
		preload("res://mini/layered2d/runtime/pair_group.gd").effect_textures.clear()
		if instance==self:instance=null
