extends RefCounted
const Compiler = preload("res://mini/layered2d/prepare/motion_compiler.gd")
const Catalog = preload("res://mini/layered2d/data/catalog.gd")
const LayerCompiler = preload("res://mini/layered2d/prepare/layer_compiler.gd")

## contact_limit は接触の残差の上限（world）。確認用の下見だけは大きくして、合わない場面も絵にできる。
func compile(session, duration: float = -1.0, tolerance: float = 0.009, max_sample_rate: float = 96.0, contact_limit: float = 0.005) -> Dictionary:
	max_sample_rate=clampf(max_sample_rate,96.0,192.0)
	if duration<=0:duration=session.duration()
	var secondary:Dictionary=session.prepare_secondary(true)
	if not secondary.ok:return secondary
	var times: Array[float]=[]
	for i in range(ceili(duration*24)+1):times.append(float(i)/ceili(duration*24))
	for actor_id in range(session.actors.size()):
		var actor=session.actors[actor_id]
		var offset:float=session.scene.actors[actor_id].get("phase_offset",0.0)
		if offset>0 and offset<1 and not times.has(offset):times.append(offset)
		for key in actor.library.clips.get(actor.clip,{}).get("keys",[]):
			var key_time:float=float(key.t) if offset==0 or offset==1 else fposmod(float(key.t)+offset,1.0)
			if not times.has(key_time):times.append(key_time)
	# 接点のキー（offset_keys）の時刻も必ず標本に入れる。
	for group in session.scene.get("constraints",[]):
		for binding in group.get("bindings",[]):
			for key in (binding.get("offset_keys",[]) if binding is Dictionary else []):
				if not times.has(float(key.t)):times.append(float(key.t))
	for rule in session.scene.get("layer_rules",[]):
		for field in ["start","end"]:
			var value: float=rule.get(field,0.0 if field=="start" else 1.0)
			if not times.has(value):times.append(value)
	times.sort()
	var samples: Dictionary={}
	var failures: Array=[]
	var max_error:=0.0
	var max_contact:=0.0
	for t in times:
		samples[t]=session.evaluate(t)
		if not samples[t].ok:return samples[t]
	var index:=0
	while index<times.size()-1:
		var a:=times[index];var b:=times[index+1]
		var error:=0.0
		for f in [0.25,0.5,0.75]:
			var t: float=lerpf(a,b,f)
			if not samples.has(t):samples[t]=session.evaluate(t)
			if not samples[t].ok:return samples[t]
			for id in range(session.actors.size()):
				var comparison:=Compiler.compare(samples[a].snapshots[id],samples[b].snapshots[id],samples[t].snapshots[id],f)
				error=maxf(error,comparison.error)
				if comparison.error>tolerance and (b-a)*duration<=1.0/max_sample_rate+0.000001:
					comparison.actor=id;comparison.interval=[a*duration,b*duration];comparison.phase=t;comparison.actor_phase=session.actor_phase(id,t);comparison.limit_world=tolerance
					failures.append(comparison)
		if error>tolerance and (b-a)*duration>1.0/max_sample_rate+0.000001:
			times.insert(index+1,(a+b)*0.5);continue
		max_error=maxf(max_error,error);index+=1
	# Include exact keys and endpoints, not only the interpolation probes.
	var worst:Dictionary={}
	for phase in samples:
		for group in samples[phase].contact_residuals_world:
			for goal in samples[phase].contact_residuals_world[group]:
				var residual:float=samples[phase].contact_residuals_world[group][goal]
				if residual>max_contact:max_contact=residual;worst={"group":group,"goal":goal,"phase":phase}
	# 肘・膝の目標（寄せる目安）は判定に入れず、最大の外れだけ返す。
	var max_bend:=0.0;var worst_bend:Dictionary={}
	for phase in samples:
		var bends:Dictionary=samples[phase].get("bend_residuals_world",{})
		for group in bends:
			for goal in bends[group]:
				if float(bends[group][goal])>max_bend:max_bend=float(bends[group][goal]);worst_bend={"group":group,"goal":goal,"phase":phase}
	if max_contact>contact_limit:return {"ok":false,"code":"CONTACT_RESIDUAL_EXCEEDED","max_world":max_contact,"limit":contact_limit,"worst":worst}
	if not failures.is_empty():return {"ok":false,"code":"INTERPOLATION_ERROR_LIMIT","details":failures.slice(0,32),"count":failures.size()}
	var tracks: Array=[]
	for id in range(session.actors.size()):
		var actor=session.actors[id]
		var original_clip: String=actor.clip
		var original_goals: Dictionary=actor.goal_overrides.duplicate(true)
		actor.goal_overrides={};actor.clip="idle"
		var rest: Array=[]
		for p in actor.sample(0).parts:rest.append(p.radii/actor.body_scale)
		actor.clip=original_clip;actor.goal_overrides=original_goals
		var frames: Array=[];var members: Array=[]
		for t in times:frames.append(samples[t].snapshots[id]);members.append(samples[t].members[id])
		var orders: Array=[]
		for direction in range(8):
			var plans: Array=[]
			for f in frames:plans.append(PackedInt32Array(range(Catalog.ALL_SLOTS.size())))
			orders.append(plans)
		tracks.append({"ok":true,"key":Catalog.fingerprint([Compiler.VERSION,session.scene,id,times]),"clip":"scene","duration":duration,"times":PackedFloat32Array(times),"frames":frames,"rest_radii":rest,"orders":orders,"members":members,"max_playback_speed":1.9})
		tracks[-1].face_timeline=session.face_timelines[id].duplicate(true)
		tracks[-1].face_phase_offset=float(session.scene.actors[id].get("phase_offset",0.0))
		if id<session.outfit_timelines.size() and not session.outfit_timelines[id].is_empty():tracks[-1].outfit_timeline=session.outfit_timelines[id].duplicate(true)
	var group_orders: Array=[]
	var slot_names: Array=[]
	for id in range(tracks.size()):
		for slot in Catalog.ALL_SLOTS:slot_names.append(str(session.scene.actors[id].get("id","actor_"+str(id)))+"."+slot)
	for direction in range(8):
		var yaw:=deg_to_rad(direction*45.0)
		var view:=Vector3(sin(yaw)*cos(PI/12),sin(PI/12),cos(yaw)*cos(PI/12))
		var plans: Array=[]
		for t in times:
			var depth: Array=[]
			for id in range(tracks.size()):
				var member: Dictionary=samples[t].members[id]
				for slot in range(samples[t].snapshots[id].parts.size()):
					var position: Vector3=Basis(Vector3.UP,deg_to_rad(member.yaw))*samples[t].snapshots[id].parts[slot].center*member.height+member.root
					var local_view:Vector3=Basis(Vector3.UP,deg_to_rad(-member.yaw))*view
					depth.append({"actor":id,"slot":slot,"depth":LayerCompiler.depth(slot,samples[t].snapshots[id].parts,local_view)*member.height+Vector3(member.root).dot(view)})
			depth.sort_custom(func(a,b):return a.depth<b.depth if absf(a.depth-b.depth)>0.000001 else a.actor*32+a.slot<b.actor*32+b.slot)
			var base: Array=[];var indexed: Dictionary={}
			for part in depth:
				var id: int=part.actor*Catalog.ALL_SLOTS.size()+part.slot
				base.append(id);indexed[id]=part
			var resolved:=LayerCompiler.resolve(base,slot_names,session.scene.get("layer_rules",[]),t,direction)
			if not resolved.ok:return resolved
			var final_order: Array=[]
			for id in resolved.order:final_order.append(indexed[id])
			plans.append(final_order)
		group_orders.append(plans)
	return {"ok":true,"tracks":tracks,"orders":group_orders,"max_error_world":max_error,"max_contact_world":max_contact,"worst_contact":worst,"max_bend_world":max_bend,"worst_bend":worst_bend,"secondary":session.secondary_diagnostic,"times":PackedFloat32Array(times)}
