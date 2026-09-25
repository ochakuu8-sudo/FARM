extends RefCounted
const Repo=preload("res://mini/layered2d/authoring/asset_manager/library_repository.gd")
const Importer=preload("res://mini/layered2d/import/asset_importer.gd")
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
const FaceComposer=preload("res://mini/layered2d/prepare/face_composer.gd")
const BodySets=preload("res://mini/layered2d/data/body_sets.gd")
var repo
var error:=""
var registrations:Dictionary={}
var animation_templates:Dictionary={}
var template_atlases:Dictionary={}
var module_templates:Dictionary={}

func _init(repository)->void:repo=repository

func config(fit:Dictionary,module:String)->Dictionary:
	var result:Dictionary=repo.catalog.configs[int(fit.modules[module].legacy)]
	if module=="upper_body" and fit.modules.upper_body.has("collar_cut"):
		result=result.duplicate(true);result.collar_cut=fit.modules.upper_body.collar_cut.duplicate(true)
	if module=="head" and fit.modules.head.has("neck_cut"):
		result=result.duplicate(true)
		result.neck_exclusions=fit.modules.head.neck_cut
		result.separate_neck=true
		if fit.modules.head.has("neck_skin"):result.neck_skin=fit.modules.head.neck_skin.duplicate()
	if fit.has("import_config"):
		result=result.duplicate(true)
		for key in ["neck_sample","joint_patches","seam_fade","seam_fade_by_view","seam_fill"]:
			if fit.import_config.has(key):result[key]=fit.import_config[key].duplicate(true)
	if fit.get("shape_cut_policy",{}).get(module,"")=="source_outline":
		result=result.duplicate(true);result.erase("rounded_joins")
	# 継ぎ目の丸め（骨盤の下端を楕円で落とす）は元の輪郭方針でも明示すれば使う。既存の冒険者と同じ作り。
	if fit.get("import_config",{}).has("rounded_joins"):
		result=result.duplicate(true);result.rounded_joins=fit.import_config.rounded_joins.duplicate(true)
	return result

func registration(fit:Dictionary,module:String)->Dictionary:
	var c:=config(fit,module)
	if not registrations.has(c.layered2d_registration):registrations[c.layered2d_registration]=JSON.parse_string(FileAccess.get_file_as_string(c.layered2d_registration))
	var result:Dictionary=registrations[c.layered2d_registration]
	if fit.has("registration_overrides"):
		result=result.duplicate(true)
		for key in fit.registration_overrides:result.references[key]=fit.registration_overrides[key].duplicate(true)
	return result

# These are the same prepared image tiles consumed by ResourceStore, not a
# bounding box or a generic join mask. Cache them independently of input edits.
func animation_template(fit:Dictionary,module:String,group:String,view:int)->Image:
	var c:=config(fit,module)
	var guide:String=fit.get("shape_guides",{}).get(module,{}).get(group,{}).get(str(view),"")
	if not guide.is_empty():
		if not animation_templates.has(guide):animation_templates[guide]=Image.load_from_file(guide)
		return animation_templates[guide]
	var key:String=c.atlas_path+"/"+group+"/"+str(view)
	if not animation_templates.has(key):
		if not template_atlases.has(c.atlas_path):template_atlases[c.atlas_path]=Image.load_from_file(ProjectSettings.globalize_path(c.atlas_path))
		var atlas:Image=template_atlases[c.atlas_path]
		animation_templates[key]=atlas.get_region(Rect2i(view*256+8,int(c.surface[group].row)*256+8,240,240))
	return animation_templates[key]

