extends RefCounted
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
## 体型の設定（43体ぶんの JSON）は一度だけ読んで使い回す。読み込み直す（prepare）ときに reset で捨てる。
static var shared_catalog=null
static func reset() -> void:
	shared_catalog=null
static func make(index: int,seed_value: int=1) -> Dictionary:
	if shared_catalog==null:shared_catalog=Catalog.new()
	var catalog=shared_catalog
	var recipe: Dictionary=catalog.recipe(seed_value)
	for key in recipe.modules:recipe.modules[key]=index
	for key in recipe.face:recipe.face[key]=index
	recipe.profile=catalog.configs[index].profile.duplicate(true)
	recipe.height=1.0;recipe.thickness=1.0;recipe.head_scale=0.9
	return recipe

