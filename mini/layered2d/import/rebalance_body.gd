extends SceneTree
const Importer=preload("res://mini/layered2d/import/asset_importer.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/catalog.json"))
	# Migration of the three existing characters, not a generic new-character importer.
	for index in range(mini(3,registry.templates.size())):
		var path:String=registry.templates[index]
		var c:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		var backup:="res://old/body_balance_before/"+str(index)
		DirAccess.make_dir_recursive_absolute(backup)
		if not FileAccess.file_exists(backup+"/template.json"):
			FileAccess.open(backup+"/template.json",FileAccess.WRITE).store_string(JSON.stringify(c,"\t"))
			DirAccess.copy_absolute(c.atlas_path,backup+"/atlas.png")
		c.profile.merge({"torso":0.60,"hip_height":0.878,"thigh":0.35,"shin":0.33,"upper_arm":0.29,"forearm":0.27,"hip_width":0.17,"shoulder":0.29 if index==1 else 0.275},true)
		c.surface.chest.radii=[0.365 if index==1 else 0.325,0.265,0.255]
		c.surface.chest.offset=[0,0,0]
		c.surface.abdomen.radii=[0.27,0.062,0.19];c.surface.abdomen.offset=[0,0,0]
		c.surface.pelvis.radii=[0.31,0.155,0.195];c.surface.pelvis.offset=[0,-0.01,0]
		c.surface.elbow.radii=[0.105 if index==1 else 0.088,0.08,0.09]
		c.surface.knee.radii=[0.066,0.065,0.065]
		for group in ["upper_arm","forearm","thigh","shin"]:c.surface[group].scale[1]=1.0
		c.surface.thigh.scale=[0.66,1.0,0.70]
		c.surface.shin.scale=[0.77,1.0,0.80]
		c.joint_patches={"elbow":[0.30,0.22,0.40,0.065],"knee":[0.30,0.17,0.40,0.055]}
		c.seam_fade={"pelvis":[0.0,0.12],"thigh":[0.12,0.0]}
		c.rounded_joins={"pelvis":true}
		if index<2:
			c.slices.chest=[0,0.78]
			c.slices.pelvis=[0.23,0.78]
			c.slices.thigh=[0.08,0.37];c.slices.shin=[0.32,0.63]
		else:
			c.slices.pelvis=[0.1,0.68];c.slices.thigh=[0.07,0.43]
		var definition:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(c.layered2d_registration))
		definition.config=c.duplicate(true);definition.cuts=c.slices.duplicate(true)
		var previous:=Image.load_from_file(ProjectSettings.globalize_path(c.atlas_path))
		var output:="res://mini/layered2d/output/body_balance_import/"+str(index)
		var result:=Importer.import_asset(definition,output)
		if not result.ok:push_error(str(result));quit(1);return
		var atlas:=Image.load_from_file(ProjectSettings.globalize_path(result.atlas))
		# Body-only adjustment: approved head artwork and expressions retain their pixels.
		atlas.blit_rect(previous,Rect2i(0,0,2560,256),Vector2i.ZERO)
		atlas.save_png(ProjectSettings.globalize_path(c.atlas_path))
		FileAccess.open(c.layered2d_registration,FileAccess.WRITE).store_string(JSON.stringify(definition,"\t"))
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(c,"\t"))
		if index==0:
			var base_path:="res://mini/projected2d/b_cutout/template.json"
			var base:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base_path))
			for field in ["profile","surface","slices","joint_patches","seam_fade","rounded_joins"]:base[field]=c[field].duplicate(true)
			FileAccess.open(base_path,FileAccess.WRITE).store_string(JSON.stringify(base,"\t"))
		if index==2:FileAccess.open(path.get_base_dir()+"/source_template.json",FileAccess.WRITE).store_string(JSON.stringify(c,"\t"))
	print("Rebalanced all three body templates; original head pixels retained")
	quit()
