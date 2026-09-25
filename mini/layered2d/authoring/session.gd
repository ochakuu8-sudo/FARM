extends RefCounted
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const Adapter = preload("res://mini/layered2d/prepare/rig_pose_adapter.gd")
const Interaction = preload("res://mini/projected2d/interaction.gd")
const Secondary=preload("res://mini/layered2d/prepare/secondary_motion.gd")
const BodySets=preload("res://mini/layered2d/data/body_sets.gd")
const Library=preload("res://mini/rig3d/library.gd")
var catalog := Catalog.new()
var actors: Array = []
var recipes: Array = []
var scene: Dictionary = {}
var constraints := Interaction.new()
var last_diagnostic: Dictionary = {}
var mode := "runtime_preview"
var secondary_dirty:=true
var baking_secondary:=false
var secondary_diagnostic:Dictionary={}
var face_timelines:Array=[]
## 衣装の時間切り替え（actor ごと）[{t, outfit}]。空なら切り替えない。描画側（resource_store.apply_outfit_track）が使う。
var outfit_timelines:Array=[]
## 直近の evaluate での押し込み量（world）。{"taker.breast_l": 0.02, ...}。数値確認用。
var last_press:Dictionary={}

func load_scene(value: Dictionary, stage: String="") -> Dictionary:
	value=value.duplicate(true)
	if not stage.is_empty():
		if not value.get("stages",{}) is Dictionary or not value.stages.get(stage) is Dictionary:return {"ok":false,"code":"STAGE_MISSING","stage":stage}
		value=merge_fields(value,value.stages[stage])
		value["selected_stage"]=stage
	if value.has("duration") and (not finite_number(value.duration) or value.duration<=0):return {"ok":false,"code":"SCENE_DURATION"}
	if value.get("version")!=1 or not value.get("actors") is Array or value.actors.is_empty() or value.actors.size()>2:return {"ok":false,"code":"SCENE_FORMAT"}
	var prepared: Array=[]
	var body_recipes: Array=[]
	var timelines:Array=[]
	var outfit_list:Array=[]
	var ids: Array=[]
	for i in range(value.actors.size()):
		var def: Dictionary=value.actors[i]
		var id: String=def.get("id","actor_"+str(i))
		if ids.has(id):return {"ok":false,"code":"DUPLICATE_ACTOR"}
		ids.append(id)
		var recipe: Dictionary=def.get("recipe",catalog.recipe(100+i)).duplicate(true)
		if def.has("character") and not def.has("recipe"):
			var character:=int(def.character)
			if character<0 or character>=catalog.configs.size():return {"ok":false,"code":"CHARACTER_MISSING"}
			for module in recipe.modules:recipe.modules[module]=character
			for part in recipe.face:recipe.face[part]=character
			if catalog.configs[character].face.get("mode","registered")=="baked":recipe.face={}
			recipe.profile=catalog.configs[character].profile.duplicate(true)
			recipe.height=1.0;recipe.thickness=1.0;recipe.head_scale=1.0
		var shaped:=BodySets.apply(recipe,catalog.configs)
		if not shaped.ok:return {"ok":false,"code":"BODY_SETS","error":shaped.error}
		recipe=shaped.recipe
		if def.has("face"):
			var face_result:=apply_face(recipe,def.face)
			if not face_result.ok:face_result.actor=id;return face_result
		if not finite_number(def.get("phase_offset",0.0)) or def.get("phase_offset",0.0)<0 or def.get("phase_offset",0.0)>1:return {"ok":false,"code":"PHASE_OFFSET_RANGE","actor":id}
		var err:=catalog.validate(recipe)
		if not err.is_empty():return {"ok":false,"code":err}
		var face_keys:=build_face_timeline(recipe,def.get("face_keys",[]))
		if not face_keys.ok:face_keys.actor=id;return face_keys
		timelines.append(face_keys.keys)
		var outfit:=build_outfit_timeline(str(value.get("outfits",{}).get(id,def.get("outfit",""))) if value.get("outfits",{}) is Dictionary else str(def.get("outfit","")),def.get("outfit_keys",[]))
		if not outfit.ok:outfit.actor=id;return outfit
		outfit_list.append(outfit.keys)
		var actor:=Adapter.new()
		actor.configure(BodySets.actor_config(recipe,catalog.configs),recipe.profile)
		# Defaults follow the selected body module, not just the head donor.
		actor.secondary_settings=catalog.secondary_for(recipe)
		if not def.get("secondary",{}) is Dictionary:return {"ok":false,"code":"SECONDARY_FORMAT","actor":id}
		actor.secondary_settings=merge_fields(actor.secondary_settings,def.get("secondary",{}))
		# 場面（段階）の loop=false：1回だけの動き（絶頂・余韻など）。揺れを周期で閉じず、静止から一度だけ焼く。
		if value.get("loop",true)==false:
			for part in actor.secondary_settings:
				if actor.secondary_settings[part] is Dictionary:actor.secondary_settings[part].loop=false
		var secondary_result:=Secondary.validate(actor.secondary_settings)
		if not secondary_result.ok:secondary_result.actor=id;return secondary_result
		var imported:=install_clips(actor.library,value.get("clips",{}))
		if not imported.ok:return imported
		actor.clip=def.get("clip","idle")
		if actor.clip not in Catalog.CLIPS and not actor.library.clips.has(actor.clip):return {"ok":false,"code":"CLIP_MISSING"}
		var p: Array=def.get("root",[0,0,0])
		actor.root=Vector3(p[0],p[1],p[2]);actor.world_yaw=float(def.get("yaw",0));actor.body_scale=recipe.height
		for goal in def.get("goals_world",{}):
			var target: Array=def.goals_world[goal]
			actor.goal_overrides[goal]=actor.world_to_solver(Vector3(target[0],target[1],target[2]))
		if def.has("pose"):
			var set_result: Dictionary=actor.set_pose(def.pose)
			if not set_result.ok:return set_result
		prepared.append(actor);body_recipes.append(recipe)
	var goals: Dictionary={}
	var leaders: Dictionary={}
	for group in value.get("constraints",[]):
		var a: int=ids.find(group.get("leader"));var b: int=ids.find(group.get("follower"))
		if a<0 or b<0 or a==b:return {"ok":false,"code":"CONSTRAINT_ACTOR"}
		if leaders.has(a):return {"ok":false,"code":"CONSTRAINT_CYCLE"}
		leaders[b]=a
		for binding in group.get("bindings",[]):
			if binding is Dictionary and binding.has("offset_keys"):
				var problem: String=validate_offset_keys(binding.offset_keys)
				if problem!="":return {"ok":false,"code":"OFFSET_KEYS","error":problem,"goal":str(binding.get("follower_goal"))}
			var key: String=str(b)+":"+str(binding.get("follower_goal"))
			if goals.has(key):return {"ok":false,"code":"DUPLICATE_GOAL","goal":key}
			goals[key]=true
	scene=value.duplicate(true);actors=prepared;recipes=body_recipes;face_timelines=timelines;outfit_timelines=outfit_list;secondary_dirty=true
	return {"ok":true}

