extends RefCounted
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
const MODULES=["head","upper_body","lower_body","arms","legs"]
const VIEWS=["front","front_three_quarter_left","left","back_three_quarter_left","back"]
const FILES=[1,2,3,5,4]
var root:String
var catalog:=Catalog.new()
var index:Dictionary={}
var error:=""
var image_cache:Dictionary={}

func _init(location:String="res://character_assets") -> void:
	root=ProjectSettings.globalize_path(location)

func path(relative:String)->String:
	if relative.is_absolute_path() or relative.contains("..") or relative.contains(":"):return ""
	return root.path_join(relative)

static func identifier(prefix:String)->String:
	return prefix+"_"+Crypto.new().generate_random_bytes(10).hex_encode()

func read(relative:String)->Dictionary:
	var p:=path(relative)
	if p.is_empty() or not FileAccess.file_exists(p):return {}
	var value=JSON.parse_string(FileAccess.get_file_as_string(p))
	if not value is Dictionary:return {}
	return value

func write(relative:String,value:Dictionary)->bool:
	var p:=path(relative)
	if p.is_empty():error="保存先が管理フォルダの外です";return false
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var temp:=p+".tmp"
	var f:=FileAccess.open(temp,FileAccess.WRITE)
	if f==null:error="書き込みできません: "+p;return false
	f.store_string(JSON.stringify(value,"\t"));f.close()
	var prior:=p+".previous"
	if FileAccess.file_exists(p):
		if FileAccess.file_exists(prior):DirAccess.remove_absolute(prior)
		if DirAccess.rename_absolute(p,prior)!=OK:error="更新前のファイルを保持できません";return false
	if DirAccess.rename_absolute(temp,p)!=OK:
		if FileAccess.file_exists(prior):DirAccess.rename_absolute(prior,p)
		error="保存の確定に失敗しました";return false
	return true

func initialize()->bool:
	for p in ["library/sources","library/materials","library/fits","library/prototypes","library/recipes","library/face_presets","drafts","previews","exports","backups","inbox"]:DirAccess.make_dir_recursive_absolute(path(p))
	if FileAccess.file_exists(path("library/index.json")):
		index=read("library/index.json")
		if index.get("schema_version")!=1:error="ライブラリの版が未対応です";return false
		return true
	index={"schema_version":1,"id":identifier("library"),"revision":1,"fits":[],"prototypes":[],"recipes":[]}
	for i in range(catalog.configs.size()):
		var config:Dictionary=catalog.configs[i]
		var proto:={"schema_version":1,"id":identifier("prototype"),"revision":1,"legacy":i,"name":["冒険者型","ゴブリン型","無地下地型"][i],"profile":config.profile.duplicate(true),"surface":config.surface.duplicate(true)}
		if not write("library/prototypes/"+proto.id+"/prototype.json",proto):return false
		index.prototypes.append(proto)
		var fit:=new_fit(i,config.get("display_name","素材"))
		fit.id=identifier("fit");fit.revision=1
		for module in MODULES:
			var source_module:String="heads" if module=="head" else module
			for vi in range(5):
				var imported:=import_source(ProjectSettings.globalize_path(config.sources[source_module]+"/single-%d.png"%FILES[vi]))
				if imported.is_empty():return false
				fit.modules[module].sources[VIEWS[vi]]=imported.id
		if not write_fit_files(fit):return false
		index.fits.append(summary(fit))
	return write("library/index.json",index)

func new_fit(prototype_index:int,display_name:String)->Dictionary:
	var modules:Dictionary={}
	for module in MODULES:modules[module]={"legacy":prototype_index,"sources":{},"slots":{}}
	return {"schema_version":1,"id":identifier("fit"),"revision":0,"material_id":identifier("material"),"kind":"body_modules","name":display_name,"prototype":index.prototypes[prototype_index].duplicate(true),"modules":modules,"heads":{},"height":1.0,"thickness":1.0,"head_scale":1.0,"face_selection":{},"presets":{},"face_keys":[]}

