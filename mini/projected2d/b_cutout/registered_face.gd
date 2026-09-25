extends RefCounted
## Regional inputs remain independent. Only the active state is composited;
## the head's existing UV mesh and renderer perform all camera interpolation.
const DIRECTIONS=["front","quarter","side"]
const MAX_SLOTS=16
static func fail(message:String)->Dictionary:return {"ok":false,"error":message}
static func whole(v)->bool:return (v is int or v is float) and is_finite(float(v)) and v==floorf(v)
static func rect_ok(a)->bool:
	if not a is Array or a.size()!=4:return false
	for v in a:
		if not (v is int or v is float) or not is_finite(float(v)):return false
	return a[0]>=0 and a[1]>=0 and a[2]>0 and a[3]>0
static func anchor_ok(a)->bool:
	if not a is Dictionary or not whole(a.get("handedness")) or absf(float(a.handedness))!=1.0:return false
	for key in ["a","b"]:
		if not a.get(key) is Array or a[key].size()!=2:return false
		for n in a[key]:
			if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>256:return false
	return Vector2(a.a[0],a.a[1]).distance_to(Vector2(a.b[0],a.b[1]))>=2.0
static func anchor_transform(a:Dictionary)->Transform2D:
	var p:=Vector2(a.a[0],a.a[1]);var q:=Vector2(a.b[0],a.b[1])
	var x:=(q-p)/128.0
	var y:=Vector2(-x.y,x.x)*float(a.handedness)
	return Transform2D(x,y,p-x*64.0-y*128.0)
static func anchored_patch(source:Image,a:Dictionary)->Image:
	var out:=Image.create(256,256,false,Image.FORMAT_RGBA8)
	var transform:=anchor_transform(a);var inverse:=transform.affine_inverse()
	var bounds:=Rect2(transform*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(256,0),Vector2(0,256),Vector2(256,256)]:bounds=bounds.expand(transform*corner)
	for y in range(maxi(0,floori(bounds.position.y)-1),mini(256,ceili(bounds.end.y)+1)):
		for x in range(maxi(0,floori(bounds.position.x)-1),mini(256,ceili(bounds.end.x)+1)):
			var uv:=inverse*Vector2(x,y)
			if uv.x<0 or uv.y<0 or uv.x>=255 or uv.y>=255:continue
			var ix:=floori(uv.x);var iy:=floori(uv.y);var f:=uv-Vector2(ix,iy)
			# Interpolate premultiplied RGB, then return straight alpha.
			var sum:=Color(0,0,0,0)
			for j in range(2):
				for i in range(2):
					var c:=source.get_pixel(ix+i,iy+j)
					var w:=(f.x if i==1 else 1.0-f.x)*(f.y if j==1 else 1.0-f.y)
					sum+=Color(c.r*c.a,c.g*c.a,c.b*c.a,c.a)*w
			if sum.a>0.00001:out.set_pixel(x,y,Color(sum.r/sum.a,sum.g/sum.a,sum.b/sum.a,sum.a))
	return out
