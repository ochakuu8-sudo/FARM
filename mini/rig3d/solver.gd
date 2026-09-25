extends RefCounted
const Library=preload("res://mini/rig3d/library.gd")
var joints: Dictionary={}
var contacts: Dictionary={}
var goals: Dictionary={}
var directions: Dictionary={}
var diagnostics: Dictionary={}
var torso_basis:=Basis.IDENTITY
## 胸から上の向き。torso_basis に背骨の曲げ（spine_pitch / spine_roll）を足したもの。曲げが0なら torso_basis と同じ。
var chest_basis:=Basis.IDENTITY
## 背骨を曲げる位置（腰から胸までの割合）。
const SPINE_BEND:=0.45
## 肘・膝の目標に、姿勢の pole をどれだけ混ぜるか（肢の長さに対する割合）。
const BEND_BLEND:=0.35
var pelvis_basis:=Basis.IDENTITY
var head_basis:=Basis.IDENTITY
var profile: Dictionary={}
var control: Dictionary={}
var overrides: Dictionary={}
var error:=""
var warnings:Array[String]=[]
static func two_bone(start: Vector3,target: Vector3,a: float,b: float,pole: Vector3) -> Dictionary:
 var delta:=target-start
 var distance:=delta.length()
 var axis:=delta/distance if distance>.00001 else Vector3.DOWN
 var d:=clampf(distance,absf(a-b)+.00001,a+b-.00001)
 var bend:=pole-axis*pole.dot(axis)
 var fallback_used:=bend.length_squared()<.000001
 if bend.length_squared()<.000001:
  var fallback:=Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD))<.9 else Vector3.RIGHT
  bend=fallback-axis*fallback.dot(axis)
 bend=bend.normalized()
 var along:=(a*a-b*b+d*d)/(2*d)
 var height:=sqrt(maxf(0,a*a-along*along))
 var end:=start+axis*d
 return {"mid":start+axis*along+bend*height,"end":end,"error":end.distance_to(target),"pole_fallback":fallback_used}
