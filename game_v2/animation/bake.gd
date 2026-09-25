extends SceneTree
## 動作データの焼き込み。出力 game_v2/assets/bakes/pc.bin と pair_report.json。
##   引数なし           単体動作（登録簿の組み込み原型）＋ 全2体場面
##   -- --pairs-only    既存 pc.bin の単体動作を流用して2体場面だけ焼き直す
##   -- --scene=<ID>    その場面だけ焼き直す（--pairs-only を含む）
## 2体場面は content/pair_scenes/ の全場面 × 配役の全組み合わせ。通らない組み合わせは飛ばして
## pair_report.json に理由を残す（ゲームではその組み合わせだけ代替文字になる）。単体動作の失敗は止める。
const Session=preload("res://mini/layered2d/authoring/session.gd")
const Compiler=preload("res://mini/layered2d/prepare/scene_compiler.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
const Check=preload("res://game_v2/animation/pair_check.gd")
const TARGET="res://game_v2/assets/bakes/pc.bin"
const REPORT="res://game_v2/assets/bakes/pair_report.json"
func _initialize():call_deferred("run")
func run():
	var start=Time.get_ticks_msec()
	var only_scene: String=""
	var pairs_only: bool=false
	for arg in OS.get_cmdline_user_args():
		if arg=="--pairs-only":pairs_only=true
		elif arg.begins_with("--scene="):only_scene=arg.split("=",true,1)[1];pairs_only=true
	var bundle: Dictionary={"version":2,"clips":{},"pair_sets":{}}
	if pairs_only:
		if not FileAccess.file_exists(TARGET):push_error("PAIRS_ONLY_NEEDS_PC_BIN");quit(1);return
		bundle=FileAccess.open(TARGET,FileAccess.READ).get_var()
		bundle.version=2
		if not bundle.has("pair_sets"):bundle.pair_sets={}
	else:
		var definitions=JSON.parse_string(FileAccess.get_file_as_string("res://game_v2/content/game_clips.json"))
		for character in Profiles.built_in():
			bundle.clips[character]={}
			for clip in definitions:
				var session=Session.new()
				var result=session.load_scene({"version":1,"duration":definitions[clip].duration,"clips":definitions,"actors":[{"id":"actor","recipe":Profiles.recipe(character),"clip":clip}]})
				if not result.ok:push_error(str(result));quit(1);return
				var compiled=Compiler.new().compile(session)
				if not compiled.ok:push_error(clip+" "+str(compiled));quit(1);return
				var track: Dictionary=compiled.tracks[0]
				for direction in 8:
					for frame in track.times.size():
						var order=PackedInt32Array()
						for part in compiled.orders[direction][frame]:order.append(part.slot)
						track.orders[direction][frame]=order
				bundle.clips[character][clip]=track
				print("BAKED ",character," ",clip)
	var checker=Check.new()
	var report: Dictionary={}
	if only_scene!="" and FileAccess.file_exists(REPORT):
		var previous=JSON.parse_string(FileAccess.get_file_as_string(REPORT))
		if previous is Dictionary:report=previous.get("scenes",{})
	var scene_ids: Array=Library.ids()
	if only_scene!="":
		if not only_scene in scene_ids:push_error("UNKNOWN_SCENE "+only_scene);quit(1);return
		scene_ids=[only_scene]
		for key in bundle.pair_sets:bundle.pair_sets[key].erase(only_scene)
	else:
		bundle.pair_sets={}
	var skipped:=0
	for scene_id in scene_ids:
		var scene: Dictionary=Library.load_scene(scene_id)
		report[scene_id]=[]
		for entry in checker.check_scene(scene,true):
			if entry.ok:
				if not bundle.pair_sets.has(entry.key):bundle.pair_sets[entry.key]={}
				bundle.pair_sets[entry.key][scene_id]=entry.compiled
				print("BAKED_PAIR ",scene_id," ",entry.key)
			else:
				skipped+=1
				print("PAIR_SKIPPED ",scene_id," ",entry.key," ",entry.problems[0] if not entry.problems.is_empty() else "")
			entry.erase("compiled")
			report[scene_id].append(entry)
	for key in bundle.pair_sets.keys():
		if bundle.pair_sets[key].is_empty():bundle.pair_sets.erase(key)
	# 旧形式の読み手向け（冒険者×ゴブリン）。
	bundle.pairs=bundle.pair_sets.get(Library.key("0","1"),{})
	bundle.erase("pair_variants")
	DirAccess.make_dir_recursive_absolute("res://game_v2/assets/bakes")
	var output=FileAccess.open(TARGET+".tmp",FileAccess.WRITE)
	if output==null:push_error("BAKE_WRITE_FAILED");quit(1);return
	output.store_var(bundle)
	var write_error: int=output.get_error();output.close()
	if write_error!=OK:push_error("BAKE_WRITE_FAILED "+str(write_error));quit(1);return
	if DirAccess.rename_absolute(TARGET+".tmp",TARGET)!=OK:push_error("BAKE_REPLACE_FAILED");quit(1);return
	var report_file=FileAccess.open(REPORT,FileAccess.WRITE)
	if report_file!=null:
		report_file.store_string(JSON.stringify({"baked_at":Time.get_datetime_string_from_system(),"scenes":report},"\t")+"\n");report_file.close()
	print("BAKE_OK ms=",Time.get_ticks_msec()-start," pair_skipped=",skipped)
	# ゲームが必要な分だけ読むための分けたファイル（packs/）も作り直す。
	var packed: Dictionary=preload("res://game_v2/animation/pack.gd").build(bundle)
	print("PACK ",packed)
	quit()