static func validate_definition(face:Dictionary)->Dictionary:
	var d=face.get("registered")
	if not d is Dictionary or d.get("version")!=1:return fail("Registered face version")
	if not d.get("slots") is Array or d.slots.is_empty() or d.slots.size()>MAX_SLOTS:return fail("1..16 named slots required")
	if not d.get("registration") is Dictionary or not d.get("presets") is Dictionary:return fail("Registration/presets required")
	if d.get("mix","gradient") not in ["gradient","blend","snap"]:return fail("Unknown face mix")
	if face.has("mix_mask_row") and (not whole(face.mix_mask_row) or face.mix_mask_row<0 or face.mix_mask_row>=face.row_count):return fail("Mask outside atlas")
	if not whole(d.get("max_cache_entries",8)) or d.get("max_cache_entries",8)<1 or d.get("max_cache_entries",8)>16:return fail("Cache bound 1..16")
	var known:Dictionary={}
	for slot in d.slots:
		if not slot is Dictionary or not slot.get("id") is String or slot.id.is_empty() or known.has(slot.id):return fail("Unique slot id required")
		if not slot.get("variants") is Dictionary or not slot.variants.has(slot.get("default")):return fail("Slot default missing")
		known[slot.id]=slot
		if slot.get("placement","rect") not in ["rect","anchors"]:return fail("Unknown placement")
		if slot.get("paint","over") not in ["over","replace_rgb"]:return fail("Unknown slot paint mode")
		if slot.has("atlas_path"):
			if not slot.atlas_path is String or not slot.atlas_path.begins_with("res://") or not slot.atlas_path.ends_with(".png"):return fail("Invalid slot atlas path")
			if not whole(slot.get("atlas_row_count")) or slot.atlas_row_count<1 or slot.atlas_row_count>34:return fail("Invalid donor atlas rows")
		if slot.has("overlay") and slot.overlay not in ["blush","tears"]:return fail("Unsupported overlay control")
		if slot.get("fallback","front") not in DIRECTIONS:return fail("Invalid fallback direction")
		for direction in DIRECTIONS:
			if not d.registration.get(direction) is Dictionary or not d.registration[direction].has(slot.id):return fail("Missing registration: "+slot.id+"/"+direction)
			var r=d.registration[direction][slot.id]
			if r!=null and (not rect_ok(r) or r[0]+r[2]>1 or r[1]+r[3]>1):return fail("Registration outside head")
			if r!=null and slot.get("placement")=="anchors" and not anchor_ok(d.get("anchors",{}).get(direction,{}).get(slot.id)):return fail("Missing/invalid recipient anchors: "+slot.id+"/"+direction)
		var variant_sets:Array=slot.variants.values()
		if slot.has("transfer_variants"):
			if not slot.transfer_variants is Dictionary:return fail("Transfer variants must be an object")
			variant_sets.append_array(slot.transfer_variants.values())
		for variant in variant_sets:
			if not variant is Dictionary or not variant.has(slot.get("fallback","front")):return fail("Missing fallback artwork")
			for direction in variant:
				if direction not in DIRECTIONS:return fail("Unknown asset direction")
				var a=variant[direction]
				if not a is Dictionary or not whole(a.get("row")) or not whole(a.get("column")) or a.row<0 or a.row>=slot.get("atlas_row_count",face.row_count) or a.column<0 or a.column>=10:return fail("Asset tile outside atlas")
				if not rect_ok(a.get("rect")) or a.rect[0]+a.rect[2]>256 or a.rect[1]+a.rect[3]>256:return fail("Asset rectangle outside tile")
				if slot.get("placement")=="anchors" and (a.rect[0]!=0 or a.rect[1]!=0 or a.rect[2]!=256 or a.rect[3]!=256):return fail("Anchor art requires the fixed 256px canvas")
	if not d.presets.has("neutral"):return fail("Neutral preset required")
	for preset in d.presets.values():
		if not preset is Dictionary:return fail("Preset must be an object")
		for id in preset:
			if not known.has(id) or not known[id].variants.has(preset[id]):return fail("Unknown preset slot/variant")
	return {"ok":true}
static func validate_state(state:Dictionary,face:Dictionary)->Dictionary:
	var d:Dictionary=face.registered
	var id=state.get("expression","neutral")
	if not id is String or (id!="custom" and not d.presets.has(id)):return fail("Unknown expression: "+str(id))
	var selected=state.get("face_parts",{})
	if not selected is Dictionary:return fail("face_parts must be an object")
	if id=="custom" and selected.is_empty():return fail("Custom expression requires named slots")
	var slots:Dictionary={}
	for s in d.slots:slots[s.id]=s
	for key in selected:
		var names:Array=["eye_l","eye_r"] if key=="eyes" else [key]
		for name in names:
			if not slots.has(name) or not slots[name].variants.has(selected[key]):return fail("Unknown slot/variant: "+str(name))
	var overlays=state.get("overlays",{})
	if not overlays is Dictionary:return fail("overlays must be an object")
	for key in overlays:
		var v=overlays[key]
		if key not in ["blush","tears"] or not (v is int or v is float) or not is_finite(float(v)) or v<0 or v>1:return fail("Invalid overlay strength")
	return {"ok":true}
static func render_data(face:Dictionary,id:String,custom:Dictionary,overlays:Dictionary)->Dictionary:
	var d:Dictionary=face.registered
	var selection:Dictionary={}
	for slot in d.slots:selection[slot.id]=slot.default
	selection.merge(d.presets.get(id,d.presets.neutral),true)
	if id=="custom":
		for key in custom:
			if key=="eyes":selection.eye_l=custom[key];selection.eye_r=custom[key]
			else:selection[key]=custom[key]
	return {"atlas_path":face.atlas_path,"blank":face.blank_row,"eyes":-1,"mouth":-1,"blush":-1,"tears":-1,
		"blush_strength":0,"tears_strength":0,"registered":d,"selection":selection,"overlay_values":overlays.duplicate(true),"mix":d.get("mix","gradient"),"mix_mask_row":face.get("mix_mask_row",-1)}
