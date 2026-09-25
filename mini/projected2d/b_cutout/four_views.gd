extends RefCounted
## Four authored directions. Mirrors and interpolation are runtime reuse, not new art.
var cap_enabled:=false
const ANGLES=[0.0,45.0,90.0,135.0,180.0,225.0,270.0,315.0,360.0]
const IDS=[0,1,2,4,4,4,6,7,0]
func resolve(view:Vector3)->Dictionary:
	var angle:=fposmod(rad_to_deg(atan2(view.x,view.z)),360)
	var elevation:=rad_to_deg(asin(clampf(view.normalized().y,-1,1)))
	var cap:=smoothstep(45,80,elevation) if cap_enabled else 0.0
	var ids:Array=IDS
	for i in range(8):
		if angle<=ANGLES[i+1]:
			var t:float=(angle-ANGLES[i])/(ANGLES[i+1]-ANGLES[i])
			return {"ids":[ids[i],ids[i+1],8 if cap_enabled else 0],"weights":Vector3((1-t)*(1-cap),t*(1-cap),cap),"derived_cap":cap>0,"underside_missing":elevation< -15}
	return {"ids":[0,1,0],"weights":Vector3(1,0,0)}
