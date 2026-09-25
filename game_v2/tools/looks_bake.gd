extends SceneTree
## 見た目の焼き込み（mini/layered2d/prepare/looks.gd）。ブラウザ版・書き出した版の前に回す。
## ゲームと同じ Bridge で、全部の原型を役者に着せ（体・顔・表情）、付属物を全部着け、2体場面を全部読んで（場面の顔・効果）、
## そのとき作った128画素の升目を game_v2/assets/looks/ に保存する。
##   Godot_console --headless --path . --script res://game_v2/tools/looks_bake.gd [-- --quality=0.9]
## キャラの素材を登録・差し替えたら焼き直す（web_export.py は書き出しの前に自動で回す）。
const Bridge=preload("res://game_v2/animation/bridge.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Props=preload("res://game_v2/animation/props.gd")
const Pack=preload("res://game_v2/animation/pack.gd")
const Looks=preload("res://mini/layered2d/prepare/looks.gd")

func _initialize():call_deferred("run")

func fresh_bridge() -> Node:
	var b=Bridge.new();root.add_child(b)
	if not b.prepare_stream(4) or not b.prepare_finish():
		push_error("looks_bake: 準備できない "+str(b.error));return null
	return b

func done(b) -> void:
	b.get_parent().remove_child(b);b.free()

func run():
	var t0:=Time.get_ticks_msec()
	Looks.recording=true;Looks.enabled=false;Looks.files={}
	# --quality=0.9 で非可逆（小さくなる）。既定は可逆（原画から作ったものと画素まで同じ）。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):Looks.quality=float(a.get_slice("=",1))
	var bad:=0
	var props: Array=Props.read().keys().filter(func(k):return not str(k).begins_with("_"))
	# 1. 原型ごと：体の部位・その頭の顔（表情も）・付属物（耳は頭ごとに違う）
	for p in Profiles.ids():
		var b=fresh_bridge()
		if b==null:bad+=1;continue
		if not b.bind_row("r0",str(p)):print("  着せられない ",p," ",b.error);bad+=1;done(b);continue
		for id in props:
			var def: Dictionary=Props.resolve(str(id))
			if def.is_empty():continue
			var slot: String=str(def.get("slot",Props.KIND_SLOT.get(str(def.kind),"")))
			if slot!="":b.set_actor_props("r0",{slot:str(id)})
		done(b)
	# 2. 2体場面：場面の中の顔（焼いた顔の表情）と効果の画像
	var b2=fresh_bridge()
	var pairs: Dictionary=b2.pack_index.get("pairs",{})
	var scenes:=0
	for key in pairs:
		for scene_id in pairs[key]:
			if not b2.ensure_pair(str(key),str(scene_id)):print("  読めない場面 ",key," ",scene_id);bad+=1;continue
			scenes+=1
			for stage in b2.pair_sets[key][scene_id]:
				for effect in b2.pair_sets[key][scene_id][stage].compiled.get("effects",[]):
					var path: String=str(effect.get("path",""))
					if path=="" or Looks.data("common").effect.has(path):continue
					if not FileAccess.file_exists(path):print("  効果の画像がない ",path);bad+=1;continue
					Looks.put("common","effect",path,{"png":Looks.encode(Image.load_from_file(ProjectSettings.globalize_path(path)))})
	done(b2)
	var counts: Dictionary={"body":0,"face":0,"prop":0,"effect":0}
	for f in Looks.files:
		for kind in counts:counts[kind]+=Looks.files[f][kind].size()
	var bytes: int=Looks.save_all()
	print("LOOKS_BAKE quality=%s "%("可逆" if Looks.quality<0 else str(Looks.quality))+"files=%d body=%d face=%d prop=%d effect=%d scenes=%d size=%.1fMB bad=%d (%.1fs)"%[Looks.files.size(),counts.body,counts.face,counts.prop,counts.effect,scenes,bytes/1048576.0,bad,(Time.get_ticks_msec()-t0)/1000.0])
	quit()
