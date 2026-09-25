extends RefCounted
## Game action names stay stable; presentation clips may be reassigned.
const PATH="res://game_v2/content/animation_calls.json"
const CLIPS="res://game_v2/content/game_clips.json"
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
## 新しいゲーム（game/）の行動一覧。ゲーム設計書 3.2。旧ゲームの inspect / disarm / block / captured は外した。
const ACTIONS=["idle","walk","run","attack","attack_heavy","cast","hit","defeated","down","down_struggle","rise","bound","flee","heal","unbind","caged","work_dig","work_craft","work_cook","work_study","guard","rest","pregnant_idle","kneel","serve"]
const LABELS=["待機","歩く","走る","攻撃","強攻撃","魔法","被弾","倒れる","崩れ落ちる","もがく（捕虜状態）","起き上がる","縛られている","逃げる","治す","縄を解く","檻で待つ","掘る","作る","料理","調べる","見張る","休む","妊娠中の待機","ひざまずく","仕える"]
## 再生方式の既定（割り当てが無いとき）。
const HOLD_ACTIONS=["defeated","down"]
const ONCE_ACTIONS=["attack","attack_heavy","cast","hit","rise"]
static func defaults() -> Dictionary:
	var actions: Dictionary={}
	for action in ACTIONS:
		actions[action]={"clip":action,"speed":1.0,"mode":"hold" if action in HOLD_ACTIONS else ("once" if action in ONCE_ACTIONS else "loop")}
	return {"version":1,"actions":actions,"profiles":{"0":{},"1":{"attack":{"clip":"claw_attack","speed":1.0,"mode":"once"}}},"events":JSON.parse_string(FileAccess.get_file_as_string("res://game_v2/content/scene_bindings.json")).bindings}
static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):return defaults()
	var data=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var problem: String=validate(data)
	if problem!="":push_warning("Animation calls: "+problem);return defaults()
	return data
static func resolve(data: Dictionary,profile: String,action: String) -> Dictionary:
	var family: String=Profiles.family(profile)
	return data.get("profiles",{}).get(profile,{}).get(action,data.get("profiles",{}).get(family,{}).get(action,data.actions.get(action,{"clip":action,"speed":1.0,"mode":"loop"})))
static func validate(data: Variant) -> String:
	if not data is Dictionary or data.get("version",0)!=1:return "設定の形式が不正です"
	if not data.get("actions") is Dictionary or not data.get("profiles") is Dictionary or not data.get("events") is Array:return "actions / profiles / events が必要です"
	for key in ["0","1"]:
		if not data.profiles.get(key) is Dictionary:return "冒険者とゴブリンの原型設定が必要です"
	var definitions=JSON.parse_string(FileAccess.get_file_as_string(CLIPS))
	for key in ACTIONS:
		if not data.actions.has(key):return "行動が不足: "+key
	var groups: Array=[data.actions]
	for profile in data.profiles:
		if not str(profile) in Profiles.ids() or not data.profiles[profile] is Dictionary:return "未登録の原型です（content/animation_profiles.json）: "+str(profile)
		groups.append(data.profiles[profile])
	for group in groups:
		for key in group:
			var v=group[key]
			if key not in ACTIONS or not v is Dictionary:return "行動設定が不正: "+str(key)
			if not definitions.has(v.get("clip","")):return "未登録モーション: "+str(v.get("clip",""))
			if v.get("mode","") not in ["loop","once","hold"]:return "再生方式が不正: "+key
			if not (v.get("speed") is float or v.get("speed") is int):return "速度が数値ではありません"
			if not is_finite(float(v.speed)) or float(v.speed)<0.1 or float(v.speed)>1.9:return "速度は0.1〜1.9です"
	var scenes: Dictionary=Library.scenes()
	for event in data.events:
		if not event is Dictionary or not event.get("event_kind") is String or event.event_kind.strip_edges()=="":return "出来事IDが必要です"
		if event.has("source_definition_id") and event.has("source_tag"):return "発生元IDとタグはどちらか一つを指定してください"
		for key in ["source_definition_id","source_tag","target_definition_id","target_tag","room","phase","fall","capture","weakness_type","weakness_result","resolution","policy","symbol","pair_scene_id","stage"]:
			if event.has(key) and not event[key] is String:return "条件・表示の値は文字列にしてください: "+key
		if event.get("pair_scene_id","")!="":
			var scene_id: String=event.pair_scene_id
			if not scenes.has(scene_id):return "未登録の2体場面: "+scene_id
			var stage: String=event.get("stage","default")
			# "@sequence" は場面の流れ（sequence）を通しで流す指定（Bridge.play_pair_sequence）。
			if stage=="@sequence":
				if not scenes[scene_id].get("sequence") is Array or scenes[scene_id].sequence.is_empty():return "流れ（sequence）の無い場面: "+scene_id
			elif stage!="default" and not scenes[scene_id].get("stages",{}).has(stage):return "未登録の段階: "+stage
	return ""
static func save_data(data: Dictionary,path: String=PATH) -> String:
	var problem: String=validate(data)
	if problem!="":return problem
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "設定を書き込めません: "+str(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data,"\t")+"\n");file.close()
	if FileAccess.file_exists(path):
		var backup_error=DirAccess.copy_absolute(path,path+".previous")
		if backup_error!=OK:return "バックアップに失敗しました"
	var result=DirAccess.rename_absolute(path+".tmp",path)
	return "" if result==OK else "設定の置き換えに失敗: "+str(result)
