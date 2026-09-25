extends SceneTree
const Importer=preload("res://mini/layered2d/import/asset_importer.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/characters/neutral_base/source_template.json"))
	var result:=Importer.import_asset(Importer.freeze(config),"res://mini/layered2d/data/characters/neutral_base")
	print(result)
	quit(0 if result.ok else 1)
