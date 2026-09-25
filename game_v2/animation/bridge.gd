extends Node2D
const World=preload("res://mini/layered2d/runtime/world.gd")
const Store=preload("res://mini/layered2d/prepare/resource_store.gd")
const Pair=preload("res://mini/layered2d/runtime/pair_group.gd")
const Recipes=preload("res://game_v2/animation/recipes.gd")
const Calls=preload("res://game_v2/animation/call_registry.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const Parts=preload("res://game_v2/animation/parts.gd")
const Library=preload("res://game_v2/animation/pair_library.gd")
const Props=preload("res://game_v2/animation/props.gd")
var call_settings: Dictionary={}:
	set(v):call_settings=v;resolved_calls={}
var world=World.new()
var resources
var tracks: Dictionary={}
var rows: Dictionary={}
var clips: Dictionary={}
var heights: Dictionary={}
var appearance_heights: Dictionary={}
## 2体場面。pair_sets["受け側原型|相手原型"][場面][段階]={compiled,ids}。組み合わせごとに体格に合わせて焼いてある。
var pair_sets: Dictionary={}
## 旧来の参照用（冒険者"0"×ゴブリン"1"）。pair_sets["0|1"] と同じもの。
var pair_data: Dictionary={}
## ゲームで2体場面を流す最長秒数（director が使う既定値）。
const PAIR_SECONDS:=4.0
## 同時に再生できる2体場面の数。ゲームは1。管理ツールの8方向確認では8にする。
var max_pairs: int=1
## 2体場面の再生中に許す表示位置のずれ（px）。被弾の揺れ（最大3px）で切れないように。
const PAIR_DRIFT:=16.0
var pairs: Dictionary={}
## 止めた2体場面の描画ノード（次の場面で使い回す）。
var pair_pool: Array=[]
## Bridge を作り直しても（管理ツールの焼き込み後など）描画ノードを使い回す。置き場は木の中なので終了時に一緒に解放される。
const Spare=preload("res://mini/layered2d/runtime/spare_holder.gd")

func _notification(what: int) -> void:
	if what==NOTIFICATION_ENTER_TREE:Spare.ensure()
	elif what==NOTIFICATION_PREDELETE:
		for h in pairs:pair_pool.append(pairs[h].node)
		for node in pair_pool:
			if is_instance_valid(node) and node.get_parent()==self:Spare.park_pair(node)
		pair_pool.clear()
		# 読み込みの途中で終わった（木に載せる前の）World は自分で解放する。
		if is_instance_valid(world) and world.get_parent()==null:world.free()
var sequence: int=1
var ready_ms: int=0
var error: String=""
var playback: Dictionary={}
var latest: Dictionary={}
var generations: Array=[]
var face_banks: Dictionary={}
var expressions: Dictionary={}
var profiles: Dictionary={}
signal scene_finished(handle: int,reason: String)
## extra_bundle_path は追加素材の束ファイル。1つ（文字列）でも複数（配列）でもよい。
## 全部を一度に読むときのテクスチャの上限（MiB）。
const FULL_LOAD_BUDGET_MIB:=768
## 全部を一度に読むときの動作データのページ数の上限（1枚 1MiB）。場面が増えると 64 では足りない。
const FULL_LOAD_MOTION_PAGES:=256

func prepare(ids: Array,profile_map: Dictionary={},extra_bundle_path: Variant="") -> bool:
	if not prepare_data(ids,profile_map,extra_bundle_path):return false
	return prepare_finish()

## 読み込みの前半：ファイルを読み、動作・役者・場面を描画用のデータに積み、部位の重ね順の形を作っておく。
## 木（シーン）に触らないので、別スレッドで呼んでよい（ゲームの起動はタイトルを出したまま裏で回す）。
var pending: Dictionary={}
var prepare_begin:=0
func prepare_data(ids: Array,profile_map: Dictionary={},extra_bundle_path: Variant="") -> bool:
	Recipes.reset()
	var begin=Time.get_ticks_msec()
	prepare_begin=begin
	call_settings=Calls.read()
	if not FileAccess.file_exists("res://game_v2/assets/bakes/pc.bin"):
		error="動作データがありません。game_v2/animation/bake.gd を実行してください";return false
	var bundle=FileAccess.open("res://game_v2/assets/bakes/pc.bin",FileAccess.READ).get_var()
	var extra_paths: Array=extra_bundle_path if extra_bundle_path is Array else ([] if str(extra_bundle_path)=="" else [str(extra_bundle_path)])
	bundle["recipes"]={}
	for extra_path in extra_paths:
		if not FileAccess.file_exists(extra_path):error="上下セットの動作データがありません: "+str(extra_path);return false
		var extra=FileAccess.open(extra_path,FileAccess.READ).get_var()
		if not extra is Dictionary or extra.get("version")!=1:error="上下セットの動作データが不正です";return false
		bundle.clips.merge(extra.get("clips",{}),true)
		bundle.recipes.merge(extra.get("recipes",{}),true)
	resources=Store.new(false)
	# 全部を一度に読む（道具のプレビュー）。原型が増えると身体の画像だけで 256MiB を超えるので上限を広げる。
	resources.texture_budget_mib=FULL_LOAD_BUDGET_MIB
	resources.motion_page_limit=FULL_LOAD_MOTION_PAGES
	for character in bundle.clips:
		tracks[character]={}
		for clip in bundle.clips[character]:tracks[character][clip]=resources.add_track(bundle.clips[character][clip])
	var recipes: Array=[];var handles: Array=[]
	for id in ids:
		var index: String=str(profile_map.get(id,1 if id in ["grim","bog"] else 0))
		# 見た目だけの原型は骨格（rig）の焼いた動作を使う（同じトラックを指す）。
		var rig: String=Profiles.rig(index)
		if not bundle.clips.has(rig):error="動作未準備: "+rig;return false
		if not tracks.has(index):tracks[index]=tracks[rig]
		profiles[id]=str(index)
		var recipe: Dictionary=bundle.get("recipes",{}).get(index,{}).duplicate(true)
		if recipe.is_empty():recipe=built_in_recipe(index,100+recipes.size())
		Profiles.with_soft(index,recipe)
		prop_ids[id]=Profiles.info(index).get("props",{}).duplicate()
		recipe.props=Props.resolve_all(prop_ids[id])
		recipe.seed=100+recipes.size()
		var row: int=recipes.size()
		rows[id]=row;clips[id]="idle";heights[id]=float(Profiles.info(index).get("height",1.0))
		# Extra appearance presets retain their authored stature. Runtime height is an additional scale.
		appearance_heights[id]=float(recipe.height) if bundle.get("recipes",{}).has(index) else 1.0
		playback[id]={"elapsed":0.0,"mode":"loop","speed":1.0,"action":-1};generations.append(1)
		expressions[id]="neutral"
		resources.bind_actor(row,recipe,bundle.clips[rig].idle.rest_radii)
		# 衣装差分（outfits.json）。2体場面の outfit / outfit_keys で切り替わる。
		var outfits: Dictionary=Profiles.outfits(index)
		if not outfits.is_empty():resources.bind_outfits(row,recipe,outfits)
		recipes.append(recipe);handles.append(tracks[str(index)].idle)
	for index in tracks:
		var recipe: Dictionary=bundle.get("recipes",{}).get(str(index),{}).duplicate(true)
		if recipe.is_empty():recipe=built_in_recipe(index)
		Profiles.with_soft(str(index),recipe)
		face_banks[str(index)]=face_bank_for(recipe)
	var sets: Dictionary=bundle.get("pair_sets",{})
	if sets.is_empty() and bundle.has("pairs"):sets={Library.key("0","1"):bundle.pairs}
	for key in sets:
		var cast: PackedStringArray=str(key).split("|")
		# 読み込んだ原型の組み合わせだけ持つ。
		if cast.size()!=2 or not tracks.has(cast[0]) or (cast[1]!="" and not tracks.has(cast[1])):continue
		pair_sets[key]={}
		for id in sets[key]:
			pair_sets[key][id]={}
			for stage in sets[key][id]:
				var compiled: Dictionary=sets[key][id][stage];var track_ids: Array=[]
				for track in compiled.tracks:track_ids.append(resources.add_track(track))
				# 載せられなかったトラック（-1）は登録しない。-1 のまま使うと配列の最後の別トラックを指してしまう。
				if track_ids.has(-1):
					push_warning("2体場面を載せられません: %s %s %s（%s）"%[key,id,stage,resources.last_error])
					continue
				pair_sets[key][id][stage]={"compiled":compiled,"ids":track_ids}
	pair_data=pair_sets.get(Library.key("0","1"),{})
	for id in rows:update_face_remap(id)
	# 部位の重ね順ごとの形は、ここで作っておく（install で作ると画面が止まる）。
	for track in resources.tracks:
		for direction in track.orders:
			for order in direction:world.plans.get_mesh(order)
	pending={"recipes":recipes,"handles":handles}
	return true

## 読み込みの後半：描画ノードを作って木に載せる。メインスレッドで呼ぶ。
func prepare_finish() -> bool:
	var recipes: Array=pending.get("recipes",[]);var handles: Array=pending.get("handles",[])
	pending={}
	add_child(world)
	world.install({"store":resources,"recipes":recipes,"handles":handles,"next_handles":[],"warmed":true})
	world.speeds.fill(1.0)
	world.paused=true
	for node in world.meshes:node.visible=false
	ready_ms=Time.get_ticks_msec()-prepare_begin
	return true
func play_actor_clip(value: Variant,clip: String,restart: bool=false,mode: String="") -> void:
	var id: String=entity(value)
	if id=="" or (clips[id]==clip and not restart):return
	var index: String=profiles[id]
	if not tracks[index].has(clip):clip="idle"
	clips[id]=clip;world.track_ids[rows[id]]=tracks[index][clip]
	world.phases[rows[id]]=0.0;world.cursors[rows[id]]=0
	playback[id].elapsed=0.0
	playback[id].mode=mode if mode!="" else ("hold" if clip in ["captured","defeated","down"] else ("once" if clip in ["hit","attack","weak_attack","attack_heavy","cast","rise"] else "loop"))
func display(id: String,point: Vector2,yaw: int,clip: String,show_actor: bool=true,action: int=-1,motion_time: float=-1.0) -> void:
	if not rows.has(id):return
	latest[id]={"point":point,"yaw":yaw,"clip":clip,"show":show_actor,"action":action}
	var restart: bool=action>=0 and action!=int(playback[id].action) and clip in ["attack","hit","weak_attack","attack_heavy","cast","rise"]
	if action>=0:playback[id].action=action
	var rkey: String=profiles[id]+"|"+clip
	if not resolved_calls.has(rkey):resolved_calls[rkey]=Calls.resolve(call_settings,profiles[id],clip)
	var assignment: Dictionary=resolved_calls[rkey]
	play_actor_clip(id,assignment.clip,restart,assignment.mode)
	playback[id].mode=assignment.mode
	playback[id].speed=float(assignment.speed)
	if motion_time>=0:playback[id].elapsed=motion_time*float(assignment.speed)
	var row: int=rows[id]
	world.meshes[row].position=point;world.meshes[row].z_index=clampi(int(point.y)+2000,-4000,4000)
	var now_visible: bool=show_actor and not world.external_rows.has(row)
	if now_visible and not world.meshes[row].visible:urgent=true
	world.meshes[row].visible=now_visible
	world.directions[row]=posmod(yaw+4,8)
	world.recipes[row].height=heights[id]*appearance_heights.get(id,1.0)*body_height(id)
	if not world.external_rows.has(row):resources.set_state(row,5,prop_state(id,{}))
## 原型×行動 → 割り当て（Calls.resolve の結果。割り当てを読み直したら空にする）
var resolved_calls: Dictionary={}
func hide_all():
	for node in world.meshes:node.visible=false
## 次の advance をすぐ回してほしい（新しく見えた役者・流し始めた場面。間引いているときに古い姿勢を出さない）。
var urgent:=false
func advance(delta: float):
	urgent=false
	if stream or needs_commit or needs_binding:sync_stream()
	for id in rows:
		var row: int=rows[id]
		# 場面の中の役者（場面が描く）と、見えていない役者は進めない。
		if world.external_rows.has(row) or not world.meshes[row].visible:continue
		var track: Dictionary=resources.tracks[world.track_ids[row]]
		var state: Dictionary=playback[id];state.elapsed+=delta*float(state.speed)
		world.phases[row]=fposmod(state.elapsed/track.duration,1.0) if state.mode=="loop" else minf(.999999,state.elapsed/track.duration)
	world.state_dirty=true;world.update_world(0,false)
	for key in pairs.keys():
		var p: Dictionary=pairs[key]
		if p.has("anchor"):
			# 動く場面（担いで運ぶ・視点を回す牧場）。位置はゲームが follow_pair で渡す。
			p.node.position=p.anchor
			p.node.z_index=clampi(int(p.anchor.y)+2000+int(p.get("z_bias",0)),-4000,4000)
		else:
			var invalid: bool=false
			for id in p.actors:
				if not latest.has(id) or not latest[id].show or latest[id].point.distance_to(p.origins[id])>PAIR_DRIFT:invalid=true
			if invalid:stop_pair_scene(key,"actor_invalid");continue
			# 被弾の揺れ程度の移動には追従する。
			p.node.position=actors_center(p.actors)+p.offset
		p.total+=delta
		# 流れ（sequence）の区切りでの一瞬の停止（pause 秒）。その間は位相を進めない。
		if float(p.get("pause",0.0))>0.0:p.pause=float(p.pause)-delta
		else:p.elapsed+=delta
		if p.total>=p.max_seconds:stop_pair_scene(key,"completed");continue
		if p.elapsed>=p.duration and p.has("sequence"):
			if not advance_sequence(key,p):continue
		elif p.elapsed>=p.duration:
			p.elapsed-=p.duration
			if p.pending!="":
				var data: Dictionary=pair_entry(p.key,p.scene,p.pending)
				p.stage=p.pending;p.pending="";p.duration=data.compiled.tracks[0].duration
				p.node.configure(resources,data.compiled,data.ids,actor_rows(p.actors));p.node.cursor=0
		for i in p.actors.size():
			var overrides=p.get("props",[])
			resources.set_state(rows[p.actors[i]],5,prop_state(p.actors[i],overrides[i] if i<overrides.size() and overrides[i] is Dictionary else {},true))
		p.node.update_frame(fposmod(p.elapsed/p.duration,1.0),false)
		# 表情を固定した役者は、場面の顔の代わりにその表情
		for fid in p.actors:
			if not forced_faces.has(fid):continue
			var fb: Dictionary=id_face_banks.get(fid,face_banks.get(profiles.get(fid,""),{}))
			if fb.has(forced_faces[fid]):
				var base: int=int(fb[forced_faces[fid]])
				resources.face_overrides[rows[fid]]=base;resources.set_state(rows[fid],4,Vector4(base,1,0,0))
	for id in rows:
		if world.external_rows.has(rows[id]) or not world.meshes[rows[id]].visible:continue
		var index: String=profiles[id]
		if index=="" or not face_banks.has(index):continue
		var bank: Dictionary=id_face_banks.get(id,face_banks[index])
		resources.set_state(rows[id],4,Vector4(bank.get(forced_faces.get(id,expressions[id]),bank.neutral),1,0,0))
	resources.upload_state()

# ───────── 分けて読む動作（packs。ゲームの起動で使う） ─────────
# 起動時は目録と原型のレシピだけを読み、役者を原型に結び付けたとき（bind_row）にその原型の動作を、
# 2体場面を流すとき（pair_entry）にその組み合わせの場面を読む。動作のページがいっぱいになったら、
# 使っていない場面・原型から外す。管理ツールと確認コマンドは今までどおり prepare（全部を読む）を使う。
const Pack=preload("res://game_v2/animation/pack.gd")
## 動作の置き場のページ数（1ページ1MiB）。確認のために小さくできる。
var motion_pages:=64
var stream:=false
var pack_index: Dictionary={}
var pack_recipes: Dictionary={}
var loaded_profiles: Dictionary={}   # 原型 → true
var loaded_pairs: Dictionary={}      # "組み合わせ/場面" → {key, scene, ids, used}
var needs_commit:=false
var needs_binding:=false

## 読み込みの前半（別スレッドで呼んでよい）。packs が古い・無いときは false（呼び出し側は prepare に戻る）。
func prepare_stream(row_count: int) -> bool:
	Recipes.reset()
	var begin=Time.get_ticks_msec()
	prepare_begin=begin
	if not Pack.fresh():error="packs が無いか古い（焼き込みで作り直される）";return false
	stream=true
	call_settings=Calls.read()
	pack_index=Pack.index()
	var rf:=FileAccess.open(Pack.DIR+"recipes.pack",FileAccess.READ)
	pack_recipes=rf.get_var() if rf!=null else {}
	resources=Store.new(false)
	resources.begin_stream(motion_pages)
	# 結び付ける前の役者は、いちばん軽い原型（ゴブリン）の待機を指しておく（見えない）。
	if not ensure_profile("1"):return false
	var recipes: Array=[];var handles: Array=[]
	for i in row_count:
		var id:="r%d"%i
		rows[id]=i;profiles[id]="";clips[id]="idle";heights[id]=1.0;appearance_heights[id]=1.0
		playback[id]={"elapsed":0.0,"mode":"loop","speed":1.0,"action":-1};generations.append(1)
		expressions[id]="neutral"
		recipes.append({"seed":100+i,"height":1.0});handles.append(tracks["1"].idle)
	pending={"recipes":recipes,"handles":handles}
	return true

func recipe_for(profile: String) -> Dictionary:
	var recipe: Dictionary=pack_recipes.get(profile,{}).duplicate(true)
	if recipe.is_empty():recipe=built_in_recipe(profile)
	Profiles.with_soft(profile,recipe)
	return recipe

func add_packed(meta: Dictionary,raw: PackedByteArray) -> int:
	var id: int=resources.add_track_packed(meta,raw)
	while id==-2 and evict_one():id=resources.add_track_packed(meta,raw)
	if id<0:error="動作を載せられない: "+resources.last_error
	return id

## 原型の単体動作と顔を読む。
func ensure_profile(profile: String) -> bool:
	if loaded_profiles.has(profile):return true
	var rig: String=Profiles.rig(profile)
	if rig!=profile:
		# 見た目だけの原型：骨格の動作を読み、同じトラックを指す（顔は見た目のもの）。
		if not ensure_profile(rig):return false
		tracks[profile]=tracks[rig]
	else:
		var file: String=str(pack_index.get("clips",{}).get(profile,""))
		if file=="":error="動作の無い原型: "+profile;return false
		var d: Dictionary=Pack.read_pack(file)
		if d.is_empty():error="読めない: "+file;return false
		var head: Dictionary=d.head
		tracks[profile]={}
		for i in head.order.size():
			var clip: String=head.order[i]
			var id: int=add_packed(head.clips[clip],d.raws[i])
			if id<0:return false
			tracks[profile][clip]=id
	loaded_profiles[profile]=true
	if not face_banks.has(profile):
		face_banks[profile]=face_bank_for(recipe_for(profile))
		needs_commit=true
	return true

## 役者を原型に結び付ける（前と同じ原型なら何もしない）。
func bind_row(id: String,profile: String) -> bool:
	if not rows.has(id):return false
	if profiles[id]==profile:return true
	if not ensure_profile(profile):return false
	var row: int=rows[id]
	clear_parts_state(id)
	var before: Array=[resources.body_cell,resources.face_cell,resources.views.size()]
	var recipe: Dictionary=recipe_for(profile)
	recipe.seed=100+row
	prop_ids[id]=Profiles.info(profile).get("props",{}).duplicate()
	prop_states.erase(id)
	recipe.props=Props.resolve_all(prop_ids[id])
	var idle: Dictionary=resources.tracks[tracks[profile].idle]
	resources.bind_actor(row,recipe,idle.rest_radii)
	var outfits: Dictionary=Profiles.outfits(profile)
	if not outfits.is_empty():resources.bind_outfits(row,recipe,outfits)
	world.recipes[row]=recipe
	profiles[id]=profile
	heights[id]=float(Profiles.info(profile).get("height",1.0))
	appearance_heights[id]=float(recipe.get("height",1.0)) if pack_recipes.has(profile) else 1.0
	world.track_ids[row]=tracks[profile].idle;clips[id]="idle"
	expressions[id]="neutral"
	update_face_remap(id)
	# 絵のページが増えたときだけ全部を作り直す。増えなければ結び付けの表だけ送る。
	if before!=[resources.body_cell,resources.face_cell,resources.views.size()]:needs_commit=true
	else:needs_binding=true
	return true

func sync_stream() -> void:
	if needs_commit:
		resources.dirty=true;resources.commit();needs_commit=false;needs_binding=false
	elif needs_binding:
		resources.update_binding();needs_binding=false
	resources.flush_uploads()

## 2体場面の組み合わせを読む（まだなら）。
func ensure_pair(key: String,scene_id: String) -> bool:
	var ks:=key+"/"+scene_id
	if loaded_pairs.has(ks):loaded_pairs[ks].used=Time.get_ticks_msec();return true
	var entry: Dictionary=pack_index.get("pairs",{}).get(key,{}).get(scene_id,{})
	if entry.is_empty():return false
	var d: Dictionary=Pack.read_pack(str(entry.file))
	if d.is_empty():return false
	if not pair_sets.has(key):pair_sets[key]={}
	pair_sets[key][scene_id]={}
	var ri:=0;var all_ids: Array=[]
	for stage in d.head.stages:
		var compiled: Dictionary=d.head.stages[stage];var ids: Array=[]
		for meta in compiled.tracks:
			var id: int=add_packed(meta,d.raws[ri]);ri+=1
			if id<0:pair_sets[key].erase(scene_id);return false
			ids.append(id)
		pair_sets[key][scene_id][stage]={"compiled":compiled,"ids":ids}
		all_ids.append_array(ids)
	loaded_pairs[ks]={"key":key,"scene":scene_id,"ids":all_ids,"used":Time.get_ticks_msec()}
	return true

## 空きが足りないとき、使っていないものを1つ外す。外せたら true。
func evict_one() -> bool:
	# 流していない2体場面のうち、いちばん前に使ったもの
	var playing: Dictionary={}
	for h in pairs:playing[pairs[h].key+"/"+pairs[h].scene]=true
	var oldest:="";var t:=INF
	for ks in loaded_pairs:
		if playing.has(ks):continue
		if float(loaded_pairs[ks].used)<t:t=float(loaded_pairs[ks].used);oldest=ks
	if oldest!="":
		var lp: Dictionary=loaded_pairs[oldest]
		for id in lp.ids:resources.release_track(id)
		pair_sets[lp.key].erase(lp.scene)
		loaded_pairs.erase(oldest)
		return true
	# 使っている役者のいない原型
	var used: Dictionary={"1":true}
	for id in rows:
		if latest.has(id):used[profiles[id]]=true;used[Profiles.rig(profiles[id])]=true
	# 見た目だけの原型を先に外す（トラックは骨格のものなので外さない）。
	var order: Array=loaded_profiles.keys().filter(func(p):return not Profiles.is_rig(p))+loaded_profiles.keys().filter(func(p):return Profiles.is_rig(p))
	for profile in order:
		if used.has(profile):continue
		if Profiles.is_rig(profile) and loaded_profiles.keys().any(func(p):return p!=profile and Profiles.rig(p)==profile):continue
		for id in rows:
			if profiles[id]==profile:
				profiles[id]="";world.track_ids[rows[id]]=tracks["1"].idle
				clear_parts_state(id)
		if Profiles.is_rig(profile):
			for clip in tracks[profile]:resources.release_track(tracks[profile][clip])
		tracks.erase(profile);loaded_profiles.erase(profile)
		return true
	return false
## mirror=true で左右反転して描く（相手が反対側から来たとき用）。表示の角度は場面の actors[].yaw で決まる。
## 1体だけの場面（配役の相手が空）は b に "" を渡す。
func play_pair_scene(a_value: Variant,b_value: Variant,scene_id: String,stage: String="default",anchor: Variant=null,max_seconds: float=PAIR_SECONDS,mirror: bool=false) -> int:
	var a: String=entity(a_value);var b: String=entity(b_value)
	if a=="" or pairs.size()>=max_pairs:return -1
	var cast: Array=[a] if b=="" else [a,b]
	for id in cast:
		if not latest.has(id):return -1
	var key: String=pair_key(a,b)
	if pair_entry(key,scene_id,stage).is_empty():return -1
	for p in pairs.values():
		for id in cast:
			if id in p.actors:return -1
	var data: Dictionary=pair_entry(key,scene_id,stage)
	# 描画ノードは使い回す（作っては捨てない）。材質は描く順を決めるとき（apply_runs）に役者の行ごとのものを当てる。
	var node=pair_pool.pop_back() if not pair_pool.is_empty() else null
	if node==null:
		node=Spare.take_pair()
		if node!=null:add_child(node)
	if node==null:node=Pair.new();add_child(node)
	node.visible=true;node.signature="";node.phase=0.0;node.cursor=0;node.free_yaw=NAN;node.pitch=15.0
	urgent=true
	node.scale=Vector2.ONE;node.z_index=0
	node.size_factor=body_height(a)
	node.configure(resources,data.compiled,data.ids,actor_rows(cast))
	node.pixels_per_unit=82.0/2.45;node.direction=0
	if mirror:node.scale.x=-1.0
	var mesh_center:=Vector2.ZERO
	for id in cast:mesh_center+=world.meshes[rows[id]].position/float(cast.size())
	node.position=mesh_center
	if anchor!=null:node.position=anchor
	var offset: Vector2=node.position-actors_center(cast)
	node.z_index=clampi(int(node.position.y)+2000,-4000,4000)
	var origins: Dictionary={}
	for id in cast:
		world.external_rows[rows[id]]=true;world.meshes[rows[id]].visible=false;origins[id]=latest[id].point
	var handle: int=sequence;sequence+=1
	pairs[handle]={"node":node,"props":data.compiled.get("props",[]),"elapsed":0.0,"duration":data.compiled.tracks[0].duration,"actors":cast,"total":0.0,"max_seconds":max_seconds,"scene":scene_id,"stage":stage,"key":key,"pending":"","offset":offset,"origins":origins}
	node.update_frame(0,false)
	return handle
## 場面の流れ（sequence）で再生する。例：導入を2周 → 強を3周 → 絶頂を1回（合図・一瞬停止）→ 余韻で止める。
## 場面JSONの sequence = [{stage, cycles(既定1), hold(最後の姿勢で止めて待つ), cue(合図の名前), pause(区切りで止める秒)}]。
## 区切りに入るたび pair_cue(handle, cue) を出す（ゲームが効果音・画面の揺れ・光を出す）。hold が無ければ最後まで流して終わる。
## sequence が無い場面は play_pair_scene(default) と同じ。max_seconds の既定は上限なし。
signal pair_cue(handle: int,cue: String)
func play_pair_sequence(a_value: Variant,b_value: Variant,scene_id: String,anchor: Variant=null,max_seconds: float=INF,mirror: bool=false) -> int:
	var a: String=entity(a_value);var b: String=entity(b_value)
	if a=="":return -1
	var sequence: Array=pair_entry(pair_key(a,b),scene_id,"default").get("compiled",{}).get("sequence",[])
	if sequence.is_empty():return play_pair_scene(a,b,scene_id,"default",anchor,max_seconds,mirror)
	var handle: int=play_pair_scene(a,b,scene_id,str(sequence[0].stage),anchor,max_seconds,mirror)
	if handle<0:return -1
	var p: Dictionary=pairs[handle]
	p.sequence=sequence;p.seq_index=0;p.cycles_left=maxi(1,int(sequence[0].get("cycles",1)))
	p.pause=float(sequence[0].get("pause",0.0))
	if str(sequence[0].get("cue",""))!="":pair_cue.emit(handle,str(sequence[0].cue))
	return handle

## 1周が終わったときの流れの処理。場面を止めたら false。
func advance_sequence(handle: int,p: Dictionary) -> bool:
	var step: Dictionary=p.sequence[p.seq_index]
	if bool(step.get("hold",false)):
		p.elapsed=p.duration*0.9999;return true
	p.cycles_left=int(p.cycles_left)-1
	if p.cycles_left>0:
		p.elapsed-=p.duration;return true
	if p.seq_index+1>=p.sequence.size():
		stop_pair_scene(handle,"completed");return false
	p.seq_index+=1
	var next: Dictionary=p.sequence[p.seq_index]
	var data: Dictionary=pair_entry(p.key,p.scene,str(next.stage))
	if data.is_empty():stop_pair_scene(handle,"stage_missing");return false
	p.elapsed-=p.duration
	p.stage=str(next.stage);p.duration=data.compiled.tracks[0].duration
	p.node.configure(resources,data.compiled,data.ids,actor_rows(p.actors));p.node.cursor=0
	p.props=data.compiled.get("props",[])
	p.cycles_left=maxi(1,int(next.get("cycles",1)))
	p.pause=float(next.get("pause",0.0))
	if str(next.get("cue",""))!="":pair_cue.emit(handle,str(next.cue))
	return true

## 場面の役者の表示行（1体の場面は1つ）。
func actor_rows(cast: Array) -> Array:
	var out: Array=[]
	for id in cast:out.append(rows[id])
	return out

## 場面の役者の表示位置の中心。
func actors_center(cast: Array) -> Vector2:
	var c:=Vector2.ZERO
	for id in cast:c+=latest[id].point/float(cast.size())
	return c

## 役者2人の組み合わせの名前。場面は骨格ごとに焼くので、見た目だけの原型は骨格の名前になる。
func pair_key(a: String,b: String) -> String:
	return Library.key(Profiles.rig(profiles[a]),Profiles.rig(profiles[b]) if b!="" else "")

## 組み合わせ（"受け側原型|相手原型"。1体の場面は "受け側原型|"）に合わせて焼いた場面を返す。無ければ空。
func pair_entry(key: String,scene_id: String,stage: String) -> Dictionary:
	if stream and not pair_sets.get(key,{}).has(scene_id):ensure_pair(key,scene_id)
	var ks:=key+"/"+scene_id
	if loaded_pairs.has(ks):loaded_pairs[ks].used=Time.get_ticks_msec()
	return pair_sets.get(key,{}).get(scene_id,{}).get(stage,{})
## 焼いていない場面を後から登録する（確認コマンド・ツールのプレビュー用）。GPUへ送り直すので重い。
func add_pair_scene(key: String,scene_id: String,stage: String,compiled: Dictionary) -> bool:
	var track_ids: Array=[]
	for track in compiled.tracks:
		var id: int=resources.add_track(track)
		if id<0:error=str(resources.last_error);return false
		track_ids.append(id)
	if not pair_sets.has(key):pair_sets[key]={}
	if not pair_sets[key].has(scene_id):pair_sets[key][scene_id]={}
	pair_sets[key][scene_id][stage]={"compiled":compiled,"ids":track_ids}
	resources.commit()
	return true
## 読み込み済みの全場面ID。
func pair_scene_ids() -> Array:
	var result: Array=[]
	for key in pair_sets:
		for id in pair_sets[key]:
			if not id in result:result.append(id)
	result.sort()
	return result
## その組み合わせで焼けている段階（未対応なら空）。
func pair_stages(taker_profile: String,partner_profile: String,scene_id: String) -> Array:
	var key: String=Library.key(Profiles.rig(taker_profile),Profiles.rig(partner_profile) if partner_profile!="" else "")
	if stream:return pack_index.get("pairs",{}).get(key,{}).get(scene_id,{}).get("stages",[])
	return pair_sets.get(key,{}).get(scene_id,{}).keys()
## 登録簿の組み込み原型からレシピを作る。未登録なら数値IDとして扱う（旧来の互換）。
func built_in_recipe(index: String,seed_value: int=1) -> Dictionary:
	var entry: Dictionary=Profiles.info(index)
	var made: Dictionary=Recipes.make(int(entry.get("make",int(index))),seed_value)
	if entry.has("head_scale"):made.head_scale=float(entry.head_scale)
	return made
func queue_pair_scene_stage(handle: int,stage: String,marker: String="cycle_start") -> Dictionary:
	if not pairs.has(handle):return {"ok":false,"reason":"終了済みの場面"}
	var p: Dictionary=pairs[handle]
	if marker!="cycle_start" or pair_entry(p.key,p.scene,stage).is_empty():return {"ok":false,"reason":"未登録の段階または境界"}
	p.pending=stage
	return {"ok":true}
func stop_pair_scene(handle: int,reason: String="cancelled"):
	if not pairs.has(handle):return
	var pair: Dictionary=pairs[handle]
	var restored:=false
	for id in pair.actors:
		# 場面で着替えていたら元の服へ戻す。
		if resources.apply_outfit(rows[id],""):restored=true
		world.external_rows.erase(rows[id])
		if latest.has(id):
			var v: Dictionary=latest[id]
			display(id,v.point,v.yaw,v.clip,v.show,v.action)
		else:world.meshes[rows[id]].visible=false
	if restored:resources.update_binding()
	pair.node.visible=false;pair_pool.append(pair.node);pairs.erase(handle)
	scene_finished.emit(handle,reason)

func stop_all():
	for key in pairs.keys():stop_pair_scene(key,"cancelled")
func spawn_actor(id: String) -> Vector2i:
	if not rows.has(id):return Vector2i(-1,-1)
	return Vector2i(rows[id],generations[rows[id]])
func entity(handle: Variant) -> String:
	if handle is String:return handle if rows.has(handle) else ""
	if not handle is Vector2i or handle.x<0 or handle.x>=generations.size() or generations[handle.x]!=handle.y:return ""
	return str(rows.find_key(handle.x))
func despawn_actor(handle: Variant):
	var id: String=entity(handle)
	if id=="":return
	for key in pairs.keys():
		if id in pairs[key].actors:stop_pair_scene(key,"actor_invalid")
	latest.erase(id);world.meshes[rows[id]].visible=false;generations[rows[id]]+=1
func set_actor_position(handle: Variant,point: Vector2):
	var id: String=entity(handle)
	if id!="":world.meshes[rows[id]].position=point
func set_actor_direction(handle: Variant,direction: int):
	var id: String=entity(handle)
	if id!="":world.directions[rows[id]]=posmod(direction+4,8)
func set_actor_scale(handle: Variant,display_height: float):
	var id: String=entity(handle)
	if id!="":heights[id]=clampf(display_height/82.0,.5,2.0)
func set_actor_playback_speed(handle: Variant,value: float) -> bool:
	var id: String=entity(handle)
	if id=="" or value<0 or value>1.9:return false
	playback[id].speed=value;return true
## 動く場面にする（以後、場面の位置は latest ではなく point で決まる）。mirror で左右を切り替える。
func follow_pair(handle: int,point: Vector2,mirror: bool=false,z_bias: int=0) -> void:
	if not pairs.has(handle):return
	var p: Dictionary=pairs[handle]
	p.anchor=point;p.z_bias=z_bias
	# 位置はすぐ反映する（アニメーションの更新を間引いても、画面を動かしたときに場面が遅れない）。
	p.node.position=point;p.node.z_index=clampi(int(point.y)+2000+z_bias,-4000,4000)
	p.node.scale.x=-absf(p.node.scale.x) if mirror else absf(p.node.scale.x)
## 場面を見る向き。direction は45度刻み（描く順番もこれで決まる）、free_yaw は途中の角度（度、NAN で direction どおり）。
func set_pair_view(handle: int,direction: int,free_yaw: float=NAN,pitch_deg: float=15.0,pixels: float=-1.0) -> void:
	if not pairs.has(handle):return
	var node=pairs[handle].node
	node.direction=posmod(direction,8);node.free_yaw=free_yaw;node.pitch=pitch_deg
	if pixels>0:node.pixels_per_unit=pixels
## 単体の役者の色（素材が届くまで同じ体型を見分ける仮の色）と、大きさの倍率（原型の高さに掛ける）。
func set_actor_tint(handle: Variant,color: Color) -> void:
	var id: String=entity(handle)
	if id!="":world.meshes[rows[id]].modulate=color
func set_actor_height(handle: Variant,factor: float) -> void:
	var id: String=entity(handle)
	if id!="":heights[id]=float(Profiles.info(profiles[id]).get("height",1.0))*factor
## 体型（素体規格の値。1が標準）。{height 身長, thickness 太さ, breast 胸, butt 尻}。
## 太さ・胸・尻は描画の束縛表を書き直す（動作の焼き直しは要らない）。身長は表示の倍率で、2体場面では場面全体を受け側の身長で拡大・縮小する。
var bodies: Dictionary={}
func set_actor_body(handle: Variant,body: Dictionary) -> bool:
	var id: String=entity(handle)
	if id=="" or profiles.get(id,"")=="" or not tracks.has(profiles[id]):return false
	bodies[id]=body.duplicate()
	var row: int=rows[id]
	var recipe: Dictionary=world.recipes[row]
	recipe.thickness=float(body.get("thickness",1.0))
	recipe.breast=float(body.get("breast",1.0))
	recipe.butt=float(body.get("butt",1.0))
	var idle: Dictionary=resources.tracks[tracks[profiles[id]].idle]
	resources.bind_actor(row,recipe,idle.rest_radii)
	var outfits: Dictionary=Profiles.outfits(profiles[id])
	if not outfits.is_empty():resources.bind_outfits(row,recipe,outfits)
	resources.update_binding()
	return true

# ───────── 部品の着せ替え（game_v2/animation/parts.gd） ─────────
var part_sets: Dictionary={}      # 役者 → {部位: 原型}
var part_origins: Dictionary={}   # 役者 → 着せ替える前の {modules, face}
var id_face_banks: Dictionary={}  # 役者 → {表情: 顔の番号}（頭を替えたときだけ。無ければ原型の face_banks）
## 部位ごとに別のキャラの部品を着せる。{"head": "std_knight", "arms": "std_ranger", ...}。{} で原型の見た目に戻す。
## 書かない部位は原型のまま。動作・2体場面は原型のものを使うので、焼き直しは要らない。
func set_actor_parts(handle: Variant,parts: Dictionary) -> bool:
	var id: String=entity(handle)
	if id=="" or profiles.get(id,"")=="" or not tracks.has(profiles[id]):return false
	var profile: String=profiles[id]
	var row: int=rows[id]
	var recipe: Dictionary=world.recipes[row]
	if not part_origins.has(id):part_origins[id]={"modules":recipe.modules.duplicate(),"face":recipe.get("face",{}).duplicate()}
	var origin: Dictionary=part_origins[id]
	recipe.modules=origin.modules.duplicate();recipe.face=origin.face.duplicate()
	for m in parts:
		var index: int=Parts.index_of(str(parts[m]))
		if index>=0 and recipe.modules.has(m):recipe.modules[m]=index
	# 顔の部品（目・眉・口）は頭と同じキャラから取る。顔の部品（eyes / brows / mouth）を書けば、その枠だけ別のキャラの顔から。
	var face_changed: bool=int(recipe.modules.head)!=int(origin.modules.head)
	if face_changed:
		for k in recipe.face:recipe.face[k]=int(recipe.modules.head)
	for m in Parts.FACE_MODULES:
		if not parts.has(m):continue
		var index: int=Parts.index_of(str(parts[m]))
		if index<0:continue
		for slot in Parts.FACE_MODULES[m]:
			if recipe.face.has(slot) and int(recipe.face[slot])!=index:recipe.face[slot]=index;face_changed=true
	var before: Array=[resources.body_cell,resources.face_cell,resources.views.size()]
	var idle: Dictionary=resources.tracks[tracks[profile].idle]
	resources.bind_actor(row,recipe,idle.rest_radii)
	var outfits: Dictionary=Profiles.outfits(profile)
	if not outfits.is_empty():resources.bind_outfits(row,recipe,outfits)
	# 頭か顔の部品を替えたら、表情の顔も新しい顔のものにする（2体場面の焼いた顔も読み替える）。
	if face_changed:id_face_banks[id]=face_bank_for(recipe)
	else:id_face_banks.erase(id)
	update_face_remap(id)
	if parts.is_empty():part_sets.erase(id);part_origins.erase(id)
	else:part_sets[id]=parts.duplicate()
	if before!=[resources.body_cell,resources.face_cell,resources.views.size()]:needs_commit=true
	else:needs_binding=true
	return true

func actor_parts(handle: Variant) -> Dictionary:
	return part_sets.get(entity(handle),{})

func clear_parts_state(id: String) -> void:
	part_sets.erase(id);part_origins.erase(id);id_face_banks.erase(id)
	if rows.has(id):resources.face_remap.erase(rows[id])

## 表情の顔の番号 {名前: 番号} を作る。通常（neutral）・目を閉じる（closed）・顔の登録の表情（preset。wink など）・
## 一枚絵の顔の表情差分（expression_atlases）。set_actor_expression(名前) で切り替える。
func face_bank_for(recipe: Dictionary) -> Dictionary:
	var bank: Dictionary={"neutral":resources.face_view_base(recipe)}
	var closed: Dictionary=recipe.duplicate(true);closed.expression={"eye_l":"closed","eye_r":"closed"}
	if resources.catalog.validate(closed)=="":
		var b: int=resources.face_view_base(closed)
		if b>=0:bank.closed=b
	var config: Dictionary=resources.catalog.configs[int(recipe.modules.head)] if recipe.has("modules") and int(recipe.modules.head)<resources.catalog.configs.size() else {}
	if str(config.get("face",{}).get("mode","registered"))=="registered":
		var presets: Dictionary=config.get("face",{}).get("registered",{}).get("presets",{})
		for name in presets:
			if name in ["neutral","blink"] or bank.has(name):continue
			var variant: Dictionary=recipe.duplicate(true);variant.expression=presets[name].duplicate()
			if resources.catalog.validate(variant)=="":
				var b: int=resources.face_view_base(variant)
				if b>=0:bank[name]=b
	for name in recipe.get("asset_face",{}).get("expression_atlases",{}):
		if bank.has(name):continue
		var variant: Dictionary=recipe.duplicate(true);variant.expression={"baked":str(name)}
		if resources.catalog.validate(variant)=="":bank[name]=resources.face_view_base(variant)
	return bank

## 焼いた動作の顔（骨格の原型の頭で焼いてある）を、この役者の頭の同じ表情へ読み替える（無い表情はその頭の素の顔）。
## 見た目だけの原型（骨格が別）と、頭を別のキャラに替えた役者で要る。どちらでもなければ読み替えない。
func update_face_remap(id: String) -> void:
	if not rows.has(id):return
	var row: int=rows[id]
	var profile: String=profiles.get(id,"")
	var source: Dictionary=face_banks.get(Profiles.rig(profile),{}) if profile!="" else {}
	var target: Dictionary=id_face_banks.get(id,face_banks.get(profile,{}))
	if source.is_empty() or target.is_empty() or source==target:resources.face_remap.erase(row);return
	var map: Dictionary={}
	for name in source:map[int(source[name])]=int(target.get(name,target.neutral))
	resources.face_remap[row]={"map":map,"neutral":int(target.neutral)}

# ───────── 付属物（docs/素材制作テンプレート/付属物の規格.md） ─────────
var prop_ids: Dictionary={}      # 役者 → {枠名: 付属物ID}
var prop_states: Dictionary={}   # 役者 → {枠名: "show"|"hide"|"rest"|"erect"}（ゲームの指定）
## 付属物を付け替える。{"weapon_r": "sword_iron", "ears": "ears_cat", "tail": "", ...}。"" で外す。書かない枠はそのまま。
func set_actor_props(handle: Variant,assigned: Dictionary) -> bool:
	var id: String=entity(handle)
	if id=="" or profiles.get(id,"")=="":return false
	var merged: Dictionary=prop_ids.get(id,{}).duplicate()
	merged.merge(assigned,true)
	prop_ids[id]=merged
	var row: int=rows[id]
	world.recipes[row].props=Props.resolve_all(merged)
	var before: int=resources.views.size()
	resources.bind_props(row,world.recipes[row])
	if resources.views.size()!=before:needs_commit=true
	else:needs_binding=true
	return true

## 付属物と見せ方を原型の既定に戻す（役者を借り直したとき）。
func reset_actor_props(handle: Variant) -> void:
	var id: String=entity(handle)
	if id=="" or profiles.get(id,"")=="":return
	prop_states.erase(id)
	var defaults: Dictionary=Profiles.info(profiles[id]).get("props",{})
	if prop_ids.get(id,{})==defaults:return
	prop_ids[id]={}
	var cleared: Dictionary={}
	for slot in Props.Catalog.PROP_SLOTS:cleared[slot]=""
	cleared.merge(defaults,true)
	set_actor_props(id,cleared)

## 見せ方を指定する（"show" / "hide" / 男性器は "rest" / "erect"）。"" で既定に戻す。2体場面の指定が優先。
func set_prop_state(handle: Variant,slot: String,value: String) -> void:
	var id: String=entity(handle)
	if id=="":return
	if not prop_states.has(id):prop_states[id]={}
	if value=="":prop_states[id].erase(slot)
	else:prop_states[id][slot]=value

func prop_state(id: String,overrides: Dictionary,in_scene: bool=false) -> Vector4:
	var states: Dictionary=prop_states.get(id,{}).duplicate()
	states.merge(overrides,true)
	return Props.state(prop_ids.get(id,{}),states,str(clips.get(id,"")),in_scene)

func body_height(id: String) -> float:
	return float(bodies.get(id,{}).get("height",1.0))

## 場面の中でも表情を固定する役者 → 表情の名前（"" で外す）。場面の焼いた顔より優先する。
var forced_faces: Dictionary={}
func force_expression(handle: Variant,expression: String) -> void:
	var id: String=entity(handle)
	if id=="":return
	if expression=="":forced_faces.erase(id)
	else:forced_faces[id]=expression

func set_actor_expression(handle: Variant,expression: String) -> bool:
	var id: String=entity(handle)
	if id=="":return false
	var index: String=profiles[id]
	if not id_face_banks.get(id,face_banks[index]).has(expression):return false
	expressions[id]=expression;return true
