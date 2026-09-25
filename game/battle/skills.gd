extends RefCounted
## スキルの値と範囲の解釈（設計書 4.4）。値は {base, stat, per} で、base ＋ 使い手の能力 × per。
const G=preload("res://game/core/g.gd")

## 値を読む（数・{base, stat, per}）。stats は使い手の能力。
static func value(v,stats: Dictionary) -> float:
	if v==null:return 0.0
	if v is Dictionary:
		return float(v.get("base",0.0))+(float(stats.get(str(v.stat),0.0))*float(v.get("per",0.0)) if v.has("stat") else 0.0)
	return float(v)

## 射程（マス。数か {base, stat, per}）。距離は中心どうしのまっすぐな長さ。
static func reach(s: Dictionary,stats: Dictionary) -> float:
	return value(s.get("range",1),stats)

## 範囲の広さ（マス）。square は r マス四方を丸で近似した半径 r+0.5、line は長さ r+0.5・幅 0.45。bonus は範囲の広がり。
static func area_radius(s: Dictionary,bonus: int) -> float:
	return float(s.get("area",{}).get("r",1))+float(bonus)+0.5

## p が範囲に入るか。center は中心（single・square）か狙う先（line）。from は使い手の位置。
static func in_area(s: Dictionary,center: Vector2,from: Vector2,bonus: int,p: Vector2) -> bool:
	var a: Dictionary=s.get("area",{"shape":"single"})
	match str(a.get("shape","single")):
		"square":return p.distance_to(center)<=area_radius(s,bonus)
		"line":
			var d: Vector2=center-from
			if d.length()<1e-4:d=Vector2(1,0)
			d=d.normalized()
			var rel: Vector2=p-from
			var along: float=rel.dot(d)
			return along>0.0 and along<=area_radius(s,bonus) and absf(rel.dot(d.orthogonal()))<=0.45
		"all":return true
		_:return p.distance_to(center)<=0.35

## 範囲の形（画面の光に使う）{shape, center, r, from}。
static func area_shape(s: Dictionary,center: Vector2,from: Vector2,bonus: int) -> Dictionary:
	var shape: String=str(s.get("area",{}).get("shape","single"))
	return {"shape":shape,"center":center,"from":from,"r":area_radius(s,bonus) if shape in ["square","line"] else 0.5}

## 説明の文（効き目にどの能力が効くか）。
static func describe(id: String) -> String:
	var s: Dictionary=G.db.skill(id)
	if s.is_empty():return ""
	var parts: Array=[str(s.get("desc",""))]
	if str(s.kind)=="active":
		var rg=s.get("range",1)
		var rt: String=("射程 %d"%int(rg)) if not rg is Dictionary else "射程 %d＋%s"%[int(rg.base),G.db.stat_name(str(rg.stat))]
		if str(s.get("target",""))=="self":rt="自分のまわり"
		parts.append(rt)
	return "　".join(parts)

## 効き目に使う能力の一覧（画面の説明用）。
static func stats_used(id: String) -> Array:
	var s: Dictionary=G.db.skill(id)
	var out: Array=[]
	var scan:=func(v):
		if v is Dictionary and v.has("stat") and not str(v.stat) in out:out.append(str(v.stat))
	scan.call(s.get("range",1))
	for e in s.get("effects",[]):
		for k in ["v","dur","power"]:scan.call(e.get(k,null))
	for k in s.get("mods",{}):
		scan.call(s.mods[k])
	return out