func build_face_timeline(base:Dictionary,keys:Variant)->Dictionary:
	if not keys is Array:return {"ok":false,"code":"FACE_KEYS_FORMAT"}
	if keys.is_empty():return {"ok":true,"keys":[]}
	if keys.size()>64:return {"ok":false,"code":"FACE_KEYS_LIMIT","limit":64}
	if catalog.configs[int(base.modules.head)].face.get("mode","registered")=="baked":return {"ok":false,"code":"BAKED_FACE_NO_PARTS"}
	var result:Array=[{"t":0.0,"recipe":base.duplicate(true)}]
	var previous:=-1.0
	for i in range(keys.size()):
		var key=keys[i]
		var path:="face_keys["+str(i)+"]"
		if not key is Dictionary or not finite_number(key.get("t")) or key.t<0 or key.t>1 or key.t<=previous:return {"ok":false,"code":"FACE_KEY_TIME","path":path}
		if not key.get("face") is Dictionary:return {"ok":false,"code":"FACE_FORMAT","path":path+".face"}
		# Each key patches the static base, never the preceding key. Random seeking
		# and omitted slots therefore have the same meaning as sequential playback.
		var recipe:Dictionary=base.duplicate(true)
		var changed:=apply_face(recipe,key.face)
		if not changed.ok:changed.path=path+".face";return changed
		var error:=catalog.validate(recipe)
		if not error.is_empty():return {"ok":false,"code":error,"path":path+".face"}
		if key.t==0:result.clear()
		result.append({"t":float(key.t),"recipe":recipe});previous=key.t
	return {"ok":true,"keys":result}