func summary(fit:Dictionary)->Dictionary:
	return {"id":fit.id,"revision":fit.revision,"name":fit.name,"prototype_id":fit.prototype.id,"path":"library/fits/"+fit.prototype.id+"/"+fit.id+"/fit.json"}

func load_fit(id:String,revision:int=-1)->Dictionary:
	for entry in index.fits:
		if entry.id==id:
			var p:String="library/fits/"+entry.prototype_id+"/"+entry.id+"/revisions/%d.json"%(int(entry.revision) if revision<0 else revision)
			var value:=read(p)
			if value.get("schema_version")!=1:error="適合データの版が未対応です";return {}
			return value
	return {}

func write_fit_files(fit:Dictionary)->bool:
	var base:String="library/fits/"+fit.prototype.id+"/"+fit.id
	if not write(base+"/revisions/%d.json"%fit.revision,fit):return false
	if not write(base+"/fit.json",fit):return false
	return write("library/materials/"+fit.material_id+"/material.json",{"schema_version":1,"id":fit.material_id,"revision":fit.revision,"name":fit.name,"kind":"body_modules","modules":fit.modules})

func register_fit(fit:Dictionary)->Dictionary:
	var connection:=preload("res://mini/layered2d/data/neck_attachment.gd").resolve(fit)
	if not connection.ok:return connection
	var disk:=read("library/index.json")
	if disk.get("revision",-1)!=index.revision:return {"ok":false,"error":"別のツールが更新しました。下書きを保存して開き直してください。"}
	var current:=load_fit(fit.id)
	if not current.is_empty() and int(current.revision)!=int(fit.revision):return {"ok":false,"error":"登録版が変わりました。別の下書きへ保存してください。"}
	var next:=fit.duplicate(true);next.revision=int(fit.revision)+1
	if not write_fit_files(next):return {"ok":false,"error":error}
	if not write("backups/"+identifier("transaction")+"/index.json",index):return {"ok":false,"error":error}
	var updated:=index.duplicate(true);updated.revision+=1
	var found:=false
	for i in range(updated.fits.size()):
		if updated.fits[i].id==next.id:updated.fits[i]=summary(next);found=true
	if not found:updated.fits.append(summary(next))
	if not write("library/index.json",updated):return {"ok":false,"error":error}
	index=updated
	return {"ok":true,"fit":next}

func import_source(file:String)->Dictionary:
	var image:=Image.load_from_file(file)
	if image==null or image.is_empty():error="画像を読めません: "+file;return {}
	if image.get_width()>8192 or image.get_height()>8192:error="画像は8192px以下で読み込んでください";return {}
	var hash_value:=FileAccess.get_sha256(file)
	var id:="source_"+hash_value
	var relative:="library/sources/"+id+"/original."+file.get_extension().to_lower()
	if not FileAccess.file_exists(path(relative)):
		DirAccess.make_dir_recursive_absolute(path(relative).get_base_dir())
		if DirAccess.copy_absolute(file,path(relative))!=OK:error="元画像をコピーできません";return {}
	var source:={"schema_version":1,"id":id,"revision":1,"file":relative,"original_name":file.get_file(),"width":image.get_width(),"height":image.get_height(),"sha256":hash_value}
	if not write("library/sources/"+id+"/source.json",source):return {}
	return source

func source_image(id:String)->Image:
	if image_cache.has(id):return image_cache[id]
	var info:=read("library/sources/"+id+"/source.json")
	if info.is_empty():error="元画像が見つかりません: "+id;return null
	var image:=Image.load_from_file(path(info.file))
	if image!=null:image_cache[id]=image
	return image

func save_draft(fit:Dictionary)->bool:
	return write("drafts/"+fit.id+"/draft.json",fit)

func fork_fit(fit:Dictionary,prototype_index:int)->Dictionary:
	var copy:=fit.duplicate(true);copy.id=identifier("fit");copy.material_id=identifier("material");copy.revision=0
	copy.prototype=index.prototypes[prototype_index].duplicate(true);copy.name=fit.name+" の複製"
	return copy
