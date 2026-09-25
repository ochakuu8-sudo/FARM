extends Control
## ゲームの入口。画面の切り替え・確認窓・通知・効果音をまとめて持つ（設計書 1.1）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Db=preload("res://game/core/db.gd")
const State=preload("res://game/core/state.gd")
const Save=preload("res://game/core/save.gd")
const Day=preload("res://game/core/day.gd")
const SCREENS:={
	"loading":"res://game/ui/screens/loading.gd",
	"title":"res://game/ui/screens/title.gd",
	"intro":"res://game/ui/screens/intro.gd",
	"ranch":"res://game/ui/screens/ranch.gd",
	"world":"res://game/ui/screens/world.gd",
	"prep":"res://game/ui/screens/prep.gd",
	"battle":"res://game/ui/screens/battle.gd",
	"ending":"res://game/ui/screens/ending.gd",
}
signal changed
var screen_root: Control
var overlay_root: Control
var toast_box: VBoxContainer
var fade: ColorRect
var current: Control
var current_name:=""
var busy:=false
var players: Array=[]
var sounds: Dictionary={}

func _ready() -> void:
	G.main=self
	# スマホ（軽量）はフレームを30までにする（毎フレームの重さを半分にし、熱と電池を抑える）
	if preload("res://game/core/perf.gd").lite:Engine.max_fps=30
	G.settings=Save.load_settings()
	var win:=get_window()
	win.content_scale_size=Vector2i(1920,1080)
	win.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	win.title="魔王の娘の魔物牧場（仮）"
	if not OS.has_feature("headless"):
		var screen_size:=DisplayServer.screen_get_usable_rect().size
		win.size=Vector2i(mini(1600,screen_size.x-80),mini(900,screen_size.y-80))
		win.position=(screen_size-win.size)/2
		if bool(G.settings.get("fullscreen",false)):win.mode=Window.MODE_FULLSCREEN
	theme=Ui.build_theme()
	Ui.full(self)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var back:=CanvasLayer.new();back.layer=-10;add_child(back)
	var bg:=ColorRect.new();bg.color=Ui.BG;Ui.full(bg);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;back.add_child(bg)
	var bg_mat:=ShaderMaterial.new();bg_mat.shader=load("res://game/ui/shaders/backdrop.gdshader");bg.material=bg_mat
	screen_root=Control.new();Ui.full(screen_root);screen_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(screen_root)
	overlay_root=Control.new();Ui.full(overlay_root);overlay_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay_root)
	toast_box=VBoxContainer.new();toast_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT);toast_box.position=Vector2(-460,90);toast_box.custom_minimum_size=Vector2(440,0)
	add_child(toast_box)
	fade=ColorRect.new();fade.color=Color(0,0,0,1);Ui.full(fade);fade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(fade)
	setup_audio()
	G.db=Db.new()
	G.db.load_all()
	G.state=State.new()
	goto("loading")

## 画面のスクリプトを先に読んでおく（タイトルで待っている間に1フレームに1つずつ）。
## 初めて開く画面はスクリプトの読み込み・コンパイルで止まる（ブラウザ版では数百ミリ秒〜1秒）ため。
func warm_up() -> void:
	for path in SCREENS.values():
		await get_tree().process_frame
		if current_name!="title":return
		load(path)

# ───────── 画面の切り替え ─────────
func goto(name: String,params: Dictionary={}) -> void:
	if busy:return
	busy=true
	if current!=null:
		var tw:=create_tween();tw.tween_property(fade,"color:a",1.0,0.18);await tw.finished
		if current.has_method("close"):current.close()
		current.queue_free();current=null
		close_all_overlays()
	var script=load(SCREENS[name])
	current=script.new()
	current.name=name
	Ui.full(current)
	current.mouse_filter=Control.MOUSE_FILTER_IGNORE
	current_name=name
	screen_root.add_child(current)
	if current.has_method("open"):current.open(params)
	var tw2:=create_tween();tw2.tween_property(fade,"color:a",0.0,0.22)
	busy=false

func refresh() -> void:
	changed.emit()

