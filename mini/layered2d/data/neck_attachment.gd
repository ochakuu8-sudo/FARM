extends RefCounted
## Art sockets are in the final 256px tile, including its 8px margin.
## Five authored directions: front, front-quarter, side, rear-quarter, back.
const BASE_COLUMN=96 # Binding 0..91 remains the existing 23-slot format.
static var defaults:Dictionary={}

static func order_slots(input:PackedInt32Array)->PackedInt32Array:
	var neck:=input.find(3);var head:=input.find(4);var chest:=input.find(2)
	var target:int=mini(head if head>=0 else neck,chest if chest>=0 else neck)
	if neck<0 or target>=neck:return input
	var result:=input.duplicate();result.remove_at(neck);result.insert(target,3);return result

static func order_members(input:Array)->Array:
	var result:=input.duplicate()
	for part in input:
		if int(part.slot)!=3:continue
		var neck:=result.find(part);var target:=neck
		for i in range(neck):
			if result[i].actor==part.actor and int(result[i].slot) in [2,4]:target=i;break
		if target<neck:result.remove_at(neck);result.insert(target,part)
	return result

static func expand(points:Array)->Array:
	var out:Array=[]
	for v in range(9):
		var p:Array=points[[0,1,2,3,4,3,2,1,4][v]].duplicate()
		if v in [5,6,7]:p[0]=1-p[0]
		out.append(p)
	return out

static func for_recipe(recipe:Dictionary)->Dictionary:
	if defaults.is_empty():defaults=JSON.parse_string(FileAccess.get_file_as_string("res://mini/layered2d/data/neck_defaults.json"))
	var head:Dictionary=defaults[str(recipe.modules.head)]
	var upper:Dictionary=defaults[str(recipe.get("part_sources",{}).get("chest",recipe.modules.upper_body))]
	if recipe.has("neck_attachment"):
		var saved:Dictionary=recipe.neck_attachment.duplicate(true)
		if not saved.has("skin"):
			saved.skin=head.skin.duplicate()
			var path:String=recipe.get("asset_modules",{}).get("head",{}).get("groups",{}).get("neck",{}).get("0","")
			if not path.is_empty() and FileAccess.file_exists(path):
				var image:=Image.load_from_file(path)
				if image!=null:
					var color:=image.get_pixelv(image.get_size()/2);saved.skin=[color.r,color.g,color.b]
		return saved
	return {"version":2,"head":expand(head.jaw),"collar":expand(upper.collar),"skin":head.skin,"length":upper.length,"width":upper.width,"collar_cut":upper.collar_cut,"head_cut":head.head_cut}

# Apply to prepared tiles, preserving their placement and dimensions.
static func cut_tile(image:Image,polygons:Array,view:int)->void:
	if polygons.is_empty() or view==8:return
	var polygon:=PackedVector2Array()
	for p in polygons[[0,1,2,3,4,3,2,1][view]]:
		polygon.append(Vector2(1-p[0] if view in [5,6,7] else p[0],p[1])*Vector2(image.get_size()))
	if polygon.size()<3:return
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for p in polygon:bounds=bounds.expand(p)
	for y in range(maxi(0,floori(bounds.position.y)),mini(image.get_height(),ceili(bounds.end.y))):
		for x in range(maxi(0,floori(bounds.position.x)),mini(image.get_width(),ceili(bounds.end.x))):
			if Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),polygon):
				var c:=image.get_pixel(x,y);c.a=0;image.set_pixel(x,y,c)

static func validate_points(points:Variant,count:int=5)->bool:
	if not points is Array or points.size()!=count:return false
	for p in points:
		if not p is Array or p.size()!=2:return false
		for n in p:
			if not (n is float or n is int) or not is_finite(n) or n<0 or n>1:return false
	return true

static func resolve(fit:Dictionary)->Dictionary:
	var required:bool=fit.get("body_sets",{}).get("upper",{}).get("authored_dimensions",false)
	var head:Dictionary=fit.modules.head.get("sockets",{})
	var upper:Dictionary=fit.get("set_materials",{}).get("upper",fit)
	var collar:Dictionary=upper.modules.upper_body.get("sockets",{})
	if head.is_empty() and collar.is_empty() and not required:return {"ok":true,"attachment":{}}
	if not validate_points(head.get("jaw",[])) or not validate_points(collar.get("collar",[])) or not fit.modules.head.has("neck_cut"):
		return {"ok":false,"error":"頭から首を分離し、顎下と襟の接続点を5方向ぶん登録してください。首入り画像＋上下補正では代用しません。"}
	if fit.modules.head.neck_cut.size()!=5:return {"ok":false,"error":"首の除外範囲は5方向必要です（首のない新規素材は各方向を空配列）。"}
	var skin=fit.modules.head.get("neck_skin",[])
	if not skin is Array or skin.size()!=3:return {"ok":false,"error":"独立した首の肌色 neck_skin を登録してください。"}
	for n in skin:
		if not (n is float or n is int) or not is_finite(n) or n<0 or n>1:return {"ok":false,"error":"neck_skin は0〜1のRGBです。"}
	var result:Dictionary={"version":2,"head":[],"collar":[]}
	for v in range(9):
		var source:int=[0,1,2,3,4,3,2,1,4][v]
		for entry in [["head",head.jaw],["collar",collar.collar]]:
			var p:Array=entry[1][source].duplicate()
			if v in [5,6,7]:p[0]=1.0-p[0]
			result[entry[0]].append(p)
	# The existing overhead tile is a crop of the back of the head; its pivot is internal.
	result.head[8]=head.get("crown",[.5,.85]).duplicate()
	result.skin=skin.duplicate()
	result.length=float(collar.get("length",.035))
	result.collar_cut=upper.modules.upper_body.get("collar_cut",[]).duplicate(true)
	result.head_cut=[] # Already removed by the registered head importer.
	return {"ok":true,"attachment":result}