## 衣装。actors[].outfit（または最上位 outfits.<actor id>、段階で上書きしやすい）が基準、
## actors[].outfit_keys=[{t, outfit}] で場面の位相に応じて切り替える。"" は元の服。
## 衣装名が原型に登録されているかは描画側で見る（無い衣装名は元の服のまま）。
func build_outfit_timeline(base:String,keys:Variant)->Dictionary:
	if not keys is Array:return {"ok":false,"code":"OUTFIT_KEYS_FORMAT"}
	if base=="" and keys.is_empty():return {"ok":true,"keys":[]}
	var result:Array=[{"t":0.0,"outfit":base}]
	var previous:=-1.0
	for i in range(keys.size()):
		var key=keys[i]
		if not key is Dictionary or not finite_number(key.get("t")) or key.t<0 or key.t>1 or key.t<=previous or not key.get("outfit") is String:
			return {"ok":false,"code":"OUTFIT_KEY","path":"outfit_keys["+str(i)+"]"}
		if key.t==0:result.clear()
		result.append({"t":float(key.t),"outfit":key.outfit});previous=key.t
	return {"ok":true,"keys":result}

func face_at(index:int,scene_phase:float)->Dictionary:
	var selected:Dictionary=recipes[index]
	var local_phase:=actor_phase(index,scene_phase)
	for key in face_timelines[index]:
		if key.t>local_phase:break
		selected=key.recipe
	return selected.get("expression",{}).duplicate(true)

func apply_face(recipe:Dictionary,value:Variant)->Dictionary:
	if not value is Dictionary:return {"ok":false,"code":"FACE_FORMAT"}
	var config:Dictionary=catalog.configs[int(recipe.modules.head)].duplicate(true)
	if recipe.has("asset_face"):config.face=recipe.asset_face
	if value.is_empty():return {"ok":true}
	# 一枚絵の顔（追加4人など）は頭画像ごとの差し替え：{"baked": 名前}（原型の expression_atlases に登録した名前）。
	# 部位の顔（preset / eye_l など）と一緒に書いてよい。体型の顔の種類に合う方だけを使う。
	if config.face.get("mode","registered")=="baked":
		if value.has("baked"):
			if str(value.baked)=="" or str(value.baked)=="neutral":recipe.expression={};return {"ok":true}
			if not config.face.get("expression_atlases",{}).has(str(value.baked)):return {"ok":false,"code":"BAKED_EXPRESSION_MISSING","name":str(value.baked),"available":config.face.get("expression_atlases",{}).keys()}
			recipe.expression={"baked":str(value.baked)}
			return {"ok":true}
		return {"ok":false,"code":"BAKED_FACE_NO_PARTS"}
	value=value.duplicate();value.erase("baked")
	if value.is_empty():return {"ok":true}
	var expression:Dictionary=recipe.get("expression",{}).duplicate(true)
	if value.has("preset"):
		var presets:Dictionary=config.face.registered.get("presets",{})
		if not value.preset is String or not presets.has(value.preset):return {"ok":false,"code":"FACE_PRESET_MISSING","preset":value.preset}
		expression.merge(presets[value.preset],true)
	for key in value:
		if key=="preset":continue
		if key not in ["eye_l","eye_r","brow_l","brow_r","mouth"] or not value[key] is String:return {"ok":false,"code":"FACE_SLOT_OR_VARIANT","slot":key}
		expression[key]=value[key]
	recipe.expression=expression
	return {"ok":true}

func actor_phase(index:int,scene_phase:float)->float:
	var offset:float=scene.actors[index].get("phase_offset",0.0)
	return clampf(scene_phase,0,1) if offset==0 or offset==1 else fposmod(clampf(scene_phase,0,1)-offset,1.0)

