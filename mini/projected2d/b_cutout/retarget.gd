extends RefCounted
const Solver=preload("res://mini/rig3d/solver.gd")
const Library=preload("res://mini/rig3d/library.gd")
var solver:=Solver.new()
## 写し先の体型での肩の位置。背骨の曲げ（solver.chest_basis）を含む。曲げが0なら
## hip+torso_basis*(肩幅, 胴−肩の下がり, 肩の奥行き) と同じ。
func target_shoulder(hip:Vector3,target:Dictionary,sign_value:float)->Vector3:
	var spine:Vector3=hip+solver.torso_basis*Vector3(0,target.torso*Solver.SPINE_BEND,0)
	return spine+solver.chest_basis*Vector3(sign_value*target.shoulder,target.torso*(1.0-Solver.SPINE_BEND)-float(target.get("shoulder_drop",.04)),float(target.get("shoulder_depth",0)))
func pose_for(pose:Dictionary,reference:Dictionary,target:Dictionary)->Dictionary:
	solver.solve(reference,pose)
	var out:=pose.duplicate(true)
	var old:Vector3=solver.joints.pelvis
	var leg:float=(target.thigh+target.shin)/(reference.thigh+reference.shin)
	var arm:float=(target.upper_arm+target.forearm)/(reference.upper_arm+reference.forearm)
	var width:float=target.hip_width/reference.hip_width
	var hip:=Vector3(old.x*width,.2+(old.y-.2)*(target.hip_height-.2)/(reference.hip_height-.2),old.z*leg)
	if pose.support!="feet":hip.y=.14+sqrt(maxf(.0001,target.thigh*target.thigh-hip.z*hip.z))
	var encoded:=hip
	if pose.support=="feet":encoded.y-=target.hip_height-2.06
	out.hip=[encoded.x,encoded.y,encoded.z]
	for side in ["l","r"]:
		var sign_value:=1.0 if side=="l" else -1.0
		var shoulder:Vector3=target_shoulder(hip,target,sign_value)
		var old_hand:=Library.vec(pose["hand_"+side])
		if pose.support=="knees" or str(pose.support).begins_with("half_kneel"):old_hand.y+=old.y-1.08
		var hand:Vector3=shoulder+(old_hand-solver.joints["shoulder_"+side])*arm
		if pose.support=="hands_knees":hand.y=.13
		if pose.support=="knees" or str(pose.support).begins_with("half_kneel"):hand.y-=hip.y-1.08
		out["hand_"+side]=[hand.x,hand.y,hand.z]
		var foot:=Library.vec(pose["foot_"+side]);foot.x*=width;foot.z*=leg;foot.y=.2+(foot.y-.2)*leg
		out["foot_"+side]=[foot.x,foot.y,foot.z]
	return out
func authoring_target(goal:String,target_position:Vector3,pose:Dictionary,reference:Dictionary,target:Dictionary)->Dictionary:
	# Inverse for wrist/ankle targets. Contact-prescribed coordinates are not invertible.
	solver.solve(reference,pose)
	var leg:float=(target.thigh+target.shin)/(reference.thigh+reference.shin)
	var arm:float=(target.upper_arm+target.forearm)/(reference.upper_arm+reference.forearm)
	var width:float=target.hip_width/reference.hip_width
	if goal in ["foot_l","foot_r"]:
		if pose.support!="feet" and (not str(pose.support).begins_with("half_kneel") or str(pose.support).ends_with(goal.right(1))):return {"ok":false,"error":"Ankle targets are fixed by knee support"}
		var foot:=Vector3(target_position.x/width,.2+(target_position.y-.2)/leg,target_position.z/leg)
		return {"ok":true,"value":[foot.x,foot.y,foot.z],"space":"authoring","goal":goal}
	if goal not in ["hand_l","hand_r"]:return {"ok":false,"error":"Supported authoring targets: hand_l/r (wrist), foot_l/r (ankle)"}
	if pose.support=="hands_knees" and absf(target_position.y-.13)>.0001:
		return {"ok":false,"error":"Palm support fixes wrist height at 0.13; use solver overrides to intentionally override support"}
	var old:Vector3=solver.joints.pelvis
	var hip:=Vector3(old.x*width,.2+(old.y-.2)*(target.hip_height-.2)/(reference.hip_height-.2),old.z*leg)
	if pose.support!="feet":hip.y=.14+sqrt(maxf(.0001,target.thigh*target.thigh-hip.z*hip.z))
	var side:=goal.right(1);var sign_value:=1.0 if side=="l" else -1.0
	var shoulder:Vector3=target_shoulder(hip,target,sign_value)
	var hand:Vector3=solver.joints["shoulder_"+side]+(target_position-shoulder)/arm
	if pose.support=="knees" or str(pose.support).begins_with("half_kneel"):hand.y-=old.y-1.08
	if pose.support=="hands_knees":hand.y=float(pose[goal][1])
	return {"ok":true,"value":[hand.x,hand.y,hand.z],"space":"authoring","goal":goal}
