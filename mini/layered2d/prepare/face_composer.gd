extends RefCounted
const Registered=preload("res://mini/projected2d/b_cutout/registered_face.gd")
const Views=preload("res://mini/layered2d/data/source_views.gd")
const Neck=preload("res://mini/layered2d/data/neck_attachment.gd")

static func donors(recipe:Dictionary)->Dictionary:
	var result:Dictionary={}
	for slot in ["eye_l","eye_r","brow_l","brow_r","mouth"]:result[slot]=int(recipe.face.get(slot,recipe.modules.head))
	return result

static func compose(recipe: Dictionary, configs: Array, images: Dictionary={}) -> Dictionary:
	var neck:=Neck.for_recipe(recipe)
	var config: Dictionary=configs[int(recipe.modules.head)].duplicate(true)
	if recipe.has("asset_face"):config.face=recipe.asset_face.duplicate(true)
	if recipe.has("asset_head_atlas"):config.atlas_path=recipe.asset_head_atlas
	var error:=Views.validate(config)
	if not error.is_empty():return {"ok":false,"code":error}
	var tile_views: Array=[0,1,2,3,4,8]
	var dependencies: Array=[]
	for item in configs:
		dependencies.append([item.face,FileAccess.get_modified_time(item.face.atlas_path),FileAccess.get_modified_time(item.atlas_path)])
		for slot in item.face.get("registered",{}).get("slots",[]):
			for variants in [slot.variants,slot.get("transfer_variants",{})]:
				for variant in variants.values():
					for art in variant.values():
						if art is Dictionary and art.has("atlas_path"):dependencies.append([art.atlas_path,FileAccess.get_modified_time(art.atlas_path)])
	var key:=preload("res://mini/layered2d/data/catalog.gd").fingerprint([4,tile_views,config.get("source_directions",[]),recipe.modules.head,donors(recipe),recipe.get("expression",{}),dependencies,recipe.get("asset_face",{}),recipe.get("asset_head_atlas","")])
	key+=preload("res://mini/layered2d/data/catalog.gd").fingerprint(neck.get("head_cut",[]))
	var cache_path:="user://layered2d/face_"+key+".png"
	if FileAccess.file_exists(cache_path):
		var cached:=Image.load_from_file(ProjectSettings.globalize_path(cache_path))
		if cached!=null and cached.get_size()==Vector2i(tile_views.size()*128,128):
			var saved: Dictionary={}
			for i in range(tile_views.size()):saved[tile_views[i]]=cached.get_region(Rect2i(i*128,0,128,128))
			return {"ok":true,"tiles":saved}
	if config.face.get("mode", "registered") == "baked":
		# 一枚絵の顔の表情差分。expression.baked=<名前> で頭画像ごと差し替える（expression_atlases に登録した名前）。
		# 旧来の {"eye_l":"closed","eye_r":"closed"} は "closed" と同じ。
		var atlases: Dictionary=config.face.get("expression_atlases",{})
		var wanted: String=str(recipe.get("expression",{}).get("baked",""))
		if wanted=="" and recipe.get("expression",{}).get("eye_l")=="closed":wanted="closed"
		if wanted!="" and atlases.has(wanted):config.atlas_path=atlases[wanted]
		var baked:=read_image(config.atlas_path,images)
		if baked==null:return {"ok":false,"code":"BODY_IMAGE_MISSING","path":config.atlas_path}
		var fixed: Dictionary={}
		for v in tile_views:
			fixed[v]=baked.get_region(Rect2i(v*256,0,256,256))
			Neck.cut_tile(fixed[v],neck.get("head_cut",[]),v)
			fixed[v].resize(128,128,Image.INTERPOLATE_LANCZOS)
		return {"ok":true,"tiles":fixed}
	var def: Dictionary=config.face.duplicate(true)
	var paths: Dictionary={def.atlas_path:true}
	for i in range(def.registered.slots.size()):
		if recipe.has("asset_face"):continue
		var id: String=def.registered.slots[i].id
		var donor: Dictionary=configs[int(recipe.face.get(id,recipe.modules.head))].face
		for slot in donor.registered.slots:
			if slot.id!=id:continue
			var imported: Dictionary=slot.duplicate(true)
			imported.variants=imported.get("transfer_variants",imported.variants).duplicate(true)
			imported.paint="over";imported.atlas_path=donor.atlas_path
			def.registered.slots[i]=imported;paths[donor.atlas_path]=true
	for slot in def.registered.slots:
		for variant in slot.variants.values():
			for art in variant.values():
				if art is Dictionary and art.has("atlas_path"):paths[art.atlas_path]=true
	var inputs: Dictionary={}
	for path in paths:
		var image:=read_image(path,images)
		if image==null:return {"ok":false,"code":"FACE_IMAGE_MISSING","path":path}
		image.convert(Image.FORMAT_RGBA8);inputs[path]=image
	var expression: Dictionary=recipe.get("expression",{})
	var face:=Registered.render_data(def,"neutral" if expression.is_empty() else "custom",expression,{})
	var underlay: Image=inputs[def.atlas_path].get_region(Rect2i(0,int(def.blank_row)*256,2560,256))
	var result:=Registered.compose(face,inputs,underlay)
	var art:=read_image(config.atlas_path,images)
	if art==null:return {"ok":false,"code":"BODY_IMAGE_MISSING","path":config.atlas_path}
	art.convert(Image.FORMAT_RGBA8)
	var tiles: Dictionary={}
	for v in [0,1,2,4]:tiles[v]=result.image.get_region(Rect2i(v*256,0,256,256))
	# Rear-quarter has no frontal eye/mouth overlay. Keep its dedicated authored head.
	tiles[3]=art.get_region(Rect2i(3*256,0,256,256))
	tiles[8]=art.get_region(Rect2i(8*256,0,256,256))
	for v in tiles:
		Neck.cut_tile(tiles[v],neck.get("head_cut",[]),v)
		tiles[v].resize(128,128,Image.INTERPOLATE_LANCZOS)
	var packed:=Image.create(tile_views.size()*128,128,false,Image.FORMAT_RGBA8)
	for i in range(tile_views.size()):packed.blit_rect(tiles[tile_views[i]],Rect2i(0,0,128,128),Vector2i(i*128,0))
	DirAccess.make_dir_recursive_absolute("user://layered2d")
	if packed.save_png(cache_path+".tmp")==OK:DirAccess.rename_absolute(cache_path+".tmp",cache_path)
	return {"ok":true,"tiles":tiles}

static func read_image(path: String, images: Dictionary) -> Image:
	if not images.has(path):images[path]=Image.load_from_file(ProjectSettings.globalize_path(path))
	return images[path]
