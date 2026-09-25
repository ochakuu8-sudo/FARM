extends RefCounted
## 役者の見た目（原型・色・背丈・部品・付属物）。種族の骨格の素材が届くまで、魔物はゴブリンの原型を色と大きさで分ける。
## 生まれた子には母の髪の色の面影を混ぜる。人型の魔物の女は体の色と付属物（獣の耳・尻尾）で分ける。
const G=preload("res://game/core/g.gd")

static func species(id: String,mother_tint: String="") -> Dictionary:
	var d: Dictionary=G.db.species.get(id,{})
	var c:=Color(str(d.get("tint","#ffffff")))
	if mother_tint!="":c=c.lerp(Color(mother_tint),0.35)
	return {"profile":str(d.get("profile","1")),"tint":c,"height":float(d.get("scale",1.0)),"props":d.get("props",{}).duplicate()}

## 雑兵（こちらが連れて行く名前のない兵）。
static func minion() -> Dictionary:
	return {"profile":"1","tint":Color("9a968a"),"height":0.78,"props":{"weapon_r":"sword_iron"}}

static func monster(m: Dictionary) -> Dictionary:
	if m.is_empty():return {}
	return species(str(m.species),str(m.get("tint","")))

## 相手役がいない施設の見た目だけの魔物（搾り場など）。
static func servant() -> Dictionary:
	return {"profile":"1","tint":Color("d8c8b8"),"height":1.0}

static func woman(w: Dictionary) -> Dictionary:
	var t: String=str(w.get("tint",""))
	return {"profile":str(w.get("profile","0")),"tint":Color(t) if t!="" else Color.WHITE,"height":1.0,"parts":w.get("parts",{}),"props":w.get("props",{})}

## 戦闘の一行の者（武器を持つ）。
static func member(m: Dictionary) -> Dictionary:
	var jd: Dictionary=G.db.jobs.get(str(m.job),{})
	var props: Dictionary=jd.get("props",{}).duplicate()
	if jd.has("weapon"):props["weapon_r"]=str(jd.weapon)
	if jd.has("shield"):props["weapon_l"]=str(jd.shield)
	var t: String=str(jd.get("tint",""))
	return {"profile":"0","tint":Color(t) if t!="" else Color.WHITE,"height":1.0,"parts":m.get("parts",{}),"props":props}

## 役者を借りて見た目を当てる（借りられなければ ""）。
static func dress(look: Dictionary,height: float=1.0) -> String:
	var id: String=G.anim.acquire(str(look.get("profile","0")))
	if id=="":return ""
	G.anim.height(id,height*float(look.get("height",1.0)))
	if look.has("tint"):G.anim.tint(id,look.tint)
	G.anim.parts(id,look.get("parts",{}))
	var props: Dictionary=look.get("props",{})
	if not props.is_empty():G.anim.props(id,props)
	return id