static func compose(face:Dictionary,inputs:Dictionary,base:Image)->Dictionary:
	var started:=Time.get_ticks_usec()
	var result:Image=base.duplicate();var records:Array=[]
	var d:Dictionary=face.registered
	for vi in [0,1,2,6,7]:
		var canonical:int=8-vi if vi>=6 else vi
		var direction:String=DIRECTIONS[canonical]
		var head:=base.get_region(Rect2i(vi*256,0,256,256))
		# Draw reflected art in its authored orientation, then reflect as one head.
		if vi>=6:head.flip_x()
		for slot in d.slots:
			var id:String=slot.id
			var selection_id:=id
			if vi>=6 and id.ends_with("_l") and face.selection.has(id.trim_suffix("_l")+"_r"):selection_id=id.trim_suffix("_l")+"_r"
			elif vi>=6 and id.ends_with("_r") and face.selection.has(id.trim_suffix("_r")+"_l"):selection_id=id.trim_suffix("_r")+"_l"
			var variant:String=face.selection[selection_id]
			var r=d.registration[direction][id]
			if r==null:records.append({"slot":id,"view":vi,"visible":false});continue
			var strength:float=face.overlay_values.get(slot.overlay,0) if slot.has("overlay") else 1.0
			var source_slot:Dictionary=slot
			if not source_slot.variants.has(variant):
				for candidate in d.slots:
					if candidate.id==selection_id:source_slot=candidate;break
			var artwork:Dictionary=source_slot.variants[variant]
			var used:String=direction if artwork.has(direction) else source_slot.get("fallback","front")
			var art:Dictionary=artwork[used];var b:Array=art.rect
			var input:Image=inputs[art.get("atlas_path",source_slot.get("atlas_path",face.atlas_path))]
			var target:=Rect2i(roundi(r[0]*256),roundi(r[1]*256),maxi(1,roundi(r[2]*256)),maxi(1,roundi(r[3]*256)))
			records.append({"slot":id,"view":vi,"visible":strength>0,"variant":variant,"art_id":art.get("input",str(art.row)+":"+str(art.column)),"atlas_path":source_slot.get("atlas_path",face.atlas_path),"paint":slot.get("paint","over"),"direction":used,"fallback":used!=direction,"target":[target.position.x,target.position.y,target.size.x,target.size.y],"strength":strength})
			if strength<=0:continue
			var patch:=input.get_region(Rect2i(art.column*256+int(b[0]),art.row*256+int(b[1]),int(b[2]),int(b[3])))
			if slot.get("placement")=="anchors":
				var anchors:Dictionary=d.anchors[direction][id]
				patch=anchored_patch(patch,anchors);target=Rect2i(0,0,256,256)
				records[-1]["placement"]="anchors";records[-1]["anchors"]=anchors.duplicate(true)
				records[-1]["scale"]=anchor_transform(anchors).x.length()
			elif patch.get_size()!=target.size:patch.resize(target.size.x,target.size.y,Image.INTERPOLATE_BILINEAR)
			if strength<1:
				for y in range(patch.get_height()):
					for x in range(patch.get_width()):
						var c:=patch.get_pixel(x,y);c.a*=strength;patch.set_pixel(x,y,c)
			if slot.get("paint","over")=="replace_rgb" and strength==1.0:head.blit_rect(patch,Rect2i(Vector2i.ZERO,patch.get_size()),target.position)
			else:head.blend_rect(patch,Rect2i(Vector2i.ZERO,patch.get_size()),target.position)
		if vi>=6:head.flip_x()
		result.blit_rect(head,Rect2i(0,0,256,256),Vector2i(vi*256,0))
	# Expression layers never change head coverage or protected external pixels.
	var pixels:=result.get_data();var original:=base.get_data()
	for i in range(0,pixels.size(),4):
		pixels[i+3]=original[i+3]
		if original[i+3]==0:
			for c in range(3):pixels[i+c]=original[i+c]
	result=Image.create_from_data(2560,256,false,Image.FORMAT_RGBA8,pixels)
	return {"image":result,"slots":records,"compose_usec":Time.get_ticks_usec()-started}