# ───────── 確認窓・重ねる窓 ─────────
func overlay(content: Control,dim: float=0.6,click_close: bool=false) -> Control:
	var layer:=Control.new();Ui.full(layer)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,dim);Ui.full(shade);layer.add_child(shade)
	if click_close:
		shade.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:close_overlay(layer))
	var center:=CenterContainer.new();Ui.full(center);center.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(center)
	center.add_child(content)
	overlay_root.add_child(layer)
	layer.modulate.a=0.0
	var tw:=layer.create_tween();tw.tween_property(layer,"modulate:a",1.0,0.16)
	content.pivot_offset=content.size*0.5
	content.scale=Vector2(0.97,0.97)
	content.resized.connect(func():content.pivot_offset=content.size*0.5,CONNECT_ONE_SHOT)
	var tw2:=content.create_tween();tw2.tween_property(content,"scale",Vector2.ONE,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return layer

func close_overlay(layer: Control=null) -> void:
	if layer==null or not is_instance_valid(layer):layer=top_overlay()
	if layer==null or layer.has_meta("closing"):return
	layer.set_meta("closing",true)
	layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var tw:=layer.create_tween();tw.tween_property(layer,"modulate:a",0.0,0.12);tw.tween_callback(layer.queue_free)

func top_overlay() -> Control:
	for i in range(overlay_root.get_child_count()-1,-1,-1):
		var c: Control=overlay_root.get_child(i)
		if not c.has_meta("closing") and not c.is_queued_for_deletion():return c
	return null

func close_all_overlays() -> void:
	for c in overlay_root.get_children():c.queue_free()

func has_overlay() -> bool:
	return top_overlay()!=null

func confirm(title: String,body: String,ok_text: String,on_ok: Callable,danger: bool=false) -> void:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,32)
	p.custom_minimum_size=Vector2(640,0)
	var v:=Ui.vbox(18);p.add_child(v)
	v.add_child(Ui.title(title,28))
	v.add_child(Ui.wrap_label(body,19,Ui.TEXT,576))
	v.add_child(Ui.gap(4))
	var h:=Ui.hbox(12);h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var layer: Control
	h.add_child(Ui.text_button("やめる",func():close_overlay(layer),19))
	var ok:=Ui.button(ok_text,func():
		close_overlay(layer);on_ok.call(),20,true)
	if danger:Ui.danger_style(ok)
	h.add_child(ok)
	layer=overlay(p)

func notice(title: String,body: String,ok_text: String="わかった",on_ok: Callable=Callable()) -> void:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,32)
	p.custom_minimum_size=Vector2(640,0)
	var v:=Ui.vbox(18);p.add_child(v)
	v.add_child(Ui.title(title,28))
	v.add_child(Ui.wrap_label(body,19,Ui.TEXT,576))
	var h:=Ui.hbox(12);h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var layer: Control
	h.add_child(Ui.button(ok_text,func():
		close_overlay(layer)
		if on_ok.is_valid():on_ok.call(),22,true))
	layer=overlay(p)

func toast(text: String,color: Color=Ui.TEXT,seconds: float=3.0) -> void:
	var p:=PanelContainer.new()
	var st:=Ui.box(Color("1e1519",0.97),Color.TRANSPARENT,0,2,16,12)
	st.border_color=color;st.border_width_left=3
	p.add_theme_stylebox_override("panel",st)
	p.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var l:=Ui.wrap_label(text,17,Ui.TEXT if color==Ui.TEXT else color.lightened(0.25),400);l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count()>6:toast_box.get_child(0).free()
	p.modulate.a=0.0
	var tw:=p.create_tween()
	tw.tween_property(p,"modulate:a",1.0,0.15)
	tw.tween_interval(seconds)
	tw.tween_property(p,"modulate:a",0.0,0.3)
	tw.tween_callback(p.queue_free)
	sfx("toast")

# ───────── 効果音（素材が届くまで、短い音を作って鳴らす） ─────────
func setup_audio() -> void:
	sounds={"click":tone(880,0.05,0.25),"hover":tone(1320,0.02,0.07),"toast":tone(660,0.12,0.18,990),
		"confirm":tone(520,0.18,0.25,780),"cue":tone(300,0.25,0.3,220),"capture":tone(440,0.3,0.3,660),
		"alarm":tone(760,0.35,0.25,540),"coin":tone(1200,0.08,0.2,1600),"hit":noise(0.06,0.18),"error":tone(200,0.2,0.3,150)}
	for i in 8:
		var p:=AudioStreamPlayer.new();add_child(p);players.append(p)