func solve(p: Dictionary,pose: Dictionary) -> void:
 profile=p;control=pose.duplicate(true)
 joints.clear();contacts.clear();goals.clear();directions.clear();diagnostics.clear()
 warnings.clear()
 var u: float=p.head
 var hip: Vector3=Library.vec(pose.hip)*u
 var support: String=pose.support
 if support=="feet": hip.y+=p.hip_height-2.06*u
 else:
  var horizontal: float=hip.z
  hip.y=.14*u+sqrt(maxf(.0001,p.thigh*p.thigh-horizontal*horizontal))
 torso_basis=Basis(Vector3.UP,deg_to_rad(pose.twist))*Basis(Vector3.RIGHT,deg_to_rad(pose.lean))
 pelvis_basis=Basis.from_euler(Vector3(deg_to_rad(pose.get("pelvis_pitch",pose.lean*.35)),deg_to_rad(pose.get("pelvis_yaw",pose.twist*.15)),deg_to_rad(pose.get("pelvis_roll",0))))
 chest_basis=torso_basis*Basis(Vector3.RIGHT,deg_to_rad(float(pose.get("spine_pitch",0.0))))*Basis(Vector3.BACK,deg_to_rad(float(pose.get("spine_roll",0.0))))
 head_basis=chest_basis*Basis(Vector3.RIGHT,deg_to_rad(pose.head_pitch))*Basis(Vector3.UP,deg_to_rad(pose.head_yaw))
 var spine: Vector3=hip+torso_basis*Vector3(0,p.torso*SPINE_BEND,0)
 var chest: Vector3=spine+chest_basis*Vector3(0,p.torso*(1.0-SPINE_BEND),0)
 joints.root=Vector3.ZERO;joints.pelvis=hip;joints.spine=spine;joints.chest=chest
 joints.neck=chest+chest_basis*Vector3(0,p.neck,0)
 # Head's rest center is independent of the rig's global head-unit scale.
 joints.head=joints.neck+head_basis*Vector3(0,p.get("head_center_height",.5*u),0)
 for side in ["l","r"]:
  var sign_value:=1.0 if side=="l" else -1.0
  var shoulder: Vector3=chest+chest_basis*Vector3(sign_value*p.shoulder,-float(p.get("shoulder_drop",.04))*u,float(p.get("shoulder_depth",0)))
  joints["shoulder_"+side]=shoulder
  var hand: Vector3=Library.vec(pose["hand_"+side])*u
  if support=="knees" or support.begins_with("half_kneel"): hand.y+=(hip.y-1.08*u)
  if overrides.has("hand_"+side): hand=overrides["hand_"+side]
  # 肘の目標（overrides.elbow_*、solver 空間の点）があれば、曲げる向きをそこへ向ける。
  # 目標が腕の軸の近くを通ると曲げる向きが反転するので、姿勢の pole を少し混ぜて連続にする。
  var arm_pole: Vector3=Library.vec(pose["pole_arm_"+side])
  if overrides.has("elbow_"+side):arm_pole=overrides["elbow_"+side]-shoulder+arm_pole.normalized()*p.upper_arm*BEND_BLEND
  var arm:=two_bone(shoulder,hand,p.upper_arm,p.forearm,arm_pole)
  if arm.pole_fallback:warnings.append("pole_arm_"+side+": limb axis parallel to pole; deterministic fallback")
  joints["elbow_"+side]=arm.mid;joints["wrist_"+side]=arm.end
  directions["hand_"+side]=Library.vec(pose["hand_dir_"+side]).normalized()
  joints["hand_"+side]=arm.end+directions["hand_"+side]*.15*u
  goals["hand_"+side]=hand
  diagnostics["arm_"+side]=arm.error
  if support=="hands_knees": contacts["palm_"+side]=Vector3(hand.x,0,hand.z+.14*u)
  var leg_start: Vector3=hip+pelvis_basis*Vector3(sign_value*p.hip_width,0,0)
  joints["hip_"+side]=leg_start
  if support=="feet" or (support.begins_with("half_kneel") and not support.ends_with(side)):
   var foot: Vector3=Library.vec(pose["foot_"+side])*u
   if overrides.has("foot_"+side): foot=overrides["foot_"+side]
   var leg_pole: Vector3=Library.vec(pose.get("pole_leg_"+side,[0,0,1]))
   if overrides.has("knee_"+side):leg_pole=overrides["knee_"+side]-leg_start+leg_pole.normalized()*p.thigh*BEND_BLEND
   var leg:=two_bone(leg_start,foot,p.thigh,p.shin,leg_pole)
   if leg.pole_fallback:warnings.append("pole_leg_"+side+": limb axis parallel to pole; deterministic fallback")
   joints["knee_"+side]=leg.mid;joints["ankle_"+side]=leg.end
   goals["foot_"+side]=foot;diagnostics["leg_"+side]=leg.error
   if absf(foot.y-.20*u)<.0001: contacts["sole_"+side]=Vector3(foot.x,0,foot.z)
  else:
   var knee:=Vector3(sign_value*p.hip_width,.14*u,0)
   joints["knee_"+side]=knee
   joints["ankle_"+side]=knee+Vector3(0,.06*u,-sqrt(maxf(.001,p.shin*p.shin-.0036*u*u)))
   contacts["knee_"+side]=knee-Vector3(0,.14*u,0)
   diagnostics["leg_"+side]=absf(leg_start.distance_to(knee)-p.thigh)
  joints["foot_"+side]=joints["ankle_"+side]+Vector3(0,-.20*u,.12*u)
 var contact_error:=0.0
 for key in contacts:
  var actual: Vector3
  if key.begins_with("sole"): actual=joints["ankle_"+key.right(1)]-Vector3(0,.20*u,0)
  elif key.begins_with("knee"): actual=joints[key]-Vector3(0,.14*u,0)
  else: actual=joints["wrist_"+key.right(1)]+Vector3(0,-.13*u,.14*u)
  contact_error=maxf(contact_error,actual.distance_to(contacts[key]))
 diagnostics.contact=contact_error
## 腰（0）から胸（1）までの背骨上の点。曲げの位置より上は胸の向きで進む。
## 曲げが0なら joints.pelvis.lerp(joints.chest, f) と同じ。
func torso_point(f: float) -> Vector3:
 var hip: Vector3=joints.pelvis
 if f<=SPINE_BEND: return hip+torso_basis*Vector3(0,profile.torso*f,0)
 return joints.spine+chest_basis*Vector3(0,profile.torso*(f-SPINE_BEND),0)
func maximum_error() -> float:
 var value:=0.0
 for n in diagnostics.values(): value=maxf(value,float(n))
 return value