func prepare_secondary(force:bool=false)->Dictionary:
	if baking_secondary or (not secondary_dirty and not force):return {"ok":true}
	for actor in actors:actor.secondary_track=[]
	var enabled:=false
	for actor in actors:enabled=enabled or Secondary.enabled(actor.secondary_settings)
	if not enabled:secondary_dirty=false;secondary_diagnostic={};return {"ok":true}
	baking_secondary=true
	var saved:Array=[];var inputs:Array=[]
	for actor in actors:
		saved.append({"root":actor.root,"goals":actor.goal_overrides.duplicate(true),"phase":actor.phase})
		inputs.append([])
	var count:=maxi(2,ceili(duration()*Secondary.HZ))
	var failure:Dictionary={}
	for i in range(count+1):
		var value:=evaluate(float(i)/count)
		if not value.ok:failure=value;break
		for a in range(actors.size()):
			var frame:Dictionary={};var member:Dictionary=value.members[a]
			for part in Secondary.PARTS:
				var point:Vector3
				if part in Secondary.SOFT_PARTS:
					var parent:Dictionary=value.snapshots[a].parts[Secondary.soft_slot(part)]
					point=parent.center+Basis(parent.rotation)*soft_anchor(actors[a],part)
				else:point=value.snapshots[a].parts[Catalog.SLOTS.find(part)].center
				frame[part]=Basis(Vector3.UP,deg_to_rad(member.yaw))*point*member.height+member.root
			inputs[a].append(frame)
	var tracks:Array=[];secondary_diagnostic={}
	if failure.is_empty():
		for a in range(actors.size()):
			var result:=Secondary.bake(inputs[a],actors[a].secondary_settings,duration(),actors[a].body_scale)
			if not result.ok:result.actor=scene.actors[a].get("id",str(a));failure=result;break
			tracks.append(result.frames);secondary_diagnostic[str(a)]={"periodic_residual":result.periodic_residual,"samples":count+1}
	for a in range(actors.size()):
		actors[a].root=saved[a].root;actors[a].goal_overrides=saved[a].goals;actors[a].phase=saved[a].phase
		if failure.is_empty():actors[a].secondary_track=tracks[a]
	baking_secondary=false
	if not failure.is_empty():return failure
	secondary_dirty=false
	return {"ok":true}

func soft_anchor(actor,part:String)->Vector3:
	var a:Array=actor.secondary_settings.get(part,{}).get("anchor",[0,0,0])
	return Vector3(a[0],a[1],a[2])

func set_pose(index: int, pose: Dictionary) -> Dictionary:
	if index<0 or index>=actors.size():return {"ok":false,"code":"ACTOR_INDEX"}
	var r: Dictionary=actors[index].set_pose(pose)
	if r.ok:scene.actors[index].pose=pose.duplicate(true);secondary_dirty=true
	return r

func set_goal(index: int, goal: String, target: Vector3) -> Dictionary:
	if index<0 or index>=actors.size() or goal not in ["hand_l","hand_r","foot_l","foot_r"] or not target.is_finite():return {"ok":false,"code":"IK_GOAL"}
	actors[index].goal_overrides[goal]=actors[index].world_to_solver(target)
	if not scene.actors[index].has("goals_world"):scene.actors[index].goals_world={}
	scene.actors[index].goals_world[goal]=[target.x,target.y,target.z]
	secondary_dirty=true
	return {"ok":true}

func evaluate(phase: float) -> Dictionary:
	if not baking_secondary:
		var prepared:=prepare_secondary()
		if not prepared.ok:return prepared
	var ids: Array=[]
	for i in range(actors.size()):
		actors[i].phase=actor_phase(i,phase)
		actors[i].secondary_phase=clampf(phase,0,1)
		ids.append(scene.actors[i].get("id","actor_"+str(i)))
	var residuals: Dictionary={}
	## 肘・膝の目標（寄せる目安）までの距離。判定には入らない。{"leader:follower": {"elbow_l": 距離}}
	var bend: Dictionary={}
	# Merge multiple groups for the same direction before solving, preserving all goals.
	var merged: Dictionary={}
	for group in scene.get("constraints",[]):
		var key: String=str(group.leader)+":"+str(group.follower)
		if not merged.has(key):merged[key]={"leader":group.leader,"follower":group.follower,"bindings":[],"placement":group.get("placement",{})}
		merged[key].bindings.append_array(timed_bindings(group.bindings,phase))
	for key in merged:
		var group: Dictionary=merged[key]
		var result: Dictionary=constraints.solve(actors[ids.find(group.leader)],actors[ids.find(group.follower)],group.bindings,group.placement)
		if result.has("error"):return {"ok":false,"code":"CONSTRAINT_FAILED","error":result.error,"worst":{"group":key,"phase":phase}}
		residuals[key]=result.residuals
		if not result.get("bend",{}).is_empty():bend[key]=result.bend
	var snapshots: Array=[]
	var members: Array=[]
	var samples: Array=[]
	for actor in actors:samples.append(actor.sample(actor.phase,phase))
	apply_press(samples,ids)
	apply_aims(samples,ids,phase)
	for index in range(actors.size()):
		var actor=actors[index]
		var sample: Dictionary=samples[index]
		var inverse:=Basis(Vector3.UP,deg_to_rad(-actor.world_yaw))
		for part in sample.parts:
			part.center=inverse*(part.center-actor.root)/actor.body_scale
			part.anchor=inverse*(part.anchor-actor.root)/actor.body_scale
			part.rotation=(inverse*Basis(part.rotation)).get_rotation_quaternion().normalized()
			part.radii/=actor.body_scale
		snapshots.append(sample)
		members.append({"root":actor.root,"yaw":actor.world_yaw,"height":actor.body_scale})
	var faces:Array=[]
	for i in range(actors.size()):faces.append(face_at(i,phase))
	last_diagnostic={"ok":true,"phase":phase,"snapshots":snapshots,"members":members,"contact_residuals_world":residuals,"bend_residuals_world":bend,"press_world":last_press.duplicate(),"actor_ids":ids,"layer_rules":scene.get("layer_rules",[]),"faces":faces}
	return last_diagnostic