func sfx(name: String) -> void:
	if not sounds.has(name) or OS.has_feature("headless"):return
	var vol: float=float(G.settings.get("sfx",0.8))*float(G.settings.get("master",0.8))
	if vol<=0.01:return
	for p in players:
		if not p.playing:
			p.stream=sounds[name];p.volume_db=linear_to_db(vol);p.play();return

func tone(freq: float,seconds: float,amp: float,freq_end: float=-1.0) -> AudioStreamWAV:
	var rate:=22050
	var n:=int(rate*seconds)
	var data:=PackedByteArray();data.resize(n*2)
	var phase:=0.0
	for i in n:
		var t:=float(i)/n
		var f:=freq if freq_end<0 else lerpf(freq,freq_end,t)
		phase+=TAU*f/rate
		var env:=minf(1.0,t*40.0)*pow(1.0-t,2.0)
		data.encode_s16(i*2,int(clampf(sin(phase)*amp*env,-1,1)*32767))
	var s:=AudioStreamWAV.new();s.format=AudioStreamWAV.FORMAT_16_BITS;s.mix_rate=rate;s.data=data
	return s

func noise(seconds: float,amp: float) -> AudioStreamWAV:
	var rate:=22050;var n:=int(rate*seconds)
	var data:=PackedByteArray();data.resize(n*2)
	var rng:=RandomNumberGenerator.new();rng.seed=7
	for i in n:
		var t:=float(i)/n
		data.encode_s16(i*2,int(rng.randf_range(-1,1)*amp*pow(1.0-t,3.0)*32767))
	var s:=AudioStreamWAV.new();s.format=AudioStreamWAV.FORMAT_16_BITS;s.mix_rate=rate;s.data=data
	return s

# ───────── 確認用の起動（コマンドラインから画面を開いて撮影する） ─────────
## --debug=screen:ranch|world|prep [--window=captives|monsters|eggs|book] / --debug=battle [--stage=<ID>] [--auto]
## --debug=hatch [--grade=0〜3] / --debug=milestone / --debug=flow / --debug=bench（重さの計測）/ --setup=early|mid|late / --shot=<png> --shot-at=<秒>
var debug: Dictionary={}
var shot_timer:=-1.0
var anim_ready_ms:=0   # 動作データを読み終えた時刻（起動からのミリ秒。計測用）
func parse_debug() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv: PackedStringArray=arg.substr(2).split("=",true,1);debug[kv[0]]=kv[1]
		elif arg.begins_with("--"):debug[arg.substr(2)]="1"

func after_loading() -> void:
	parse_debug()
	if not debug.has("debug"):goto("title");return
	if not G.anim.ready_ok:await G.anim.loaded
	anim_ready_ms=Time.get_ticks_msec()
	if debug.has("shot"):shot_timer=float(debug.get("shot-at","6"))
	var what: PackedStringArray=str(debug.debug).split(":",true,1)
	G.state=State.new();G.state.new_game(G.db,int(debug.get("seed","7")))
	Day.first_morning()
	G.state.flags.help_seen={"ranch":true,"world":true,"prep":true,"battle":true}
	if debug.has("setup"):load("res://game/tests/debug_setup.gd").apply(str(debug.setup))
	var Sites=load("res://game/world/sites.gd")
	match what[0]:
		"screen":
			var name: String=what[1] if what.size()>1 else "ranch"
			var params: Dictionary={}
			if name=="prep":params=debug_site(Sites)
			goto(name,params)
			if debug.has("window"):
				await get_tree().create_timer(1.2).timeout
				open_window(str(debug.window))
		"battle":
			var params2: Dictionary=debug_site(Sites)
			if G.state.party.is_empty():load("res://game/tests/auto_play.gd").pick_party()
			goto("battle",params2)
			if debug.has("auto"):
				await get_tree().create_timer(1.5).timeout
				auto_battle()
		"hatch":
			# 孵化の演出：召喚陣の卵を1つ作って孵す
			var st=G.state
			var Make=load("res://game/core/make.gd");var Eggs=load("res://game/breed/eggs.gd")
			var w: Dictionary=st.add_woman(Make.woman_from(Make.named_member("rina"),"確認"))
			w.stage=3
			var e: Dictionary=Eggs.lay(w,"altar",{})
			if debug.has("grade"):e.grade=int(debug.grade)
			e.hatch_day=st.day
			st.report=[]
			var m: Dictionary=Eggs.hatch(e)
			st.log_event("hatch","%sが孵った"%m.name,{"monster":int(m.uid)})
			goto("ranch",{"morning":true})
		"milestone":
			var st2=G.state
			var W2=load("res://game/core/make.gd")
			var w2: Dictionary=st2.add_woman(W2.woman_from(W2.named_member("rina"),"確認"))
			w2.stage=2
			st2.report=[];st2.flags.milestones=[{"woman":int(w2.uid),"stage":2,"ending":false}]
			goto("ranch",{"morning":true})
		"flow":run_flow()
		"bench":preload("res://game/core/bench.gd").run(self)