func module_animation_template(fit:Dictionary,module:String,view:int)->Dictionary:
	var c:=config(fit,module)
	var source_module:String="heads" if module=="head" else module
	var source_index:int=Repo.FILES[view]-1
	var entry:=slot(fit,module,Repo.VIEWS[view])
	var key:=Catalog.fingerprint([c.atlas_path,module,view,entry.cuts,fit.get("shape_guides",{}).get(module,{}),fit.get("registration_overrides",{})])
	if module_templates.has(key):return module_templates[key]
	var definition:=registration(fit,module).duplicate(true)
	definition["cuts_by_view"]={str(source_index):entry.cuts}
	var ref:Array=definition.references[source_module][source_index].canvas
	var canvas:=Vector2i(ref[0],ref[1])
	var whole:=Image.create(canvas.x,canvas.y,false,Image.FORMAT_RGBA8)
	var pieces:Array=[];var groups:Array=[]
	for i in range(Catalog.GROUPS.size()):
		var group:String=Catalog.GROUPS[i]
		if Catalog.MODULES[i]!=module or groups.has(group):continue
		groups.append(group)
		# Neck is extracted from front art only; it is not a region of side/back art.
		if group=="neck":continue # Sampled from head art, not the torso input image.
		var part:=animation_template(fit,module,group,view)
		var rect:=Importer.part_source_rect(c,definition,source_module,group,view,canvas)
		var patch:Image=part.duplicate();patch.resize(rect.size.x,rect.size.y,Image.INTERPOLATE_BILINEAR)
		for y in range(rect.size.y):
			for x in range(rect.size.x):
				var point:=rect.position+Vector2i(x,y)
				if not Rect2i(Vector2i.ZERO,canvas).has_point(point):continue
				var alpha:=maxf(whole.get_pixelv(point).a,patch.get_pixel(x,y).a)
				whole.set_pixelv(point,Color(1,1,1,alpha))
		var bitmap:=BitMap.new();bitmap.create_from_image_alpha(part,.1)
		pieces.append({"group":group,"rect":rect,"polygons":bitmap.opaque_to_polygons(Rect2i(0,0,240,240),.7)})
	var divisions:Array=[]
	for piece in pieces:
		var segments:=PackedVector2Array()
		for polygon in piece.polygons:
			for i in range(polygon.size()):
				var start:Vector2=Vector2(piece.rect.position)+polygon[i]/240.0*Vector2(piece.rect.size)
				var end:Vector2=Vector2(piece.rect.position)+polygon[(i+1)%polygon.size()]/240.0*Vector2(piece.rect.size)
				var distance:float=start.distance_to(end)
				if distance<.01:continue
				var normal:Vector2=(end-start).orthogonal().normalized()*1.5
				var steps:int=maxi(1,ceili(distance))
				for step in range(steps):
					var a:Vector2=start.lerp(end,float(step)/steps);var b:Vector2=start.lerp(end,float(step+1)/steps)
					var center:Vector2=(a+b)*.5
					# Only internal borders: do not draw a second outline on the exterior.
					if template_alpha(whole,center+normal)>.1 and template_alpha(whole,center-normal)>.1:
						segments.append(a/Vector2(canvas));segments.append(b/Vector2(canvas))
		divisions.append({"group":piece.group,"segments":segments})
	var result:={"image":whole,"divisions":divisions}
	module_templates[key]=result
	return result

static func template_alpha(image:Image,point:Vector2)->float:
	var pixel:=Vector2i(point.floor())
	return image.get_pixelv(pixel).a if Rect2i(Vector2i.ZERO,image.get_size()).has_point(pixel) else 0.0

static func constrain_to_template(part:Image,reference:Image)->void:
	# Do not square the soft joint edge: the prepared reference already includes
	# its fade. Transparent areas of the replacement may still stay transparent.
	for y in range(part.get_height()):
		for x in range(part.get_width()):
			var pixel:=part.get_pixel(x,y)
			pixel.a=minf(pixel.a,reference.get_pixel(x,y).a)
			part.set_pixel(x,y,pixel)

static func defaults(source_id:String,image:Image)->Dictionary:
	return {"source_id":source_id,"source_rect_px":[0,0,image.get_width(),image.get_height()],"transform":[0.0,0.0,1.0,1.0,0.0],"cuts":{},"erase":[],"flip":false}