## 押し込み。actors[i].press = {"from": 相手のid, "radius": 0.08, "strength": 1.0, "max": 0.06, "parts": ["hand_l","hand_r"]}
## 相手の部位（既定は両手の中心）が、この actor の胸・尻の揺れる領域の中心（原型の soft.*.anchor）から radius 以内に入ると、
## 手から離れる向きに押し込んだぶんを揺れの変位（parts[].soft / soft_butt）に足す。描画は揺れと同じく、領域がずれて潰れる。
## radius / max は world 単位（体の倍率をかける前の基準）。soft が登録されていない原型では何もしない。
func apply_press(samples: Array,ids: Array) -> void:
	last_press={}
	for i in range(actors.size()):
		var press=scene.actors[i].get("press")
		if not press is Dictionary:continue
		var other: int=ids.find(str(press.get("from","")))
		if other<0 or other==i:continue
		var scale: float=actors[i].body_scale
		var radius: float=float(press.get("radius",0.08))*scale
		var strength: float=float(press.get("strength",1.0))
		var limit: float=float(press.get("max",0.06))*scale
		var pressers: Array=[]
		for name in press.get("parts",["hand_l","hand_r"]):
			var slot: int=Catalog.SLOTS.find(str(name))
			if slot>=0 and slot<samples[other].parts.size():pressers.append(Vector3(samples[other].parts[slot].center))
		var soft: Dictionary=recipes[i].get("soft",{})
		for kind in [["breast",2,"soft"],["butt",0,"soft_butt"]]:
			var config=soft.get(kind[0],{})
			if not config is Dictionary or config.is_empty():continue
			var part: Dictionary=samples[i].parts[kind[1]]
			var basis:=Basis(part.rotation)
			var anchor: Vector3=Library.vec(config.get("anchor",[0,0,0]))
			var lags: Array=(part.get(kind[2],[Vector3.ZERO,Vector3.ZERO]) as Array).duplicate()
			var pushed:=false
			for side in 2:
				var local:=Vector3(anchor.x*(1.0 if side==0 else -1.0),anchor.y,anchor.z)
				var center: Vector3=Vector3(part.center)+basis*(local*scale)
				var push:=Vector3.ZERO
				for point in pressers:
					var away: Vector3=center-point
					var distance: float=away.length()
					if distance<radius and distance>0.0001:push+=away/distance*(radius-distance)*strength
				if push.length()>limit:push=push.normalized()*limit
				if push!=Vector3.ZERO:pushed=true
				last_press["%s.%s_%s"%[ids[i],kind[0],"l" if side==0 else "r"]]=push.length()
				lags[side]=Vector3(lags[side])+basis.inverse()*push/scale
			if pushed or part.has(kind[2]):part[kind[2]]=lags

