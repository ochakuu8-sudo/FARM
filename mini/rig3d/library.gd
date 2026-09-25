extends RefCounted
const CHARACTER_PATH="res://mini/rig3d/data/characters.json"
const MOTION_PATH="res://mini/rig3d/data/motions.json"
const VECTORS=["hip","hand_l","hand_r","foot_l","foot_r","pole_arm_l","pole_arm_r","hand_dir_l","hand_dir_r","pole_leg_l","pole_leg_r"]
const OPTIONAL_VECTORS={"pole_leg_l":[0,0,1],"pole_leg_r":[0,0,1]}
const ANGLES=["lean","twist","head_pitch","head_yaw"]
const JOINT_VECTORS={"wrist_l":[0,0,0],"wrist_r":[0,0,0],"palm_normal_l":[0,0,1],"palm_normal_r":[0,0,1]}
## spine_pitch / spine_roll：背骨の曲げ（度）。胸から上を腹に対して曲げる。pitch は正で前へ丸め、負で反る。
const JOINT_NUMBERS={"hand_follow_l":0.0,"hand_follow_r":0.0,"pelvis_roll":0.0,"spine_pitch":0.0,"spine_roll":0.0}
var profiles: Dictionary={}
var poses: Dictionary={}
var clips: Dictionary={}
var error:=""
func number(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))
func vector(v: Variant) -> bool:
 return v is Array and v.size()==3 and number(v[0]) and number(v[1]) and number(v[2])
func fail(message: String) -> bool:
 error=message
 return false
func load_files(a: String=CHARACTER_PATH,b: String=MOTION_PATH) -> bool:
 return load_data(JSON.parse_string(FileAccess.get_file_as_string(a)),JSON.parse_string(FileAccess.get_file_as_string(b)))
func load_data(a: Variant,b: Variant) -> bool:
 if not a is Dictionary or not b is Dictionary: return fail("JSONのルートが不正です")
 if a.get("version")!=1 or b.get("version")!=1: return fail("version=1 が必要です")
 if not a.get("characters") is Array or not b.get("poses") is Dictionary or not b.get("clips") is Array: return fail("characters / poses / clips が必要です")
 var pc: Dictionary={}
 var cc: Dictionary={}
 for p in a.characters:
  if not p is Dictionary or not p.get("id") is String or not p.get("name") is String: return fail("キャラのID・名前が不正です")
  if p.id.is_empty() or pc.has(p.id): return fail("キャラIDが空か重複しています")
  for key in ["head","hip_height","torso","neck","thigh","shin","upper_arm","forearm","shoulder","hip_width"]:
   if not number(p.get(key)) or p[key]<=0: return fail("寸法は正の有限数です: "+key)
  if absf(p.hip_height+p.torso+p.neck-3*p.head)>.001: return fail("基準の立位は4頭身が必要です")
  for key in ["coat","pants","skin","hair"]:
   if not p.get(key) is String or not Color.html_is_valid(p[key]): return fail("色が不正です: "+key)
  pc[p.id]=p.duplicate(true)
 for id in b.poses:
  if not validate_pose(b.poses[id]): return false
 for c in b.clips:
  if not c is Dictionary or not c.get("id") is String or not c.get("name") is String: return fail("動作のID・名前が不正です")
  if c.id.is_empty() or cc.has(c.id): return fail("動作IDが空か重複しています")
  if not number(c.get("duration")) or c.duration<=0: return fail("duration は正の数です")
  if not c.get("keys") is Array or c.keys.size()<2: return fail("キーが2個以上必要です")
  if c.has("seat") and not c.seat is bool: return fail("seat は真偽値です")
  var previous:=-1.0
  var support:=""
  for k in c.keys:
   if not k is Dictionary or not number(k.get("t")) or not b.poses.has(k.get("pose")): return fail("キー参照が不正です")
   if k.t<=previous or k.t<0 or k.t>1: return fail("キーは0〜1の昇順です")
   previous=k.t
   var current: String=b.poses[k.pose].support
   if not support.is_empty() and support!=current: return fail("接地方式をまたぐ動作は接触の持ち替え設計が必要です")
   support=current
  if c.keys[0].t!=0 or c.keys[-1].t!=1: return fail("キーは0から1まで必要です")
  cc[c.id]=c.duplicate(true)
 if pc.is_empty() or cc.is_empty(): return fail("キャラと動作が必要です")
 profiles=pc;poses=b.poses.duplicate(true);clips=cc;error=""
 return true
