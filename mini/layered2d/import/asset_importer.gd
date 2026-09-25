extends RefCounted
## Legacy adapter with frozen registration. Reimport never infers scale from new alpha bounds.
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
const Views=preload("res://mini/layered2d/data/source_views.gd")

static func freeze(config: Dictionary) -> Dictionary:
	var result:={"version":1,"config":config.duplicate(true),"references":{},"cuts":config.slices.duplicate(true)}
	for module in config.sources:
		result.references[module]=[]
		for view in range(Views.names(config).size()):
			var image:=Image.load_from_file(ProjectSettings.globalize_path(config.sources[module]+"/single-%d.png"%(view+1)))
			var rect:=image.get_used_rect()
			result.references[module].append({"canvas":[image.get_width(),image.get_height()],"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
	return result

static func source_rect(size:Vector2i, reference:Dictionary, cut:Array=[0,1])->Rect2i:
	var scale_value:=Vector2(size)/Vector2(reference.canvas[0],reference.canvas[1])
	var r:Array=reference.rect
	var base:=Rect2(Vector2(r[0],r[1])*scale_value,Vector2(r[2],r[3])*scale_value)
	return Rect2i(roundi(base.position.x),floori(base.position.y+base.size.y*cut[0]),roundi(base.size.x),maxi(1,floori(base.size.y*(cut[1]-cut[0]))))

static func crop_source(image:Image, reference:Dictionary, cut:Array=[0,1])->Image:
	return image.get_region(source_rect(image.get_size(),reference,cut))

# Editor and import use exactly the same pixel boundaries, including joint patches.
static func part_source_rect(config:Dictionary, definition:Dictionary, module:String, group:String, view:int, size:Vector2i)->Rect2i:
	var source:int=0 if group=="neck" else Views.source(config,view)
	var reference:Dictionary=definition.references[module][source]
	var cut:Array=definition.get("cuts_by_view",{}).get(str(source),{}).get(group,definition.cuts.get(group,[0,1]))
	var rect:=source_rect(size,reference,cut)
	if config.get("joint_patches",{}).has(group) or group=="neck":
		var whole:=source_rect(size,reference)
		var patch:Array=config.get("neck_sample",[.43,.77,.045,.035]) if group=="neck" else config.joint_patches[group]
		if group=="neck":
			rect=Rect2i(whole.position+Vector2i(int(whole.size.x*patch[0]),int(whole.size.y*patch[1])),Vector2i(maxi(2,int(whole.size.x*patch[2])),maxi(2,int(whole.size.y*patch[3]))))
		else:
			rect=Rect2i(whole.position+Vector2i(roundi(whole.size.x*patch[0]),roundi(whole.size.y*patch[1])),Vector2i(maxi(2,roundi(whole.size.x*patch[2])),maxi(2,roundi(whole.size.y*patch[3]))))
	if group=="head" and view==8:
		rect=Rect2i(rect.position+Vector2i(int(rect.size.x*.13),int(rect.size.y*.08)),Vector2i(int(rect.size.x*.74),int(rect.size.y*.70)))
	return rect

static func import_asset(definition: Dictionary, output: String) -> Dictionary:
	if definition.get("version")!=1:return {"ok":false,"code":"IMPORT_VERSION"}
	var config: Dictionary=definition.config.duplicate(true)
	var direction_error:=Views.validate(config)
	if not direction_error.is_empty():return {"ok":false,"code":direction_error}
	var originals: Dictionary={}
	for module in config.sources:
		originals[module]=[]
		if definition.references.get(module,[]).size()!=Views.names(config).size():return {"ok":false,"code":"REFERENCE_DIRECTION_COUNT","module":module}
		for view in range(Views.names(config).size()):
			var path: String=config.sources[module]+"/single-%d.png"%(view+1)
			var image:=Image.load_from_file(ProjectSettings.globalize_path(path))
			if image==null:return {"ok":false,"code":"IMAGE_MISSING","path":path}
			originals[module].append(image)
	var atlas:=Image.create(2560,3840,false,Image.FORMAT_RGBA8)
	for view in range(10):
		var source: int=Views.source(config,view)
		for group in config.surface:
			var module: String="heads" if group in ["head","neck"] else ("upper_body" if group=="chest" else ("lower_body" if group in ["abdomen","pelvis"] else ("arms" if group in ["upper_arm","forearm","hand","elbow"] else "legs")))
			var part:=build_part(config,definition,originals,module,group,view)
			if part==null:return {"ok":false,"code":"CUT_RANGE","group":group}
			atlas.blit_rect(part,Rect2i(0,0,240,240),Vector2i(view*256+8,int(config.surface[group].row)*256+8))
	DirAccess.make_dir_recursive_absolute(output)
	var path:=output+"/atlas.png"
	if atlas.save_png(path)!=OK:return {"ok":false,"code":"WRITE_FAILED"}
	config.atlas_path=path;config.slices=definition.cuts.duplicate(true)
	config.layered2d_registration=output+"/registration.json"
	FileAccess.open(output+"/template.json",FileAccess.WRITE).store_string(JSON.stringify(config,"\t"))
	FileAccess.open(output+"/registration.json",FileAccess.WRITE).store_string(JSON.stringify(definition,"\t"))
	return {"ok":true,"template":output+"/template.json","atlas":path}

static func build_part(config: Dictionary, definition: Dictionary, originals: Dictionary, module: String, group: String, view: int) -> Image:
	if group=="neck" and config.has("neck_skin"):
		var skin:Array=config.neck_skin
		var solid:=Image.create(240,240,false,Image.FORMAT_RGBA8)
		solid.fill(Color(skin[0],skin[1],skin[2],1))
		return solid
	var source: int=Views.source(config,view)
	var image:Image=originals.heads[0] if group=="neck" else originals[module][source]
	var cut:Array=definition.get("cuts_by_view",{}).get(str(source),{}).get(group,definition.cuts.get(group,[0,1]))
	if cut.size()!=2 or cut[0]<0 or cut[1]>1 or cut[0]>=cut[1]:return null
	var part:=image.get_region(part_source_rect(config,definition,module,group,view,image.get_size()))
	if Views.mirrored(config,view):part.flip_x()
	part.convert(Image.FORMAT_RGBA8)
	# Same legacy placement contract; binding restores physical dimensions.
	part.resize(240,240,Image.INTERPOLATE_LANCZOS)
	apply_part_mask(part,config,group,view)
	return part

## 帯（上端から top、下端から bottom の割合）の中を、部位の地の色へ寄せる。端に近い半分は完全に地の色、
## そこから帯の内側の境へかけて元の絵に戻す。輪郭線ほどの暗い画素は2倍の強さで寄せる。透明度は変えない
## （形はそのまま。端のぼかしは seam_fade が行う）。
## 地の色は列ごと：帯の中の、その列の左右 16px の不透明な画素の明るさの中央値を、さらに横 ±10px でならしたもの。
## 部位の中で色が違う所（騎士の鎧と布など）も、その列の色で延ばす。
const SEAM_FILL_VERSION:=4
static func fill_seam(part:Image,top:float,bottom:float,strength:float)->void:
	var size:=part.get_size()
	for end in [["top",top],["bottom",bottom]]:
		var depth:int=int(float(end[1])*size.y)
		if depth<=0:continue
		var from_top:bool=end[0]=="top"
		# 帯の中そのものから取る（帯の下の膝当て・鎧の色が筋になって入らないように）。
		var rows:Array=[]
		for i in range(depth):rows.append(i if from_top else size.y-1-i)
		var columns:Array=[]
		for x in range(size.x):
			var samples:Array=[]
			for y in rows:
				var c:=part.get_pixel(x,y)
				if c.a>0.9:samples.append(c)
			columns.append(samples)
		var medians:Array=[]
		for x in range(size.x):
			var window:Array=[]
			for k in range(maxi(0,x-16),mini(size.x,x+17)):window.append_array(columns[k])
			if window.is_empty():medians.append(null);continue
			window.sort_custom(func(a,b):return a.get_luminance()<b.get_luminance())
			medians.append(window[window.size()/2])
		# 横にならして、列ごとの色の段を消す。
		var bases:Array=[]
		for x in range(size.x):
			var total:=Color(0,0,0,0);var count:=0
			for k in range(maxi(0,x-10),mini(size.x,x+11)):
				if medians[k]!=null:total+=medians[k];count+=1
			bases.append(total/float(count) if count>0 and medians[x]!=null else null)
		for i in range(depth):
			var y:int=i if from_top else size.y-1-i
			var t:float=float(i)/depth
			var weight:float=(1.0 if t<0.5 else 1.0-smoothstep(0.5,1.0,t))*strength
			for x in range(size.x):
				var c:=part.get_pixel(x,y)
				if c.a<=0.0 or bases[x]==null:continue
				var base:Color=bases[x]
				var w:float=weight*(2.0 if c.get_luminance()<base.get_luminance()*0.6 else 1.0)
				var mixed:=c.lerp(Color(base.r,base.g,base.b,c.a),clampf(w,0.0,1.0))
				mixed.a=c.a
				part.set_pixel(x,y,mixed)

## 上端の角を丸めて幅を絞る（taper）。1枚絵の腿は上端が腰の絵より広く、脚を振ると角が腰の輪郭の外へはみ出す。
## 行ごとに不透明な範囲 [左, 右] を見て、上端ほど両側を内へ削る（削る量 = 半幅×taper×(1−t)²、t は帯の中の深さ 0〜1）。
## 縁は 4px でぼかす。
static func taper_top(part:Image,depth_ratio:float,amount:float)->void:
	var size:=part.get_size()
	var depth:int=int(depth_ratio*size.y)
	for y in range(depth):
		var left:=-1;var right:=-1
		for x in range(size.x):
			if part.get_pixel(x,y).a>0.5:
				if left<0:left=x
				right=x
		if left<0:continue
		var t:float=float(y)/depth
		var inset:float=(right-left)*0.5*amount*pow(1.0-t,2.0)
		if inset<=0.5:continue
		for x in range(left,right+1):
			var edge:float=minf(float(x-left),float(right-x))
			var keep:float=clampf((edge-inset)/4.0+0.5,0.0,1.0)
			if keep>=1.0:continue
			var c:=part.get_pixel(x,y);c.a*=keep;part.set_pixel(x,y,c)

static func apply_part_mask(part:Image,config:Dictionary,group:String,view:int)->void:
	if group=="chest" and config.has("collar_cut"):
		var polygons:Array=config.collar_cut.duplicate(true)
		for polygon in polygons:
			for point in polygon:
				point[0]=(point[0]*256-8)/240;point[1]=(point[1]*256-8)/240
		preload("res://mini/layered2d/data/neck_attachment.gd").cut_tile(part,polygons,view)
	if group=="head" and view!=8 and config.has("neck_exclusions"):
		var source:int=[0,1,2,3,4,3,2,1][view]
		var polygon:=PackedVector2Array()
		for p in config.neck_exclusions[source]:polygon.append(Vector2((1.0-p[0]) if view in [5,6,7] else p[0],p[1])*240.0)
		for y in range(240 if polygon.size()>=3 else 0):
			for x in range(240):
				if Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),polygon):
					var c:=part.get_pixel(x,y);c.a=0;part.set_pixel(x,y,c)
	# 継ぎ目側の輪郭線・影を消して塗りを延ばす（seam_fill）。1枚絵から切り出した部位は、他の部位の下に潜る側にも
	# 元絵の輪郭線と影が残り、角度が変わると継ぎ目に線や段が出る。部位ごとに描いた素材（既存の冒険者）と同じく、
	# 潜る側を平らな塗りにする。{"thigh": {"top": 0.3, "strength": 1.0}}（top / bottom は帯の深さ、画像の高さに対する割合）
	var fill:Dictionary=config.get("seam_fill",{}).get(group,{})
	if not fill.is_empty():
		fill_seam(part,float(fill.get("top",0.0)),float(fill.get("bottom",0.0)),float(fill.get("strength",1.0)))
		if float(fill.get("taper",0.0))>0.0:taper_top(part,float(fill.get("top",0.0)),float(fill.get("taper",0.0)))
	if bool(config.get("rounded_joins",{}).get(group,false)):
		for y in range(72,240):
			for x in range(240):
				var nx:float=(x-119.5)/119.5
				var ny:float=(float(y)/239.0-.3)/.7
				var coverage:=clampf((1.0-nx*nx-ny*ny)/.10,0.0,1.0)
				var pixel:=part.get_pixel(x,y);pixel.a*=coverage;part.set_pixel(x,y,pixel)
	# Fade only the internal join, already covered by the adjoining surface.
	# This is baked once at import; no extra runtime layer or draw call.
	# seam_fade_by_view があれば元画像の向き（STANDARD の番号）ごとの値を優先する。
	var fade_by_view:Dictionary=config.get("seam_fade_by_view",{}).get(group,{})
	var view_fade=fade_by_view.get(str(Views.source(config,view)),null) if not fade_by_view.is_empty() else null
	if view_fade!=null or config.get("seam_fade",{}).has(group):
		var fade:Array=view_fade if view_fade!=null else config.seam_fade[group]
		for y in range(240):
			var weight:=1.0
			if float(fade[0])>0:weight*=smoothstep(0,float(fade[0])*239,y)
			if float(fade[1])>0:weight*=smoothstep(0,float(fade[1])*239,239-y)
			if weight<1:
				for x in range(240):
					var color:=part.get_pixel(x,y);color.a*=weight;part.set_pixel(x,y,color)
	if (group in ["elbow","knee","neck"] and not (group=="neck" and config.get("separate_neck",false))) or (group=="head" and view==8):
		for y in range(240):
			for x in range(240):
				var q:=(Vector2(x,y)-Vector2(119.5,119.5))/119.5
				var c:=part.get_pixel(x,y);c.a*=clampf((1-q.length())*12,0,1);part.set_pixel(x,y,c)