static func fit_reference(entry:Dictionary,image:Image,reference:Dictionary)->void:
	var source:Array=entry.source_rect_px
	var rect:=Rect2i(source[0],source[1],source[2],source[3]).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if rect.size.x<=0 or rect.size.y<=0:return
	var used:=image.get_region(rect).get_used_rect()
	if used.size.x<=0 or used.size.y<=0:return
	entry.source_rect_px=[rect.position.x+used.position.x,rect.position.y+used.position.y,used.size.x,used.size.y]
	var r:Array=reference.rect;var canvas:Array=reference.canvas
	var scale_value:=minf(float(r[2])/used.size.x,float(r[3])/used.size.y)
	entry.transform=[(r[0]+r[2]*.5)/canvas[0]-.5,(r[1]+r[3]*.5)/canvas[1]-.5,used.size.x*scale_value/canvas[0],used.size.y*scale_value/canvas[1],0]

func slot(fit:Dictionary,module:String,view:String)->Dictionary:
	if fit.modules[module].slots.has(view):return fit.modules[module].slots[view]
	var source_id:String=fit.modules[module].sources.get(view,"")
	if source_id.is_empty():
		var source_module:String="heads" if module=="head" else module
		var file:String=config(fit,module).sources[source_module]+"/single-%d.png"%Repo.FILES[Repo.VIEWS.find(view)]
		var imported:Dictionary=repo.import_source(ProjectSettings.globalize_path(file))
		if imported.is_empty():return {}
		source_id=imported.id
	var image:Image=repo.source_image(source_id)
	return defaults(source_id,image) if image!=null else {}

static func transformed(image:Image,entry:Dictionary,canvas:Vector2i)->Image:
	var r:Array=entry.source_rect_px
	var rect:=Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if rect.size.x<=0 or rect.size.y<=0:return null
	var patch:=image.get_region(rect);patch.convert(Image.FORMAT_RGBA8)
	if entry.get("flip",false):patch.flip_x()
	var t:Array=entry.get("transform",[0,0,1,1,0])
	var out:=Image.create(canvas.x,canvas.y,false,Image.FORMAT_RGBA8)
	if absf(t[4])<0.0001:
		var size:=Vector2i(maxi(1,roundi(canvas.x*t[2])),maxi(1,roundi(canvas.y*t[3])))
		patch.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
		out.blit_rect(patch,Rect2i(Vector2i.ZERO,size),Vector2i((Vector2(canvas)-Vector2(size))*.5+Vector2(t[0]*canvas.x,t[1]*canvas.y)))
	else:
		var transform:=Transform2D(deg_to_rad(t[4]),Vector2(t[2],t[3]),0,Vector2(canvas)*.5+Vector2(t[0]*canvas.x,t[1]*canvas.y))
		var inverse:=transform.affine_inverse()
		for y in range(canvas.y):
			for x in range(canvas.x):
				var uv:=(inverse*Vector2(x+.5,y+.5))/Vector2(canvas)+Vector2(.5,.5)
				if uv.x>=0 and uv.y>=0 and uv.x<1 and uv.y<1:out.set_pixel(x,y,patch.get_pixel(mini(patch.get_width()-1,int(uv.x*patch.get_width())),mini(patch.get_height()-1,int(uv.y*patch.get_height()))))
	for stroke in entry.get("erase",[]):
		var center:=Vector2(stroke[0]*canvas.x,stroke[1]*canvas.y);var radius:float=stroke[2]*canvas.x
		for y in range(maxi(0,int(center.y-radius)),mini(canvas.y,ceili(center.y+radius))):
			for x in range(maxi(0,int(center.x-radius)),mini(canvas.x,ceili(center.x+radius))):
				if Vector2(x,y).distance_to(center)<radius:out.set_pixel(x,y,Color.TRANSPARENT)
	if entry.has("chroma"):
		var color:=Color(entry.chroma[0],entry.chroma[1],entry.chroma[2]);var tolerance:float=entry.get("chroma_tolerance",.12)
		for y in range(canvas.y):
			for x in range(canvas.x):
				var c:=out.get_pixel(x,y)
				if Vector3(c.r,c.g,c.b).distance_to(Vector3(color.r,color.g,color.b))<tolerance:out.set_pixel(x,y,Color.TRANSPARENT)
	return out