## 付属物の向き（docs/素材制作テンプレート/付属物の規格.md）。今は男性器（groin）だけ。
## actors[i].aim = {"slot": "groin", "leader": 相手のid, "leader_socket": "part:pelvis", "offset": [x,y,z], "insert": 0〜1, "insert_keys": [{t, insert}]}
##   付け根から狙いの点（相手の部位の中心＋部位ローカルの offset）へ向ける。insert は付け根からどこまで見せるか（焼いた半径の縦の比で描画へ渡る）。
## aim が無く actors[i].props.groin が "erect" なら、腰の前へ少し下向きに向ける。どちらも無ければ腰と同じ向き（下へ垂れる）。
func apply_aims(samples: Array,ids: Array,phase: float) -> void:
	var slot: int=Catalog.ALL_SLOTS.find("groin")
	for i in range(actors.size()):
		if slot>=samples[i].parts.size():continue
		var aim=scene.actors[i].get("aim")
		var props=scene.actors[i].get("props",{})
		var part: Dictionary=samples[i].parts[slot]
		var root: Vector3=part.center
		var basis:=Basis(part.rotation)
		var direction:=Vector3.ZERO
		var shown:=1.0
		if aim is Dictionary:
			var other: int=ids.find(str(aim.get("leader","")))
			if other<0:continue
			var socket: String=str(aim.get("leader_socket","part:pelvis")).trim_prefix("part:")
			var target_slot: int=Catalog.ALL_SLOTS.find(socket)
			if target_slot<0 or target_slot>=samples[other].parts.size():continue
			var target_part: Dictionary=samples[other].parts[target_slot]
			var offset: Vector3=Library.vec(aim.get("offset",[0,0,0]))*actors[other].body_scale
			var target: Vector3=Vector3(target_part.center)+Basis(target_part.rotation)*offset
			direction=target-root
			shown=aim_insert(aim,phase)
		elif props is Dictionary and str(props.get("groin",""))=="erect":
			direction=basis.z*0.94-basis.y*0.34
		if direction.length()<0.0001:continue
		# 絵は付け根（上端）から下へ伸びるので、枠の −Y を狙いへ向ける。
		var y:=-direction.normalized()
		var x:=basis.x-y*basis.x.dot(y)
		if x.length()<0.0001:x=basis.z.cross(y)
		x=x.normalized()
		part.rotation=Basis(x,y,x.cross(y)).get_rotation_quaternion().normalized()
		part.radii=Vector3(part.radii)*Vector3(1,clampf(shown,0.0,1.0),1)

static func aim_insert(aim: Dictionary,phase: float) -> float:
	var keys=aim.get("insert_keys",[])
	if not keys is Array or keys.is_empty():return float(aim.get("insert",1.0))
	if phase<=float(keys[0].t):return float(keys[0].insert)
	for k in range(keys.size()-1):
		var a: Dictionary=keys[k];var b: Dictionary=keys[k+1]
		if phase<=float(b.t):
			var u: float=clampf((phase-float(a.t))/maxf(float(b.t)-float(a.t),0.000001),0.0,1.0)
			u=u*u*(3.0-2.0*u)
			return lerpf(float(a.insert),float(b.insert),u)
	return float(keys[-1].insert)

func save(path: String) -> void:
	var value:=scene.duplicate(true)
	for i in range(actors.size()):
		value.actors[i].recipe=recipes[i]
		value.actors[i].root=[actors[i].root.x,actors[i].root.y,actors[i].root.z]
		value.actors[i].yaw=actors[i].world_yaw
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(value,"\t",true,true))

static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## 接点を時間で動かす。binding.offset_keys=[{t, offset:[x,y,z], ease?}, ...]（場面の位相 0〜1、昇順）。
## 位相に応じて offset を補間した binding の複製を返す。キーの ease はそのキーから次のキーまでの区間に効く（rig3d/library.gd の EASES）。
## 最初のキーより前・最後のキーより後はその端の値。周期で閉じるには t=0 と t=1 に同じ offset を置く。
static func timed_bindings(bindings: Array,phase: float) -> Array:
	var result: Array=[]
	for binding in bindings:
		if not binding is Dictionary or not binding.has("offset_keys"):result.append(binding);continue
		var copy: Dictionary=binding.duplicate(true)
		copy.offset=offset_at(binding.offset_keys,phase)
		result.append(copy)
	return result

static func offset_at(keys: Array,phase: float) -> Array:
	var t:=clampf(phase,0,1)
	if t<=float(keys[0].t):return keys[0].offset
	for i in range(1,keys.size()):
		if t<=float(keys[i].t):
			var a: Vector3=Library.vec(keys[i-1].offset);var b: Vector3=Library.vec(keys[i].offset)
			var f: float=Library.ease_value(str(keys[i-1].get("ease","smooth")),inverse_lerp(float(keys[i-1].t),float(keys[i].t),t))
			var v:=a.lerp(b,f)
			return [v.x,v.y,v.z]
	return keys[-1].offset

