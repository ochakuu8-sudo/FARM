extends RefCounted
## Position-only socket constraints. One-way leader -> follower, no whole-body physics.
## 手首・足首（hand_*/foot_*）に加えて、肘・膝（elbow_*/knee_*）を目標にできる。肘・膝は曲げる向きで近づける。
const BEND_GOALS=["elbow_l","elbow_r","knee_l","knee_r"]
func vector(value)->Dictionary:
	if value is Vector3 and value.is_finite():return {"ok":true,"value":value}
	if value is Array and value.size()==3:
		for v in value:
			if not (v is int or v is float) or not is_finite(float(v)):return {"ok":false}
		return {"ok":true,"value":Vector3(value[0],value[1],value[2])}
	return {"ok":false}
func solve(leader,follower,bindings:Array,placement:Dictionary={})->Dictionary:
	if leader==follower:return {"error":"Leader and follower must be different actors","parts":[]}
	var leader_parts:Array=leader.evaluate().duplicate(true)
	var old_root:Vector3=follower.root
	var old_goals:Dictionary=follower.goal_overrides.duplicate(true)
	if not placement.is_empty():
		for key in ["leader_socket","space"]:
			if placement.has(key) and not placement[key] is String:return {"error":"Placement "+key+" must be a string","parts":[]}
		var anchor:Dictionary=leader.socket_position(str(placement.get("leader_socket","joint:pelvis")),leader_parts)
		var offset:=vector(placement.get("offset",Vector3.ZERO))
		if not anchor.ok or not offset.ok:return {"error":"Invalid root placement socket/offset","parts":[]}
		var shift:Vector3=offset.value
		var space:String=placement.get("space","leader_local")
		if space=="leader_local":shift=leader.solver_to_world(shift)-leader.root
		elif space!="world":return {"error":"Unknown placement space","parts":[]}
		follower.root=anchor.position+shift
	follower.goal_overrides.clear()
	var current:Array=follower.evaluate()
	var targets:Dictionary={};var sockets:Dictionary={};var requested:Dictionary={};var tolerances:Dictionary={};var soft_goals:Dictionary={}
	var error:=""
	for binding in bindings:
		if not binding is Dictionary:error="Binding must be an object";break
		for key in ["follower_goal","leader_socket","leader_part","offset_space","follower_socket"]:
			if binding.has(key) and not binding[key] is String:error="Binding "+key+" must be a string";break
		if not error.is_empty():break
		var goal:String=binding.get("follower_goal","")
		if targets.has(goal):error="Duplicate follower goal: "+goal;break
		if goal in BEND_GOALS:
			# 肘・膝の目標：曲げる向きを目標点へ向ける。手首・足首の目標と一緒に解くので、
			# 肘（膝）が通れる円の上で目標に最も近い点になる。tolerance（world、既定0.03）までの差は許す。
			if goal.begins_with("knee") and follower.solver.control.support!="feet":error="Knee goal needs support=feet: "+goal;break
			var bend_anchor:Dictionary=leader.socket_position(binding.get("leader_socket","part:"+str(binding.get("leader_part",""))),leader_parts)
			var bend_offset:=vector(binding.get("offset",Vector3.ZERO))
			if not bend_anchor.ok or not bend_offset.ok:error="Invalid leader socket/offset for "+goal;break
			var bend_delta:Vector3=bend_offset.value
			if binding.get("offset_space","world")=="leader_local":bend_delta=leader.solver_to_world(bend_delta)-leader.root
			var bend_target:Vector3=bend_anchor.position+bend_delta
			targets[goal]=bend_target;sockets[goal]="joint:"+goal;requested[goal]=follower.world_to_solver(bend_target)
			tolerances[goal]=maxf(0.0,float(binding.get("tolerance",0.03)))
			if not bool(binding.get("strict",false)):soft_goals[goal]=true
			continue
		var anchor_name:String=binding.get("leader_socket","part:"+str(binding.get("leader_part","")))
		var anchor:Dictionary=leader.socket_position(anchor_name,leader_parts)
		var offset:=vector(binding.get("offset",Vector3.ZERO))
		if not anchor.ok or not offset.ok:error="Invalid leader socket/offset: "+anchor_name;break
		var delta:Vector3=offset.value
		var space:String=binding.get("offset_space","world")
		if space=="leader_local":delta=leader.solver_to_world(delta)-leader.root
		elif space!="world":error="Unknown binding offset_space";break
		var socket:String=binding.get("follower_socket",("part:"+goal if goal.begins_with("hand") else "sole_"+goal.right(1)))
		var target:Vector3=anchor.position+delta
		var converted:Dictionary=follower.target_for_socket(goal,socket,target,current)
		if not converted.ok:error=converted.error;break
		targets[goal]=target;sockets[goal]=converted.socket;requested[goal]=converted.target
	if not error.is_empty():
		follower.root=old_root;follower.goal_overrides=old_goals;follower.evaluate()
		return {"error":error,"parts":[]}
	follower.goal_overrides=requested
	var follower_parts:Array=follower.evaluate().duplicate(true)
	# A hand center rotates around its wrist. Recompute this offset after every IK
	# solve; a single conversion leaves a fixed residual even for reachable targets.
	var iterations:=0
	for iteration in range(48):
		var maximum:=0.0
		var next:Dictionary=requested.duplicate(true)
		for goal in targets:
			if goal in BEND_GOALS:continue
			var point:Dictionary=follower.socket_position(sockets[goal],follower_parts)
			maximum=maxf(maximum,Vector3(point.position).distance_to(targets[goal]))
			var converted:Dictionary=follower.target_for_socket(goal,sockets[goal],targets[goal],follower_parts)
			if not converted.ok:continue
			next[goal]=Vector3(requested[goal]).lerp(converted.target,0.8)
		if maximum<=0.00001:break
		requested=next;follower.goal_overrides=requested
		follower_parts=follower.evaluate().duplicate(true)
		iterations=iteration+1
	var residuals:Dictionary={};var local_residuals:Dictionary={};var warnings:Array=[];var bend:Dictionary={}
	for goal in targets:
		var point:Dictionary=follower.socket_position(sockets[goal],follower_parts)
		var distance:float=Vector3(point.position).distance_to(targets[goal])
		# 肘・膝の目標は既定で「寄せる目安」。届かなくても判定を落とさず、距離（許容差を引いたもの）を bend に返す。
		# strict=true のものだけ接触の残差に入れる。
		if soft_goals.has(goal):bend[goal]=maxf(0.0,distance-tolerances[goal]);continue
		residuals[goal]=distance
		if tolerances.has(goal):residuals[goal]=maxf(0.0,residuals[goal]-tolerances[goal])
		local_residuals[goal]=residuals[goal]/follower.render_scale()
		if local_residuals[goal]>.0001:warnings.append({"goal":goal,"reason":"unreachable_or_unsatisfied","residual_solver":local_residuals[goal]})
	return {"leader":leader_parts,"follower":follower_parts,"residuals":residuals,"bend":bend,"residuals_solver":local_residuals,"targets_world":targets,"goals_solver":requested,"warnings":warnings,"iterations":iterations,"space":"render_world"}