## 確認用の出撃先（--stage=<ストーリー戦の ID>。無ければ今日の最初の出撃先）。
func debug_site(Sites) -> Dictionary:
	var st=G.state
	if debug.has("stage"):
		var id: String=str(debug.stage)
		for r in G.db.regions:
			if id in r.story:
				var s: Dictionary=Sites.story_site(r,id)
				st.world.sites_today.append(s)
				return {"site":str(s.id),"k":int(debug.get("k","0"))}
	return {"site":str(st.world.sites_today[0].id),"k":0}

## 戦闘の画面を速さ×4で最後まで流す（確かめ用。スキルは自動なので押す操作はない）。
func auto_battle() -> void:
	if current!=null and current.get("sim")!=null:current.speed_i=current.SPEEDS.size()-1

func open_window(name: String) -> void:
	var W=preload("res://game/ui/parts/windows.gd")
	match name:
		"captives":W.captives(current)
		"monsters":W.monsters(current)
		"eggs":W.eggs(current)
		"book":W.book(current)

## 画面を順に自動で操作して通しで確かめる（牧場 → 窓 → 大陸 → 編成 → 戦闘 → 結果 → 牧場 → 一日を終える → 朝）。
func run_flow() -> void:
	var shot:=func(name: String):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://game/tests/flow_%s.png"%name)
		print("FLOW_SHOT ",name)
	goto("ranch",{})
	await get_tree().create_timer(2.0).timeout
	await shot.call("ranch")
	for wn in ["captives","monsters","eggs","book"]:
		open_window(wn)
		await get_tree().create_timer(0.8).timeout
		await shot.call("win_"+wn)
		close_all_overlays()
		await get_tree().create_timer(0.3).timeout
	current.set_mode("build")
	await get_tree().create_timer(0.5).timeout
	await shot.call("build")
	current.set_mode("view")
	current.sortie()
	await get_tree().create_timer(1.5).timeout
	await shot.call("world")
	current.go()
	await get_tree().create_timer(2.0).timeout
	await shot.call("prep")
	current.start()
	await get_tree().create_timer(1.5).timeout
	current.speed_i=2
	var shot_mid:=false
	while current_name=="battle" and not current.finished:
		if not shot_mid and current.sim.t>=6.0:shot_mid=true;await shot.call("battle")
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(4.5).timeout
	await shot.call("result")
	close_all_overlays()
	goto("ranch",{})
	await get_tree().create_timer(1.5).timeout
	Day.end_day(false)
	refresh()
	current.after_morning()
	preload("res://game/ui/parts/report.gd").morning(current,func():pass)
	await get_tree().create_timer(2.5).timeout
	await shot.call("morning")
	close_all_overlays()
	print("FLOW_DONE day=",G.state.day," chapter=",G.state.chapter," women=",G.state.women.size()," monsters=",G.state.monsters.size()," born=",G.state.records.born," wins=",G.state.records.wins)
	get_tree().quit()

func _process(delta: float) -> void:
	if shot_timer>0:
		shot_timer-=delta
		if shot_timer<=0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(debug.shot))
			print("SHOT ",debug.shot)
			get_tree().quit()

func _exit_tree() -> void:
	G.db=null;G.state=null;G.anim=null;G.main=null
	Ui.theme=null;Ui.body_font=null;Ui.head_font=null

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode==KEY_F11:
		var win:=get_window()
		win.mode=Window.MODE_WINDOWED if win.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
