extends SceneTree
const Importer=preload("res://mini/layered2d/import/asset_importer.gd")
const Views=preload("res://mini/layered2d/data/source_views.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/catalog.json"))
	for i in range(2):
		var path:String=registry.templates[i]
		var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		config.source_directions=Views.STANDARD.duplicate()
		if config.head_landmarks.size()==4:config.head_landmarks.append(config.head_landmarks[3].duplicate())
		config.display_name="冒険者（5方向）" if i==0 else "ゴブリン（5方向）"
		config.notes=["Five authored directions for every module; single-5 is rear quarter left.","Opposite side is mirrored. Front expression registration remains unchanged."]
		var name:String="adventurer" if i==0 else "goblin"
		var output:String="res://mini/layered2d/output/five_view_migration/"+name
		var definition:=Importer.freeze(config)
		var result:=Importer.import_asset(definition,output)
		if not result.ok:push_error(str(result));quit(1);return
		var atlas:=Image.load_from_file(ProjectSettings.globalize_path(config.atlas_path))
		var new_atlas:=Image.load_from_file(ProjectSettings.globalize_path(result.atlas))
		# Migrate only rear-quarter columns. Preserve approved front/side/back art exactly.
		for v in [3,5]:atlas.blit_rect(new_atlas,Rect2i(v*256,0,256,3840),Vector2i(v*256,0))
		atlas.save_png(ProjectSettings.globalize_path(config.atlas_path))
		var registration:String="res://mini/layered2d/data/characters/"+name+"/registration.json"
		DirAccess.make_dir_recursive_absolute(registration.get_base_dir())
		config.layered2d_registration=registration;definition.config=config.duplicate(true)
		FileAccess.open(registration,FileAccess.WRITE).store_string(JSON.stringify(definition,"\t"))
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(config,"\t"))
		# The adventurer's canonical art template is also used by shared authoring tools.
		if i==0:
			var base_path:="res://mini/projected2d/b_cutout/template.json"
			var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base_path))
			for key in ["source_directions","head_landmarks","notes","layered2d_registration"]:base[key]=config[key]
			FileAccess.open(base_path,FileAccess.WRITE).store_string(JSON.stringify(base,"\t"))
		print("MIGRATED ",name," five sources; original eight atlas columns retained")
	quit()
