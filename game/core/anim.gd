extends Node
## アニメーションの窓口（設計書 3.4）。Bridge を1つだけ持ち、起動時に一度だけ準備して全画面で使い回す。
## ゲームは「行動名」と「出来事」だけを渡す。どの動作・場面を流すかは animation_calls.json（管理ツールで編集）で決まる。
const Bridge=preload("res://game_v2/animation/bridge.gd")
const Calls=preload("res://game_v2/animation/call_registry.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const G=preload("res://game/core/g.gd")
const Perf=preload("res://game/core/perf.gd")
## 原型ごとに用意しておく役者の数。画面は必要な数だけ借りて返す。
## 描画器の上限は256体（Catalog.CAPACITY）。
const POOL:={"0":56,"1":72}
signal cue(handle: int,name: String)
signal finished(handle: int,reason: String)
var bridge
var ready_ok:=false
var error:=""
var pool: Dictionary={}      # 原型 → [役者ID]
var free: Dictionary={}      # 原型 → [空いている役者ID]
var used: Dictionary={}      # 役者ID → true
var bindings: Array=[]
var host: Node=null

signal loaded
var loading:=false
var thread: Thread
var data_ok:=false
var ids: Array=[]
var map: Dictionary={}

## 分けて読む（packs）ときの役者の数。どの原型にも結び付けられる。描画器の上限（Catalog.CAPACITY）と同じ256体。
const ROWS:=256
var stream:=false
var free_rows: Array=[]

## すぐ終わる（確認コマンド用）。
func setup() -> bool:
	begin_setup()
	data_ok=load_data()
	finish_setup()
	return ready_ok

## ゲームの起動用：読み込みの前半を別スレッドで回し、終わったら loaded を出す（その間もタイトルは動く）。
func setup_async() -> void:
	begin_setup()
	loading=true
	if not OS.has_feature("threads"):
		# 読み込み画面を1回描いてから読む（その間は画面が止まる）。
		await get_tree().process_frame
		data_ok=load_data()
		loading=false
		finish_setup()
		return
	thread=Thread.new()
	thread.start(func():data_ok=load_data())

## packs が新しければ目録だけ読む（速い）。無い・古いときは今までどおり全部を読む。
func load_data() -> bool:
	# 動作の置き場（1ページ 256×256。GPU では 16bit で 0.5MB）。全場面を載せても約10ページ。足りなければ使っていない場面から外す。
	bridge.motion_pages=16 if Perf.lite else 32
	if bridge.prepare_stream(ROWS):
		stream=true
		return true
	# packs の判定は準備に入る前に行うので、同じ Bridge でそのまま全部を読める。
	push_warning("Anim: "+bridge.error+" → 全部を読む方式に戻す")
	bridge.stream=false
	for profile in POOL:
		if not profile in Profiles.ids():continue
		pool[profile]=[];free[profile]=[]
		for i in POOL[profile]:
			var id:="%s#%d"%[profile,i]
			ids.append(id);map[id]=profile
			pool[profile].append(id);free[profile].append(id)
	return bridge.prepare_data(ids,map,Profiles.bundle_paths())

func _process(_delta: float) -> void:
	if loading and thread!=null and not thread.is_alive():
		thread.wait_to_finish();thread=null;loading=false
		finish_setup()

func begin_setup() -> void:
	bridge=Bridge.new()
	bridge.name="Bridge"
	ids=[];map={}
	add_child(bridge)

func finish_setup() -> void:
	ready_ok=data_ok and bridge.prepare_finish()
	if ready_ok and stream:
		free_rows=[]
		for i in ROWS:free_rows.append("r%d"%i)
	error=bridge.error
	if not ready_ok:loaded.emit();return
	# 同時に流せる2体場面の数。役者（2人ずつ）の上限 ROWS の範囲なら実質いくつでも。
	bridge.max_pairs=ROWS/2
	bridge.pair_cue.connect(func(h,c):cue.emit(h,c))
	bridge.scene_finished.connect(func(h,r):finished.emit(h,r))
	bridge.visible=false
	bindings=Calls.read().get("events",[])
	loaded.emit()

func _exit_tree() -> void:
	if thread!=null:thread.wait_to_finish();thread=null

# ───────── 画面への付け外し ─────────
## 画面の世界ノードの下へ描画を移す。z_index で役者の前後が決まる。
func attach(parent: Node) -> void:
	if bridge==null:return
	release_all()
	bridge.get_parent().remove_child(bridge)
	parent.add_child(bridge)
	bridge.visible=true
	host=parent

func detach() -> void:
	if bridge==null:return
	release_all()
	if bridge.get_parent()!=self:
		bridge.get_parent().remove_child(bridge)
		add_child(bridge)
	bridge.visible=false
	bridge.world.pitch=PI/12
	host=null

# ───────── 役者を借りる ─────────
func acquire(profile: String) -> String:
	var id:=""
	if stream:
		if free_rows.is_empty():return ""
		# 同じ原型に結び付いたままの空きがあればそれを使う（結び直さずに済む）。
		for i in range(free_rows.size()-1,-1,-1):
			if bridge.profiles[free_rows[i]]==profile:id=free_rows[i];free_rows.remove_at(i);break
		if id=="":
			for i in range(free_rows.size()):
				if bridge.profiles[free_rows[i]]=="":id=free_rows[i];free_rows.remove_at(i);break
		if id=="":id=free_rows.pop_front()
		if not bridge.bind_row(id,profile):
			push_warning("Anim: "+bridge.error);free_rows.append(id);return ""
	else:
		if not free.has(profile):profile="0"
		if not free.has(profile) or free[profile].is_empty():return ""
		id=free[profile].pop_back()
	used[id]=true
	bridge.set_actor_tint(id,Color.WHITE)
	bridge.set_actor_height(id,1.0)
	bridge.set_actor_expression(id,"neutral")
	# 前に借りた者の体型が残らないよう、標準へ戻す。
	if bridge.bodies.has(id):bridge.set_actor_body(id,{});bridge.bodies.erase(id)
	bridge.reset_actor_props(id)
	# 前に借りた者の部品が残らないよう、原型の見た目へ戻す。
	if bridge.part_sets.has(id):bridge.set_actor_parts(id,{})
	return id

func release(id: String) -> void:
	if id=="" or not used.has(id):return
	for h in bridge.pairs.keys():
		if id in bridge.pairs[h].actors:bridge.stop_pair_scene(h,"released")
	used.erase(id)
	bridge.latest.erase(id)
	bridge.world.meshes[bridge.rows[id]].visible=false
	if stream:free_rows.append(id)
	else:free[bridge.profiles[id]].append(id)

func release_all() -> void:
	if bridge==null or not ready_ok:return
	bridge.stop_all()
	for id in used.keys():release(id)

func remaining(profile: String) -> int:
	if stream:return free_rows.size()
	return free.get(profile,[]).size()

# ───────── 役者を動かす ─────────
## 毎フレーム：位置（親ノードの座標）・向き（0〜7、2で画面の右向き）・行動名。
func place(id: String,point: Vector2,facing: int,action: String,shown: bool=true) -> void:
	if id=="":return
	bridge.display(id,point,facing,action,shown)

func act(id: String,action: String,restart: bool=false) -> void:
	if id=="" or not bridge.latest.has(id):return
	var v: Dictionary=bridge.latest[id]
	bridge.display(id,v.point,v.yaw,action,v.show,(Time.get_ticks_msec() if restart else -1))

func tint(id: String,color: Color) -> void:
	if id!="":bridge.set_actor_tint(id,color)

func height(id: String,factor: float) -> void:
	if id!="":bridge.set_actor_height(id,factor)

## 体型（素体規格の値 {height, thickness, breast, butt}。1が標準）。
func body(id: String,values: Dictionary) -> void:
	if id!="":bridge.set_actor_body(id,values)

## 部品の着せ替え（game_v2/animation/parts.gd）。{"head": "std_knight", "arms": "std_ranger", ...}。{} で原型の見た目。
func parts(id: String,assigned: Dictionary) -> void:
	if id=="":return
	if assigned.is_empty() and not bridge.part_sets.has(id):return
	bridge.set_actor_parts(id,assigned)

## 付属物（docs/素材制作テンプレート/付属物の規格.md）。{"weapon_r": "sword_iron", "ears": "ears_cat", ...}。"" で外す。
func props(id: String,assigned: Dictionary) -> void:
	if id!="":bridge.set_actor_props(id,assigned)

## 付属物の見せ方（"show" / "hide"、男性器は "rest" / "erect"）。"" で既定（武器は捕まると隠れる、男性器は隠す）。
func prop_state(id: String,slot: String,value: String) -> void:
	if id!="":bridge.set_prop_state(id,slot,value)

func expression(id: String,name: String) -> void:
	if id!="":bridge.set_actor_expression(id,name)

## 場面の中でも表情を固定する（"" で場面の表情に戻す）。その頭に無い表情は効かない。
func force_expression(id: String,name: String) -> void:
	if id!="":bridge.force_expression(id,name)

## 役者の頭が持つ表情の名前（通常・目を閉じる・ウインク・表情差分）。
func expressions_of(id: String) -> Array:
	if id=="" or not bridge.rows.has(id):return []
	return bridge.id_face_banks.get(id,bridge.face_banks.get(bridge.profiles.get(id,""),{})).keys()

## 場面を名指しで流す（施設ごとに選んだ場面）。流れ（sequence）のある場面は通しで流す。流せたら handle。
func play_scene(scene_id: String,a: String,b: String,anchor: Variant=null,follow: bool=false) -> int:
	if a=="" or scene_id=="":return -1
	var h: int=bridge.play_pair_sequence(a,b,scene_id,anchor,INF)
	if h>=0 and follow:bridge.follow_pair(h,anchor if anchor!=null else bridge.pairs[h].node.position)
	if h>=0 and G.state!=null:G.state.records.scenes["%s|"%scene_id]=true
	return h

func hide(id: String) -> void:
	if id=="" or not bridge.latest.has(id):return
	var v: Dictionary=bridge.latest[id]
	bridge.display(id,v.point,v.yaw,v.clip,false)

func set_pitch(radians: float) -> void:
	bridge.world.pitch=radians

## 軽量（Perf.lite）では姿勢の計算を毎秒30回に間引く。新しく見えた役者・流し始めた場面があればすぐ計算する。
var anim_acc:=0.0
func advance(delta: float) -> void:
	if bridge==null or not ready_ok:return
	var hz: float=Perf.anim_hz()
	if hz<=0.0:bridge.advance(delta);return
	anim_acc+=delta
	if anim_acc<1.0/hz-0.002 and not bridge.urgent:return
	bridge.advance(anim_acc);anim_acc=0.0

# ───────── 出来事 → 場面 ─────────
## 出来事の辞書 {kind, a: 女の役者ID, b: 相手の役者ID, target_definition_id, target_tags, source_definition_id, source_tags, room, phase, fall, capture}
## 場面を出せたら handle（>=0）、出せなければ -1。記号は choose(event).symbol。
func present(event: Dictionary,anchor: Variant=null,follow: bool=false,mirror: bool=false) -> int:
	var binding: Dictionary=choose(event)
	if binding.is_empty() or str(binding.get("pair_scene_id",""))=="":return -1
	# b が空なら1体だけの場面（出産など。配役の相手が空の場面だけが流れる）。
	var a: String=str(event.get("a",""));var b: String=str(event.get("b",""))
	if a=="":return -1
	var handle:=-1
	if str(binding.get("stage","default"))=="@sequence":
		handle=bridge.play_pair_sequence(a,b,binding.pair_scene_id,anchor,INF,mirror)
	else:
		handle=bridge.play_pair_scene(a,b,binding.pair_scene_id,str(binding.get("stage","default")),anchor,INF,mirror)
	if handle>=0 and follow:
		bridge.follow_pair(handle,anchor if anchor!=null else bridge.pairs[handle].node.position,mirror)
	if handle>=0:
		var key: String="%s|%s"%[binding.pair_scene_id,str(event.get("target_definition_id",event.get("room","")))]
		if G.state!=null:G.state.records.scenes[key]=true
	return handle

func choose(event: Dictionary) -> Dictionary:
	var best: Dictionary={};var best_rank:=-1
	for binding in bindings:
		if str(binding.get("event_kind",""))!=str(event.get("kind","")):continue
		var rank:=10
		if binding.has("target_definition_id"):
			if str(binding.target_definition_id)!=str(event.get("target_definition_id","")):continue
			rank=50
		elif binding.has("target_tag"):
			if not str(binding.target_tag) in event.get("target_tags",[]):continue
			rank=40
		elif binding.has("source_definition_id"):
			if str(binding.source_definition_id)!=str(event.get("source_definition_id","")):continue
			rank=30
		elif binding.has("source_tag"):
			if not str(binding.source_tag) in event.get("source_tags",[]):continue
			rank=20
		var valid:=true
		for key in ["room","phase","fall","capture"]:
			if binding.has(key):
				if str(binding[key])!=str(event.get(key,"")):valid=false;break
				rank+=1
		if not valid:continue
		if rank>best_rank:best=binding;best_rank=rank
	return best

func follow(handle: int,point: Vector2,mirror: bool=false,z_bias: int=0) -> void:
	if bridge.pairs.has(handle):bridge.follow_pair(handle,point,mirror,z_bias)

func view(handle: int,direction: int,free_yaw: float=NAN,pitch_deg: float=15.0,pixels: float=-1.0) -> void:
	bridge.set_pair_view(handle,direction,free_yaw,pitch_deg,pixels)

func playing(handle: int) -> bool:
	return bridge.pairs.has(handle)

func stop(handle: int) -> void:
	if bridge.pairs.has(handle):bridge.stop_pair_scene(handle,"stopped")

func queue_stage(handle: int,stage: String) -> void:
	if bridge.pairs.has(handle):bridge.queue_pair_scene_stage(handle,stage)

func pair_node(handle: int) -> Node2D:
	return bridge.pairs[handle].node if bridge.pairs.has(handle) else null

func pause_pair(handle: int,seconds: float) -> void:
	if bridge.pairs.has(handle):bridge.pairs[handle].pause=seconds
