extends RefCounted
## 2体場面の確認。ベイク（bake.gd）と確認コマンド（tools/scene_check.gd）が同じ判定を使う。
## 1つの場面を「受け側×相手」の全組み合わせ・全段階でコンパイルし、失敗で止めずに全部集めて言葉にする。
const Session=preload("res://mini/layered2d/authoring/session.gd")
const Compiler=preload("res://mini/layered2d/prepare/scene_compiler.gd")
const Catalog=preload("res://mini/layered2d/data/catalog.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
const CONTACT_LIMIT:=0.005
const BOUNDARY_CENTER:=0.005
const BOUNDARY_ROTATION:=0.01
const FAILED_SCORE:=100.0

var recipe_cache: Dictionary={}

## 1組み合わせ×1段階。notes に自動で行った調整を残す。
## contact_limit を大きくすると、接触が合わない場面も下見用に焼ける（判定には使わない）。
func compile(scene: Dictionary,taker: String,partner: String,stage: String,contact_limit: float=CONTACT_LIMIT) -> Dictionary:
	var loaded: Dictionary=load_session(scene,taker,partner,stage)
	if not loaded.ok:return loaded
	var result: Dictionary=Compiler.new().compile(loaded.session,-1.0,0.009,96.0,contact_limit)
	result.notes=loaded.notes
	if result.get("ok",false):
		result.effects=effects_for(loaded.session.scene)
		result.walls=walls_for(loaded.session.scene)
		result.blocks=walls_for(loaded.session.scene,"blocks")
		result.lines=lines_for(loaded.session.scene)
		# 付属物の見せ方（actors[].props）。役者の順の配列。再生時に Bridge が役者の状態へ写す。
		result.props=[]
		for actor in loaded.session.scene.get("actors",[]):result.props.append(actor.get("props",{}) if actor.get("props",{}) is Dictionary else {})
		result.sequence=valid_sequence(loaded.session.scene)
		result.loop=loaded.session.scene.get("loop",true)!=false
	return result

## 効果の層（汗・紅潮・記号など）。場面の effects を焼いた結果に写す（actor の id を番号にする）。
## 描くのは runtime/pair_group.gd。画像は character_assets/effects/<image>.png。
const EFFECT_DIR="res://character_assets/effects/"
static func effects_for(scene: Dictionary) -> Array:
	var ids: Array=[]
	for actor in scene.get("actors",[]):ids.append(str(actor.get("id","")))
	var result: Array=[]
	for effect in scene.get("effects",[]):
		if not effect is Dictionary:continue
		var entry: Dictionary=effect.duplicate(true)
		entry.actor_index=ids.find(str(effect.get("actor","")))
		entry.path=EFFECT_DIR+str(effect.get("image",""))+".png"
		if entry.actor_index>=0:result.append(entry)
	return result

## 壁（壁尻など）。場面の walls を焼いた結果に写す（actor の id を番号にする）。描くのは runtime/pair_group.gd。
## 線（lines）。"from": "<actor>.<部位>"、"to": "<actor>.<部位>" か "to_point": [x,y,z]（from の actor の足もとから）。
## 部位は Catalog.SLOTS の名前（hand_r / neck / boot_l …）。描くのは runtime/pair_group.gd（LineLayer）。
static func lines_for(scene: Dictionary) -> Array:
	var ids: Array=[]
	for actor in scene.get("actors",[]):ids.append(str(actor.get("id","")))
	var result: Array=[]
	for line in scene.get("lines",[]):
		if not line is Dictionary:continue
		var entry: Dictionary=line.duplicate(true)
		var f: PackedStringArray=str(line.get("from","")).split(".")
		if f.size()!=2 or ids.find(f[0])<0 or Catalog.SLOTS.find(f[1])<0:continue
		entry.from_actor=ids.find(f[0]);entry.from_slot=Catalog.SLOTS.find(f[1])
		entry.to_actor=entry.from_actor;entry.to_slot=-1
		if line.has("to"):
			var t: PackedStringArray=str(line.to).split(".")
			if t.size()!=2 or ids.find(t[0])<0 or Catalog.SLOTS.find(t[1])<0:continue
			entry.to_actor=ids.find(t[0]);entry.to_slot=Catalog.SLOTS.find(t[1])
		result.append(entry)
	return result

## 置物（blocks）も同じ形で写す。
static func walls_for(scene: Dictionary,field: String="walls") -> Array:
	var ids: Array=[]
	for actor in scene.get("actors",[]):ids.append(str(actor.get("id","")))
	var result: Array=[]
	for wall in scene.get(field,[]):
		if not wall is Dictionary:continue
		var entry: Dictionary=wall.duplicate(true)
		entry.actor_index=ids.find(str(wall.get("actor","")))
		if entry.actor_index>=0:result.append(entry)
	return result

## 読み込み済みの Session（焼く前の状態）。数値確認（scene_tools.gd の probe）と compile が共用する。
## 成功時 {ok:true, session, notes}。失敗時は Session.load_scene の返り値に notes を足したもの。
func load_session(scene: Dictionary,taker: String,partner: String,stage: String) -> Dictionary:
	var source: Dictionary=apply_body_patches(scene,taker,partner)
	source.erase("cast")
	var taker_recipe: Dictionary=Profiles.recipe(taker,recipe_cache)
	# 1体だけの場面（partner が空）は actors[0] だけを使う。
	var partner_recipe: Dictionary=Profiles.recipe(partner,recipe_cache) if partner!="" else {"solo":true}
	if taker_recipe.is_empty() or partner_recipe.is_empty():
		return {"ok":false,"code":"PROFILE_MISSING","notes":[],"missing":taker if taker_recipe.is_empty() else partner}
	if partner=="":
		if source.get("actors",[]).size()!=1:return {"ok":false,"code":"SOLO_ACTORS","notes":[]}
		source.actors[0].recipe=taker_recipe
	else:
		source.actors[0].recipe=taker_recipe;source.actors[1].recipe=partner_recipe
	var notes: Array=[]
	var session=Session.new()
	var accepted: Dictionary=session.load_scene(source,"" if stage=="default" else stage)
	if not accepted.ok and accepted.get("code","")=="BAKED_FACE_NO_PARTS":
		for actor in source.actors:actor.erase("face_keys")
		notes.append("顔が一枚絵の体型なので表情キー（face_keys）を外した")
		session=Session.new();accepted=session.load_scene(source,"" if stage=="default" else stage)
	if not accepted.ok:
		accepted.notes=notes;return accepted
	return {"ok":true,"session":session,"notes":notes}

## 体型ごとの上書き（場面JSONの by_body）。{"<原型ID>": {"<. 区切りの場所>": 値, ...}}。
## 受け側・相手のどちらかがその原型なら当てる（相手→受け側の順）。配列は番号で指す（actors.1.root）。
## 例: "by_body": {"four_knight": {"actors.1.root": [-0.2, 0, -0.2], "clips.hold.poses.in.hip": [0, 1.7, 0.1]}}
static func apply_body_patches(scene: Dictionary,taker: String,partner: String) -> Dictionary:
	var source: Dictionary=scene.duplicate(true)
	var patches=source.get("by_body",{})
	source.erase("by_body")
	if not patches is Dictionary:return source
	for id in [partner,taker]:
		var patch=patches.get(id,{})
		if not patch is Dictionary:continue
		for path in patch:set_path(source,str(path),patch[path])
	return source

static func set_path(data: Variant,path: String,value: Variant) -> void:
	var keys: PackedStringArray=path.split(".")
	var node=data
	for i in keys.size()-1:
		var next=node[int(keys[i])] if node is Array else node.get(keys[i])
		if next==null:
			next={};node[keys[i]]=next
		node=next
	if node is Array:node[int(keys[-1])]=value.duplicate(true) if value is Array or value is Dictionary else value
	else:node[keys[-1]]=value.duplicate(true) if value is Array or value is Dictionary else value

## 1組み合わせの全段階。keep=true ならコンパイル結果（ベイク・撮影用）も返す。
## preview=true（keep と一緒に）なら、接触が合わない段階も下見用に焼いて compiled に入れる（entry.preview=true）。
## ベイクは entry.ok のものしか書かないので、下見がゲームに入ることはない。
func check_pair(scene: Dictionary,taker: String,partner: String,keep: bool=false,only_stage: String="",preview: bool=false) -> Dictionary:
	var entry: Dictionary={"taker":taker,"partner":partner,"key":Library.key(taker,partner),"ok":true,"stages":{},"problems":[],"hints":[],"notes":[],"score":0.0,"compiled":{}}
	var results: Dictionary={}
	for stage in Library.stages(scene):
		if only_stage!="" and stage!=only_stage:continue
		var result: Dictionary=compile(scene,taker,partner,stage)
		for note in result.get("notes",[]):
			if not note in entry.notes:entry.notes.append(note)
		var info: Dictionary={"ok":result.get("ok",false),"code":result.get("code",""),"contact":float(result.get("max_contact_world",result.get("max_world",0.0)))}
		if result.has("worst"):info.worst=result.worst
		var bend: float=float(result.get("max_bend_world",0.0))
		if bend>0.0:
			var where: Dictionary=result.get("worst_bend",{})
			var note: String="段階 %s：肘・膝の目標から最大 %.3f 離れている（%s、位相 %.2f）。判定には入れない目安"%[stage,bend,str(where.get("goal","")),float(where.get("phase",0))]
			entry.notes.append(note)
		entry.stages[stage]=info
		if not result.get("ok",false):
			entry.ok=false
			entry.score=maxf(entry.score,info.contact/CONTACT_LIMIT if info.code=="CONTACT_RESIDUAL_EXCEEDED" else FAILED_SCORE)
			describe_failure(scene,stage,result,entry)
			# 撮影用に、接触の上限を外した下見を持つ（ゲーム用には焼かない。画像には × が付く）。
			if keep and preview and info.code=="CONTACT_RESIDUAL_EXCEEDED":
				var rough: Dictionary=compile(scene,taker,partner,stage,INF)
				if rough.get("ok",false):entry.compiled[stage]=rough;entry.preview=true
			continue
		entry.score=maxf(entry.score,info.contact/CONTACT_LIMIT)
		if keep:entry.compiled[stage]=result
		results[stage]=result
	check_boundaries(scene,results,entry)
	if not keep:entry.erase("compiled")
	return entry

## 段階のつなぎ目の検査。
## sequence がある場面：並びの順に「前の段階の終わり → 次の段階の始まり」と、2周以上回す段階の「終わり → 始まり」。
## sequence に無い段階（と sequence の無い場面）は従来どおり「default の始まり ＝ その段階の始まり」（周期の頭で切り替えるため）。
func check_boundaries(scene: Dictionary,results: Dictionary,entry: Dictionary) -> void:
	var pairs: Array=[]
	var sequence: Array=valid_sequence(scene)
	var covered: Dictionary={}
	for i in sequence.size():
		var stage: String=str(sequence[i].stage);covered[stage]=true
		if int(sequence[i].get("cycles",1))>1:pairs.append([stage,-1,stage,0,"段階 %s を繰り返すとき（終わり→始まり）"%stage])
		if i+1<sequence.size():pairs.append([stage,-1,str(sequence[i+1].stage),0,"%s → %s のつなぎ目"%[stage,sequence[i+1].stage]])
	for stage in results:
		if stage!="default" and not covered.has(stage):pairs.append(["default",0,stage,0,"段階 %s の開始姿勢が default と違う"%stage])
	for check in pairs:
		if not results.has(check[0]) or not results.has(check[2]):continue
		var boundary: Dictionary=boundary_difference(results[check[0]],results[check[2]],scene,check[1],check[3])
		if entry.stages.has(check[2]):entry.stages[check[2]].boundary=boundary
		entry.score=maxf(entry.score,maxf(boundary.center/BOUNDARY_CENTER,boundary.rotation/BOUNDARY_ROTATION))
		if boundary.center<=BOUNDARY_CENTER and boundary.rotation<=BOUNDARY_ROTATION:continue
		entry.ok=false
		entry.problems.append("%s：%s の %s（位置差 %.4f / 上限 %.3f、角度差 %.3f rad / 上限 %.2f）"%[check[4],boundary.actor,boundary.part,boundary.center,BOUNDARY_CENTER,boundary.rotation,BOUNDARY_ROTATION])
		var has_secondary: bool=false
		for actor in scene.actors:
			if actor.has("secondary"):has_secondary=true
		if scene.get("stages",{}).get(check[2],{}).has("duration") and has_secondary:
			add_hint(entry,"段階で duration を変えると揺れ（secondary）の残り方が変わり、周期の頭の姿勢もずれる。周期は変えず、ポーズの振れ幅で強弱をつける")
		elif check[1]==-1:
			add_hint(entry,"前の段階の最後のキーと、次の段階の最初のキーを同じ姿勢にする（1回だけの段階は keys の最後で次の段階の始まりに合わせる）")
		else:
			add_hint(entry,"段階の上書きが位相0の姿勢に触れていないか確認する（全段階で周期の頭の姿勢を揃える）。接触相手の腕が伸び切っていると、わずかな差で解が変わりやすい")

## 場面の流れ。[{stage, cycles?, hold?, cue?, pause?}]。無い・不正なら空。
static func valid_sequence(scene: Dictionary) -> Array:
	var sequence=scene.get("sequence",[])
	if not sequence is Array:return []
	var stages: Array=Library.stages(scene)
	for item in sequence:
		if not item is Dictionary or not str(item.get("stage","")) in stages:return []
	return sequence

## 場面の全組み合わせ。
func check_scene(scene: Dictionary,keep: bool=false) -> Array:
	var result: Array=[]
	for pair in Library.cast(scene):result.append(check_pair(scene,pair[0],pair[1],keep))
	return result

## 2つの焼いた結果の、指定のコマ（0=最初、-1=最後）どうしの部位のずれの最大。
func boundary_difference(reference: Dictionary,candidate: Dictionary,scene: Dictionary,reference_frame: int=0,candidate_frame: int=0) -> Dictionary:
	var worst: Dictionary={"center":0.0,"rotation":0.0,"actor":"","part":""}
	var worst_score:=0.0
	for actor in reference.tracks.size():
		var a: Dictionary=reference.tracks[actor].frames[reference_frame];var b: Dictionary=candidate.tracks[actor].frames[candidate_frame]
		for part in a.parts.size():
			var center: float=a.parts[part].center.distance_to(b.parts[part].center)
			var rotation: float=a.parts[part].rotation.angle_to(b.parts[part].rotation)
			var score: float=maxf(center/BOUNDARY_CENTER,rotation/BOUNDARY_ROTATION)
			if score>worst_score:
				worst_score=score
				worst={"center":center,"rotation":rotation,"actor":actor_name(scene,actor),"part":Catalog.SLOTS[part] if part<Catalog.SLOTS.size() else str(part)}
	return worst

func describe_failure(scene: Dictionary,stage: String,result: Dictionary,entry: Dictionary) -> void:
	var code: String=result.get("code","")
	match code:
		"CONTACT_RESIDUAL_EXCEEDED":
			var worst: Dictionary=result.get("worst",{})
			entry.problems.append("段階 %s：接触が合わない。%s の %s が位相 %.2f で %.4f ずれ（上限 %.3f）"%[stage,worst.get("group",""),worst.get("goal",""),float(worst.get("phase",0)),float(result.max_world),CONTACT_LIMIT])
			add_hint(entry,"手が届いていない。相手の立ち位置 actors[1].root か接点の offset を調整する。scene_check.gd --search で全体型に通る立ち位置を探せる")
		"INTERPOLATION_ERROR_LIMIT":
			var first: Dictionary=result.get("details",[{}])[0]
			entry.problems.append("段階 %s：補間の誤差が大きい。%s の %s、位相 %.3f 付近で %.4f（%d か所）"%[stage,actor_name(scene,int(first.get("actor",0))),first.get("socket",""),float(first.get("phase",0)),float(first.get("error",0)),int(result.get("count",0))])
			add_hint(entry,"速い弧・肘の反転・ねじりの大回りで起きやすい。中間キーを足す、肘を曲げたままにする、ねじり量を減らす")
		"SOLO_ACTORS":
			entry.problems.append("1体だけの場面（cast.partner が []）なのに actors が1つではない")
		"PROFILE_MISSING":
			entry.problems.append("原型 %s のレシピがない（追加素材の束ファイルが未作成？）"%result.get("missing",""))
		_:
			entry.problems.append("段階 %s：%s %s"%[stage,code,JSON.stringify(result).left(300)])

func add_hint(entry: Dictionary,text: String) -> void:
	if not text in entry.hints:entry.hints.append(text)

func actor_name(scene: Dictionary,index: int) -> String:
	var actors: Array=scene.get("actors",[])
	return str(actors[index].get("id","actor_"+str(index))) if index<actors.size() else "actor_"+str(index)

## 結果を人が読む行にする。余裕度は 1.0 未満なら合格（接触・境目の上限に対する割合の最大値）。
func report_lines(scene_id: String,entries: Array) -> Array:
	var lines: Array=["■ "+scene_id]
	for entry in entries:
		var stage_text: Array=[]
		for stage in entry.stages:
			var info: Dictionary=entry.stages[stage]
			var text: String=stage+" "+("OK" if info.ok else "NG")+" 接触%.4f"%info.contact
			if info.has("boundary"):text+=" 境目%.3frad"%info.boundary.rotation
			stage_text.append(text)
		lines.append("  %s %s  上限比 %.2f  [%s]"%["○" if entry.ok else "×",Library.cast_name(entry.taker,entry.partner),entry.score,", ".join(stage_text)])
		for problem in entry.problems:lines.append("      問題: "+problem)
		for hint in entry.hints:lines.append("      対処: "+hint)
		for note in entry.notes:lines.append("      補足: "+note)
	return lines