func canvas_image(fit:Dictionary,module:String,view:String)->Image:
	var entry:=slot(fit,module,view)
	if entry.is_empty():error=repo.error;return null
	var image:Image=repo.source_image(entry.source_id)
	if image==null:error=repo.error;return null
	var source_module:String="heads" if module=="head" else module
	var ref:Array=registration(fit,module).references[source_module][Repo.FILES[Repo.VIEWS.find(view)]-1].canvas
	return transformed(image,entry,Vector2i(ref[0],ref[1]))

func head_key(fit:Dictionary)->String:
	# Material identity is separate from prototype; editing the head invalidates its old face target.
	var head:Dictionary=fit.modules.head.duplicate(true);head.erase("borrowed_from");head.erase("sockets");head.erase("neck_skin")
	return Catalog.fingerprint(JSON.parse_string(JSON.stringify(head)))

func face_state(fit:Dictionary)->Dictionary:
	return fit.heads.get(head_key(fit),{"slots":{},"presets":{},"keys":[]})

func base_face(fit:Dictionary)->Dictionary:
	return config(fit,"head").face.duplicate(true)

func build_face(fit:Dictionary)->Dictionary:
	var face:=base_face(fit)
	var state:=face_state(fit)
	if face.get("mode","")=="baked":return {"ok":true,"face":face}
	if not fit.modules.head.slots.is_empty() and not state.has("underlay"):
		return {"ok":false,"error":"変更した頭には顔の下地が必要です。顔パーツ画面で登録してください。"}
	if state.has("underlay"):face.atlas_path=repo.path(state.underlay);face.blank_row=0;face.erase("mix_mask_row")
	for s in face.registered.slots:
		s.variants=s.get("transfer_variants",s.variants).duplicate(true)
		if not state.slots.has(s.id):continue
		var edit:Dictionary=state.slots[s.id]
		for name in edit.get("variants",{}):
			var variants:Dictionary={}
			for view in edit.variants[name]:
				var entry:Dictionary=edit.variants[name][view].duplicate(true)
				# Translation and size belong to the target face frame, not to a clipped patch.
				entry.transform=[0,0,1,1,edit.get("transform",[0,0,1,1,0])[4]];entry.flip=edit.get("flip",false)
				var image:Image=repo.source_image(entry.source_id)
				if image==null:return {"ok":false,"error":repo.error}
				var built:=transformed(image,entry,Vector2i(128,128))
				if built==null:return {"ok":false,"error":"顔パーツの切出し範囲が画像の外です"}
				var relative:="previews/face_"+Catalog.fingerprint(entry)+".png"
				if not FileAccess.file_exists(repo.path(relative)) and built.save_png(repo.path(relative))!=OK:return {"ok":false,"error":"顔パーツ画像を保存できません"}
				variants[view]={"atlas_path":repo.path(relative),"column":0,"row":0,"rect":[0,0,128,128]}
			if not variants.has("front"):return {"ok":false,"error":s.id+" / "+name+" の正面画像が必要です"}
			s.variants[name]=variants
		s.erase("transfer_variants");s.paint="over"
		if edit.has("frames"):
			for view in edit.frames:face.registered.registration[view][s.id]=edit.frames[view]
		var transform:Array=edit.get("transform",[0,0,1,1,0])
		for view in ["front","quarter","side"]:
			var rect=face.registered.registration[view][s.id]
			if rect==null:continue
			var w:float=rect[2]*transform[2];var h:float=rect[3]*transform[3]
			var next:Array=[rect[0]+(rect[2]-w)*.5+transform[0],rect[1]+(rect[3]-h)*.5+transform[1],w,h]
			if next[0]<0 or next[1]<0 or next[0]+w>1 or next[1]+h>1:return {"ok":false,"error":s.id+" / "+view+" の配置枠が頭の外です"}
			face.registered.registration[view][s.id]=next
	face.registered.presets.merge(state.get("presets",{}),true)
	return {"ok":true,"face":face}

