extends RefCounted
## Preparation-only damped tracking. The periodic initial state is solved directly
## from the discrete spring's one-cycle affine map; seeking never integrates time.
const PARTS=["head","chest","abdomen","pelvis","breast_l","breast_r","butt_l","butt_r"]
## 胸・尻の左右は描画部位ではない。親の部位（胸・骨盤）に固定した点（anchor、親のローカル座標）の遅れを求め、
## 親の画像の中の領域を変形する量として使う（resource_store / cutout.gdshader）。
const SOFT_PARTS=["breast_l","breast_r","butt_l","butt_r"]
## 種類 → 親の描画スロット（胸=2、骨盤=0）
const SOFT_KINDS={"breast":2,"butt":0}
static func soft_slot(part:String)->int:
	return SOFT_KINDS[part.substr(0,part.length()-2)]
const HZ=120.0

static func validate(value:Variant)->Dictionary:
	if not value is Dictionary:return {"ok":false,"code":"SECONDARY_FORMAT"}
	for part in value:
		if part not in PARTS:return {"ok":false,"code":"SECONDARY_PART_UNAVAILABLE","part":part,"supported":PARTS}
		var entry=value[part]
		if not entry is Dictionary:return {"ok":false,"code":"SECONDARY_FORMAT","part":part}
		for field in entry:
			if field not in ["lag","damping","amount","max_offset","loop","anchor"]:return {"ok":false,"code":"SECONDARY_FIELD","part":part,"field":field}
		for field in ["lag","damping","amount","max_offset"]:
			var n=entry.get(field,{"lag":0.12,"damping":0.7,"amount":1.0,"max_offset":0.04}[field])
			if not (n is float or n is int) or not is_finite(float(n)):return {"ok":false,"code":"SECONDARY_NUMBER","part":part,"field":field}
		if entry.get("lag",0.12)<0 or entry.get("lag",0.12)>1 or entry.get("damping",0.7)<0.05 or entry.get("damping",0.7)>3 or entry.get("amount",1.0)<0 or entry.get("amount",1.0)>2 or entry.get("max_offset",0.04)<0 or entry.get("max_offset",0.04)>0.15:return {"ok":false,"code":"SECONDARY_RANGE","part":part}
		if not entry.get("loop",true) is bool:return {"ok":false,"code":"SECONDARY_LOOP_TYPE","part":part}
	return {"ok":true}

static func enabled(value:Dictionary)->bool:
	for entry in value.values():
		if entry.get("lag",0.12)>0 and entry.get("amount",1.0)>0 and entry.get("max_offset",0.04)>0:return true
	return false

static func bake(frames:Array, settings:Dictionary, duration:float, scale_value:float=1.0)->Dictionary:
	var count:=frames.size()-1
	var result:Array=[]
	for i in range(count+1):result.append({})
	var cycles_error:=0.0
	for part in settings:
		var cfg:Dictionary=settings[part]
		var lag:float=cfg.get("lag",0.12);var amount:float=cfg.get("amount",1.0);var limit:float=cfg.get("max_offset",0.04)*scale_value
		if lag<=0 or amount<=0 or limit<=0:continue
		var points:Array[Vector3]=[]
		for frame in frames:points.append(frame[part])
		var loop:bool=cfg.get("loop",true)
		if loop and points[0].distance_to(points[-1])>0.0001*scale_value:
			# 胸の揺れは見た目だけの付属なので、戻らない動作（捕獲・撃破など）では静止から始める。
			if part in SOFT_PARTS:loop=false
			else:return {"ok":false,"code":"SECONDARY_LOOP_OPEN","part":part,"gap_world":points[0].distance_to(points[-1]),"hint":"Close the motion or set loop:false."}
		var h:=duration/count;var w:=2.0/maxf(lag,0.005);var damping:float=cfg.get("damping",0.7)
		var den:=1+2*damping*w*h+w*w*h*h
		var a:=(1+2*damping*w*h)/den;var b:=h/den;var c:=-h*w*w/den;var d:=1/den
		var fx:=h*h*w*w/den;var fv:=h*w*w/den
		var x:=Vector3.ZERO;var v:=Vector3.ZERO
		var m00:=1.0;var m01:=0.0;var m10:=0.0;var m11:=1.0
		if loop:
			for i in range(1,count+1):
				var old_x:=x;x=a*x+b*v+fx*points[i];v=c*old_x+d*v+fv*points[i]
				var n00:=a*m00+b*m10;var n01:=a*m01+b*m11
				var n10:=c*m00+d*m10;var n11:=c*m01+d*m11
				m00=n00;m01=n01;m10=n10;m11=n11
			var det:=(1-m00)*(1-m11)-m01*m10
			if absf(det)<1e-10:return {"ok":false,"code":"SECONDARY_PERIODIC_SINGULAR","part":part}
			var force_x:=x;var force_v:=v
			x=((1-m11)*force_x+m01*force_v)/det
			v=(m10*force_x+(1-m00)*force_v)/det
		else:x=points[0]
		var initial_x:=x;var initial_v:=v
		result[0][part]=((x-points[0])*amount).limit_length(limit)
		for i in range(1,count+1):
			var old_x:=x;x=a*x+b*v+fx*points[i];v=c*old_x+d*v+fv*points[i]
			result[i][part]=((x-points[i])*amount).limit_length(limit)
		if loop:
			cycles_error=maxf(cycles_error,maxf(x.distance_to(initial_x),v.distance_to(initial_v)))
			result[count][part]=result[0][part]
	if cycles_error>0.00001:return {"ok":false,"code":"SECONDARY_NOT_CONVERGED","residual":cycles_error}
	return {"ok":true,"frames":result,"periodic_residual":cycles_error}

static func sample(frames:Array,phase:float)->Dictionary:
	if frames.is_empty():return {}
	var f:=clampf(phase,0,1)*(frames.size()-1)
	var a:=mini(floori(f),frames.size()-2);var t:=f-a
	var result:Dictionary={}
	for part in frames[a]:result[part]=Vector3(frames[a][part]).lerp(frames[a+1][part],t)
	return result