static func validate_offset_keys(keys: Variant) -> String:
	if not keys is Array or keys.size()<2:return "offset_keys は2個以上の配列"
	var previous:=-1.0
	for key in keys:
		if not key is Dictionary or not finite_number(key.get("t")) or float(key.t)<0 or float(key.t)>1 or float(key.t)<=previous:return "offset_keys の t は0〜1の昇順"
		var offset=key.get("offset")
		if not offset is Array or offset.size()!=3:return "offset_keys の offset は [x,y,z]"
		for v in offset:
			if not finite_number(v):return "offset_keys の offset は有限の数"
		if key.has("ease") and not str(key.ease) in Library.EASES:return "offset_keys の ease が不明: "+str(key.ease)
		previous=float(key.t)
	return ""

static func merge_fields(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged:=base.duplicate(true)
	for key in patch:
		if patch[key] is Dictionary and merged.get(key) is Dictionary:merged[key]=merge_fields(merged[key],patch[key])
		else:merged[key]=patch[key].duplicate(true) if patch[key] is Array or patch[key] is Dictionary else patch[key]
	return merged

func duration() -> float:
	if scene.has("duration"):return float(scene.duration)
	var seconds:=0.0
	for actor in actors:seconds=maxf(seconds,actor.duration())
	return maxf(seconds,0.001)

static func install_clips(library, definitions: Variant) -> Dictionary:
	if not definitions is Dictionary:return {"ok":false,"code":"CLIPS_FORMAT","path":"clips"}
	for id in definitions:
		var path: String="clips."+str(id)
		var definition=definitions[id]
		if not id is String or id.is_empty() or id in ["reach_cycle","twist_test","unseen","__external"]:return {"ok":false,"code":"CLIP_RESERVED_ID","path":path}
		if not definition is Dictionary or not definition.get("poses") is Dictionary or not definition.get("keys") is Array:return {"ok":false,"code":"CLIP_FORMAT","path":path}
		if not finite_number(definition.get("duration")) or definition.duration<=0:return {"ok":false,"code":"CLIP_DURATION","path":path}
		var pose_names: Dictionary={}
		for name in definition.poses:
			var patch=definition.poses[name]
			if not patch is Dictionary:return {"ok":false,"code":"POSE_FORMAT","path":path+".poses."+str(name)}
			var pose: Dictionary=patch.duplicate(true)
			var base: String=pose.get("base",definition.get("base",""))
			pose.erase("base")
			if not base.is_empty():
				if not library.poses.has(base):return {"ok":false,"code":"POSE_BASE_MISSING","path":path,"pose":base}
				pose=merge_fields(library.poses[base],pose)
			if not library.validate_pose(pose):return {"ok":false,"code":"POSE_INVALID","path":path+".poses."+str(name),"error":library.error}
			var internal: String="@scene/"+str(id)+"/"+str(name)
			library.poses[internal]=pose;pose_names[name]=internal
		if definition.keys.size()<2:return {"ok":false,"code":"CLIP_KEYS","path":path}
		var keys: Array=[];var previous:=-1.0;var support:=""
		for i in range(definition.keys.size()):
			var key=definition.keys[i]
			if not key is Dictionary or not finite_number(key.get("t")) or key.t<0 or key.t>1 or key.t<=previous or not pose_names.has(key.get("pose")):return {"ok":false,"code":"CLIP_KEY_INVALID","path":path+".keys["+str(i)+"]"}
			var current: String=library.poses[pose_names[key.pose]].support
			if not support.is_empty() and support!=current:return {"ok":false,"code":"CLIP_SUPPORT_CHANGE","path":path}
			if key.has("ease") and not str(key.ease) in Library.EASES:return {"ok":false,"code":"CLIP_KEY_EASE","path":path+".keys["+str(i)+"].ease","allowed":Library.EASES}
			var entry: Dictionary={"t":key.t,"pose":pose_names[key.pose]}
			if key.has("ease"):entry.ease=str(key.ease)
			support=current;previous=key.t;keys.append(entry)
		if keys[0].t!=0 or keys[-1].t!=1:return {"ok":false,"code":"CLIP_ENDPOINTS","path":path}
		library.clips[id]={"id":id,"name":definition.get("name",id),"duration":definition.duration,"keys":keys}
	return {"ok":true}