func recipe(fit:Dictionary)->Dictionary:
	var connection:=preload("res://mini/layered2d/data/neck_attachment.gd").resolve(fit)
	if not connection.ok:return connection
	var r:Dictionary=repo.catalog.recipe(0)
	r.prototype_index=int(fit.prototype.legacy);r.profile=fit.prototype.profile.duplicate(true)
	r.height=fit.height;r.thickness=fit.thickness;r.head_scale=fit.head_scale;r.face={};r.asset_modules={}
	r.registration=fit.get("part_registration",{}).duplicate(true)
	# 画像の下への延長（切り出し範囲を伸ばした分）。描画側で大きさと位置を補正する。
	if fit.get("import_config",{}).has("part_extension"):r.part_extension=fit.import_config.part_extension.duplicate(true)
	if not connection.attachment.is_empty():
		r.neck_attachment=connection.attachment
		# Position is constrained by the two art sockets; a world offset is not a fit.
		r.registration.erase("head")
	for module in Repo.MODULES:r.modules[module]=int(fit.modules[module].legacy)
	var head_edited:bool=not fit.modules.head.slots.is_empty()
	var face_result:=build_face(fit)
	if not face_result.ok:
		if head_edited and face_state(fit).slots.is_empty() and str(face_result.error).begins_with("変更した頭"):
			face_result={"ok":true,"face":{"mode":"baked","atlas_path":config(fit,"head").atlas_path,"registered":{"slots":[],"presets":{"neutral":{}}}}}
		else:return face_result
	if not face_state(fit).slots.is_empty() or face_state(fit).has("underlay") or head_edited:r.asset_face=face_result.face
	r.expression=fit.get("face_selection",{}).duplicate(true)
	if fit.has("body_sets"):
		r.body_sets=fit.body_sets.duplicate(true)
		var resolved:=BodySets.apply(r,repo.catalog.configs)
		if not resolved.ok:return resolved
		r=resolved.recipe
	if face_result.face.get("mode","")=="baked":r.expression={}
	for module in Repo.MODULES:
		if fit.modules[module].slots.is_empty():continue
		var built:=build_module(fit,module)
		if not built.ok:return built
		r.asset_modules[module]={"groups":built.groups}
		if built.has("head_atlas"):r.asset_head_atlas=built.head_atlas
	var materials:=apply_set_materials(fit,r,false)
	if not materials.ok:return materials
	if fit.get("baked_expression_head_key","")==head_key(fit) and r.get("asset_face",{}).get("mode")=="baked":
		r.asset_face.expression_atlases=fit.get("baked_expression_atlases",{}).duplicate(true)
		r.expression=fit.get("face_selection",{}).duplicate(true)
	return {"ok":true,"recipe":r}

# Untouched modules keep reference art. Once a module is edited, none of its
# missing directions may fall back to reference art. Game export stays separate.
func preview_recipe(fit:Dictionary)->Dictionary:
	var result:=recipe(fit)
	if not result.ok:return result
	var r:Dictionary=result.recipe
	var blank_path:String=repo.path("previews/empty_preview_part.png")
	if not FileAccess.file_exists(blank_path):
		var blank:=Image.create(256,256,false,Image.FORMAT_RGBA8)
		if blank.save_png(blank_path)!=OK:return {"ok":false,"error":"透明プレビュー画像を保存できません"}
	var head_paths:Dictionary={}
	for module in Repo.MODULES:
		if fit.modules[module].slots.is_empty():continue
		var groups:Dictionary=r.asset_modules.get(module,{}).get("groups",{}).duplicate(true)
		for group in config(fit,module).surface:
			if Catalog.MODULES[Catalog.GROUPS.find(group)]!=module:continue
			var paths:Dictionary=groups.get(group,{})
			for view in range(9):
				if not paths.has(str(view)):paths[str(view)]=blank_path
			groups[group]=paths
			if group=="head":head_paths=paths
		r.asset_modules[module]={"groups":groups}
	var materials:=apply_set_materials(fit,r,true)
	if not materials.ok:return materials
	if head_paths.is_empty():return {"ok":true,"recipe":r}
	# Head normally goes through a separate face composer. Build a transparent
	# atlas here too, so it cannot resurrect an original face or rear/top tile.
	var head_path:String=repo.path("previews/input_head_"+Catalog.fingerprint(head_paths)+".png")
	if not FileAccess.file_exists(head_path):
		var head:=Image.create(2560,256,false,Image.FORMAT_RGBA8)
		for view in range(9):
			var tile:=Image.load_from_file(head_paths[str(view)])
			if tile==null:return {"ok":false,"error":"プレビュー用の頭画像を読み込めません"}
			head.blit_rect(tile,Rect2i(0,0,256,256),Vector2i(view*256,0))
		if head.save_png(head_path)!=OK:return {"ok":false,"error":"プレビュー用の頭画像を保存できません"}
	r.asset_head_atlas=head_path
	var variants:Dictionary=r.get("asset_face",{}).get("expression_atlases",{})
	r.asset_face={"mode":"baked","atlas_path":head_path,"registered":{"slots":[],"presets":{"neutral":{}}},"expression_atlases":variants}
	r.face={}
	if variants.is_empty():r.expression={}
	return {"ok":true,"recipe":r}