func validate_pose(p: Variant) -> bool:
 if not p is Dictionary: return fail("姿勢はオブジェクトです")
 for key in p:
  if key not in VECTORS and key not in ANGLES and key!="support" and key not in JOINT_VECTORS and key not in JOINT_NUMBERS and key not in ["pelvis_pitch","pelvis_yaw"]: return fail("未知の姿勢項目: "+str(key))
 for key in JOINT_VECTORS:
  if p.has(key) and not vector(p[key]):return fail("関節ベクトルが不正: "+key)
  if key.begins_with("palm_normal") and p.has(key) and vec(p[key]).length()<0.001:return fail("掌の法線がゼロ: "+key)
 for key in ["hand_follow_l","hand_follow_r","pelvis_pitch","pelvis_yaw","pelvis_roll","spine_pitch","spine_roll"]:
  if p.has(key) and not number(p[key]):return fail("関節角度が不正: "+key)
  if key.begins_with("hand_follow") and (p.get(key,0)<0 or p.get(key,0)>1):return fail("追従量は0〜1: "+key)
 for key in VECTORS:
  var value=p.get(key,OPTIONAL_VECTORS.get(key))
  if not vector(value): return fail("3D座標が不正です: "+key)
  if key.begins_with("pole_") or key.begins_with("hand_dir"):
   if vec(value).length()<.001: return fail("向きがゼロです: "+key)
 for key in ANGLES:
  if not number(p.get(key)): return fail("角度が不正です: "+key)
 if p.get("support") not in ["feet","knees","hands_knees","half_kneel_l","half_kneel_r"]: return fail("接地方式が不正です")
 return true
static func vec(v: Array) -> Vector3: return Vector3(v[0],v[1],v[2])
static func mix(a: Dictionary,b: Dictionary,t: float) -> Dictionary:
 var result: Dictionary={"support":b.support}
 for key in VECTORS:
  var av:=vec(a.get(key,OPTIONAL_VECTORS.get(key)))
  var bv:=vec(b.get(key,OPTIONAL_VECTORS.get(key)))
  var v:=av.lerp(bv,t)
  if key.begins_with("pole_") and av.normalized().dot(bv.normalized())<-.99999:
   # Deterministic great-circle fallback for opposite poles, never a zero pole.
   var axis:=av.normalized().cross(Vector3.UP)
   if axis.length_squared()<.000001:axis=av.normalized().cross(Vector3.RIGHT)
   v=av.normalized().rotated(axis.normalized(),PI*t)*lerpf(av.length(),bv.length(),t)
  result[key]=[v.x,v.y,v.z]
 for key in ANGLES: result[key]=lerpf(float(a[key]),float(b[key]),t)
 for key in JOINT_VECTORS:
  var av:=vec(a.get(key,JOINT_VECTORS[key]));var bv:=vec(b.get(key,JOINT_VECTORS[key]))
  var value:Vector3
  if key.begins_with("wrist"):
   value=Basis.from_euler(av*PI/180).get_rotation_quaternion().slerp(Basis.from_euler(bv*PI/180).get_rotation_quaternion(),t).get_euler()*180/PI
  else:
   if av.normalized().dot(bv.normalized())<-.999:
    var axis:=av.normalized().cross(Vector3.UP)
    if axis.length_squared()<.0001:axis=av.normalized().cross(Vector3.RIGHT)
    value=av.normalized().rotated(axis.normalized(),PI*t)
   else:value=av.lerp(bv,t).normalized()
  result[key]=[value.x,value.y,value.z]
 for key in JOINT_NUMBERS:result[key]=lerpf(a.get(key,JOINT_NUMBERS[key]),b.get(key,JOINT_NUMBERS[key]),t)
 result.pelvis_pitch=lerpf(a.get("pelvis_pitch",a.lean*.35),b.get("pelvis_pitch",b.lean*.35),t)
 result.pelvis_yaw=lerpf(a.get("pelvis_yaw",a.twist*.15),b.get("pelvis_yaw",b.twist*.15),t)
 return result
func sample(id: String,phase: float) -> Dictionary:
 var keys: Array=clips[id].keys
 var t:=clampf(phase,0,1)
 for i in range(1,keys.size()):
  if t<=keys[i].t:
   var k0: Dictionary=keys[i-1]
   var k1: Dictionary=keys[i]
   return mix(poses[k0.pose],poses[k1.pose],ease_value(str(k0.get("ease","smooth")),inverse_lerp(k0.t,k1.t,t)))
 return poses[keys[-1].pose].duplicate(true)
## キーから次のキーまでの進み方。キーの ease がその区間に効く。
##   smooth 既定。ゆっくり出てゆっくり着く    linear 等速
##   in     ゆっくり出て速く着く（突き込み・叩きつけ）  out  速く出てゆっくり着く（引き・反動）
##   sharp  in より急（着く直前に一気に加速）  soft  smooth より出だしと着きが長い
const EASES=["smooth","linear","in","out","sharp","soft"]
static func ease_value(kind: String,f: float) -> float:
 f=clampf(f,0,1)
 match kind:
  "linear": return f
  "in": return f*f
  "out": return 1-(1-f)*(1-f)
  "sharp": return f*f*f
  "soft": return f*f*f*(f*(f*6-15)+10)
 return smoothstep(0,1,f)