func build_module(fit:Dictionary,module:String)->Dictionary:
	var c:=config(fit,module)
	var definition:=registration(fit,module).duplicate(true)
	var source_module:String="heads" if module=="head" else module
	var originals:Dictionary={source_module:[]}
	for i in range(5):originals[source_module].append(null)
	for view in Repo.VIEWS:
		var image:=canvas_image(fit,module,view)
		if image==null:return {"ok":false,"error":error}
		var source_index:int=Repo.FILES[Repo.VIEWS.find(view)]-1
		originals[source_module][source_index]=image
		var entry:=slot(fit,module,view)
		if not definition.has("cuts_by_view"):definition.cuts_by_view={}
		definition.cuts_by_view[str(source_index)]=entry.get("cuts",{}).duplicate(true)
	if module!="head":originals.heads=[canvas_image(fit,"head","front") if not fit.modules.head.slots.is_empty() else Image.load_from_file(ProjectSettings.globalize_path(c.sources.heads+"/single-1.png"))]
	var parts:Array=["animation_template_alpha_v3",fit.modules[module],definition,fit.get("import_config",{}),fit.get("shape_cut_policy",{}),fit.get("shape_guides",{}).get(module,{}),FileAccess.get_modified_time(c.atlas_path)]
	# 継ぎ目の塗り延ばし（seam_fill）の処理を変えたら作り直すよう、使うときだけ版を鍵に入れる（使わない fit の鍵は変えない）。
	if fit.get("import_config",{}).has("seam_fill"):parts.append(["seam_fill",Importer.SEAM_FILL_VERSION])
	var key:=Catalog.fingerprint(parts)
	var folder:String=repo.path("previews/module_"+key);DirAccess.make_dir_recursive_absolute(folder)
	var groups:Dictionary={}
	var head_atlas:Image=null
	if module=="head":head_atlas=Image.load_from_file(ProjectSettings.globalize_path(c.atlas_path)).get_region(Rect2i(0,0,2560,256))
	for group in c.surface:
		var group_module:String=Catalog.MODULES[Catalog.GROUPS.find(group)]
		if group_module!=module:continue
		groups[group]={}
		for view in range(9):
			var source_index:int=preload("res://mini/layered2d/data/source_views.gd").source(c,view)
			var source_view:String=preload("res://mini/layered2d/data/source_views.gd").STANDARD[source_index]
			if not fit.modules[module].slots.has("front" if group=="neck" else source_view):continue
			var p:String=folder+"/"+group+"_%d.png"%view
			if not FileAccess.file_exists(p):
				var part:Image=Importer.build_part(c,definition,originals,"heads" if group=="neck" else source_module,group,view)
				if part==null:return {"ok":false,"error":"切り出し範囲を確認してください: "+group}
				constrain_to_template(part,animation_template(fit,module,group,view))
				var tile:=Image.create(256,256,false,Image.FORMAT_RGBA8)
				tile.blit_rect(part,Rect2i(0,0,240,240),Vector2i(8,8))
				if tile.save_png(p)!=OK:return {"ok":false,"error":"加工画像を保存できません"}
			groups[group][str(view)]=p
			if group=="head":head_atlas.blit_rect(Image.load_from_file(p),Rect2i(0,0,256,256),Vector2i(view*256,0))
	var result:={"ok":true,"groups":groups}
	if head_atlas!=null:
		var p:String=folder+"/head.png"
		if head_atlas.save_png(p)!=OK:return {"ok":false,"error":"頭画像を保存できません"}
		result.head_atlas=p
	return result

func apply_set_materials(fit:Dictionary,r:Dictionary,inputs_only:bool)->Dictionary:
	for role in ["upper","lower"]:
		if not fit.get("set_materials",{}).has(role):continue
		var donor:Dictionary=fit.set_materials[role]
		var built:Dictionary={}
		for group in (BodySets.UPPER if role=="upper" else BodySets.LOWER):
			if group=="neck":continue # Skin material follows the selected head, dimensions follow the upper body.
			var module:String=Catalog.MODULES[Catalog.GROUPS.find(group)]
			if not r.has("part_sources"):r.part_sources={}
			r.part_sources[group]=int(donor.modules[module].legacy)
			if not r.asset_modules.has(module):r.asset_modules[module]={"groups":{}}
			r.asset_modules[module].groups.erase(group)
			if donor.modules[module].slots.is_empty():continue
			if not built.has(module):built[module]=build_module(donor,module)
			if not built[module].ok:return built[module]
			var paths:Dictionary=built[module].groups[group].duplicate(true)
			if inputs_only:
				var blank:String=repo.path("previews/empty_preview_part.png")
				for view in range(9):
					if not paths.has(str(view)):paths[str(view)]=blank
			r.asset_modules[module].groups[group]=paths
	return {"ok":true}

# Freeze a new garment outline explicitly. Moving the input image afterwards
# cannot move this guide; preview and export use the same prepared mask.
func freeze_shape_guide(fit:Dictionary,module:String)->Dictionary:
	if fit.modules[module].slots.is_empty():return {"ok":false,"error":"先に新しい画像を読み込み、位置を合わせてください"}
	var c:=config(fit,module).duplicate(true);c.erase("rounded_joins")
	var definition:=registration(fit,module).duplicate(true)
	var source_module:String="heads" if module=="head" else module
	var originals:Dictionary={source_module:[]};var guides:Dictionary={}
	for i in range(5):originals[source_module].append(null)
	for view in Repo.VIEWS:
		var source_index:int=Repo.FILES[Repo.VIEWS.find(view)]-1
		originals[source_module][source_index]=canvas_image(fit,module,view)
		if originals[source_module][source_index]==null:return {"ok":false,"error":error}
		if not definition.has("cuts_by_view"):definition.cuts_by_view={}
		definition.cuts_by_view[str(source_index)]=slot(fit,module,view).cuts
	if module!="head":originals.heads=[canvas_image(fit,"head","front") if not fit.modules.head.slots.is_empty() else Image.load_from_file(ProjectSettings.globalize_path(c.sources.heads+"/single-1.png"))]
	var folder:String=repo.path("library/shapes/"+Repo.identifier("guide"));DirAccess.make_dir_recursive_absolute(folder)
	for group in c.surface:
		if Catalog.MODULES[Catalog.GROUPS.find(group)]!=module:continue
		guides[group]={}
		for view in range(9):
			var part:Image=Importer.build_part(c,definition,originals,"heads" if group=="neck" else source_module,group,view)
			if part==null:return {"ok":false,"error":"切り出し範囲を確認してください"}
			var path:String=folder+"/"+group+"_%d.png"%view
			if part.save_png(path)!=OK:return {"ok":false,"error":"輪郭の保存に失敗しました"}
			guides[group][str(view)]=path
	if not fit.has("shape_guides"):fit.shape_guides={}
	fit.shape_guides[module]=guides
	if not fit.has("shape_cut_policy"):fit.shape_cut_policy={}
	fit.shape_cut_policy[module]="source_outline"
	return {"ok":true}
