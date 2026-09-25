extends Control
## タイトル。右側の石の間で、捕らわれた女と魔物が魔法陣の上でゆっくり動いている。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Save=preload("res://game/core/save.gd")
const Settings=preload("res://game/ui/parts/settings_panel.gd")
var world: Node2D
var back: Backdrop
var actors: Array=[]
var time:=0.0

func open(_p: Dictionary) -> void:
	var layer:=CanvasLayer.new();layer.layer=-5;add_child(layer)
	back=Backdrop.new();back.z_index=-4000;layer.add_child(back)
	world=Node2D.new();world.position=Vector2(1330,860);world.scale=Vector2(3.1,3.1);layer.add_child(world)
	# 左の題と項目
	var v:=Ui.vbox(12);v.position=Vector2(140,200);v.custom_minimum_size=Vector2(600,0);add_child(v)
	var t:=Ui.title("魔王の娘の",40,Ui.GOLD);v.add_child(t)
	var t2:=Ui.title("魔物",84,Ui.GOLD_HI);t2.add_theme_constant_override("outline_size",12);v.add_child(t2)
	var t3:=Ui.title("牧場",84,Ui.GOLD_HI);t3.add_theme_constant_override("outline_size",12);v.add_child(t3)
	var fl:=Ui.flourish(460);fl.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;v.add_child(fl)
	var sub:=Ui.label("攻めて捕らえ、卵を産ませ、育てて、また攻める。",22,Ui.DIM,true);v.add_child(sub)
	v.add_child(Ui.gap(34))
	var has_save:=Save.any()
	if has_save:continue_button=menu_button("play","続きから",func():continue_game(),true);v.add_child(continue_button)
	new_button=menu_button("plus","新しく始める",func():
		if has_save:G.main.confirm("新しく始める","自動保存は新しいゲームで上書きされます。手動で保存した枠は残ります。","始める",new_game)
		else:new_game(),not has_save)
	v.add_child(new_button)
	if has_save:load_button=menu_button("scroll","読み込む",func():load_menu());v.add_child(load_button)
	v.add_child(menu_button("gear","設定",func():Settings.open_panel()))
	v.add_child(menu_button("door","終わる",func():get_tree().quit()))
	var ver:=Ui.label("試作版　Space：決定　F11：全画面",15,Ui.FAINT);ver.position=Vector2(140,1030);add_child(ver)
	Ui.rise_in(v,0.1,20.0)
	# 動作データは裏で読み込んでいる。読み終わるまで、始める・続きから・読み込むは待たせる。
	if G.anim.ready_ok:on_loaded()
	else:
		for b in [continue_button,new_button,load_button]:
			if b!=null:b.disabled=true
		loading_label=Ui.label("",19,Ui.DIM);loading_label.position=Vector2(140,166);add_child(loading_label)
		G.anim.loaded.connect(on_loaded)

var continue_button: Button
var new_button: Button
var load_button: Button
var loading_label: Label

func on_loaded() -> void:
	if loading_label!=null and not G.anim.ready_ok:
		loading_label.text="動作データを読めません："+G.anim.error+"　管理ツールで焼き込みをしてください。"
		loading_label.add_theme_color_override("font_color",Ui.DANGER);return
	G.anim.attach(world)
	G.anim.set_pitch(PI/12)
	var cast: Array=[["0","kneel",Vector2(-40,0),6,1.0,Color.WHITE],["1","idle",Vector2(40,-6),6,1.0,Color.WHITE],["1","idle",Vector2(-120,-14),2,1.5,Color("c09070")],["0","caged",Vector2(120,-24),5,1.0,Color.WHITE]]
	for c in cast:
		var id: String=G.anim.acquire(c[0])
		G.anim.height(id,c[4]);G.anim.tint(id,c[5])
		G.anim.place(id,c[2],c[3],c[1])
		actors.append(id)
	# 役者を一度描いて、描画のシェーダーを作らせてからボタンを押せるようにする。
	# ブラウザ版ではシェーダーの準備に数秒かかり、その間は画面が止まる（押した直後に止まらないように先に済ませる）。
	world.modulate.a=0.02
	if loading_label!=null:loading_label.text="描画の準備をしています"
	for i in 3:await get_tree().process_frame
	if not is_inside_tree():return
	if loading_label!=null:
		var tw:=loading_label.create_tween();tw.tween_property(loading_label,"modulate:a",0.0,0.4)
	for b in [continue_button,new_button,load_button]:
		if b!=null:b.disabled=false
	var tw2:=world.create_tween();tw2.tween_property(world,"modulate:a",1.0,0.8)
	G.main.warm_up()

func menu_button(icon: String,text: String,cb: Callable,primary: bool=false) -> Button:
	var b:=Ui.icon_button(icon,text,cb,24)
	if primary:Ui.primary_style(b)
	b.custom_minimum_size=Vector2(420,62)
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	return b

func new_game() -> void:
	G.state=preload("res://game/core/state.gd").new()
	G.state.new_game(G.db)
	G.main.goto("intro")

func continue_game() -> void:
	var slot:=Save.latest()
	if slot>=0 and Save.load_slot(slot):G.main.goto("ranch",{})
	else:G.main.toast("読み込めませんでした",Ui.DANGER)

func load_menu() -> void:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,30);p.custom_minimum_size=Vector2(720,0)
	var v:=Ui.vbox(10);p.add_child(v)
	var hh:=Ui.hbox(12);v.add_child(hh)
	hh.add_child(Ui.icon_disc("scroll",40,Ui.GOLD));hh.add_child(Ui.title("読み込む",30))
	v.add_child(Ui.rule())
	var layer: Control
	for s in [Save.AUTO,1,2,3]:
		var info: Dictionary=Save.info(s)
		var name: String="自動保存" if s==Save.AUTO else "枠 %d"%s
		var ok: bool=not info.is_empty() and int(info.get("version",0))>=5
		var text: String=name+"　　"+("空き" if info.is_empty() else ("%d日目　%s　女%d人・魔物%d体　%s"%[info.day,G.db.region(int(info.chapter)).name,int(info.get("women",0)),int(info.get("monsters",0)),info.saved_at]) if ok else "古い版（読めません）")
		var b:=Ui.button(text,func():
			G.main.close_overlay(layer)
			if Save.load_slot(s):G.main.goto("ranch",{}),17)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		b.icon=preload("res://game/ui/icons.gd").tex("hourglass" if s==Save.AUTO else "scroll",20)
		b.disabled=not ok
		v.add_child(b)
	v.add_child(Ui.gap(4))
	var bh:=Ui.hbox();bh.alignment=BoxContainer.ALIGNMENT_END;v.add_child(bh)
	bh.add_child(Ui.icon_button("back","戻る",func():G.main.close_overlay(layer),17))
	layer=G.main.overlay(p,0.6,true)

func _process(delta: float) -> void:
	time+=delta
	G.anim.advance(delta)
	if back!=null:back.t=time;back.queue_redraw()
	if loading_label!=null and not G.anim.ready_ok and G.anim.loading:
		loading_label.text="動作データを読み込んでいます"+".".repeat(int(time*3)%4)
	if world!=null:world.position.y=860+sin(time*0.4)*4

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode==KEY_SPACE and not G.main.has_overlay() and G.anim.ready_ok:
		if Save.any():continue_game()
		else:new_game()

func close() -> void:
	G.anim.detach()

## 石の間：石積みの壁、左右の柱と深紅の垂れ幕、床の魔法陣、松明、左は文字のために暗く。
class Backdrop extends Node2D:
	var t:=0.0
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var W:=1920.0;var H:=1080.0
		draw_rect(Rect2(0,0,W,H),Color("0c0809"))
		# 奥の石積み
		for row in 16:
			var y: float=row*56.0
			var off: float=0.0 if row%2==0 else 60.0
			for col in 18:
				var x: float=800+col*120.0-off
				var hsh: int=(row*73856093)^(col*19349663)
				var v: float=float(hsh%9)/9.0
				draw_rect(Rect2(x+2,y+2,116,52),Color("1a1214").lerp(Color("241a1b"),v))
		# 灯り（床の魔法陣の上に深紅の光）
		for i in 16:
			draw_circle(Vector2(1330,720),640-i*36,Color(0.55,0.08,0.12,0.02))
		# 柱と垂れ幕
		for px in [880.0,1780.0]:
			draw_rect(Rect2(px-40,0,80,H),Color("140e0f"))
			draw_rect(Rect2(px-40,0,6,H),Color(U.GOLD,0.18))
			draw_rect(Rect2(px+34,0,6,H),Color(0,0,0,0.5))
		for bx in [960.0,1640.0]:
			var pts:=PackedVector2Array([Vector2(bx,0),Vector2(bx+80,0),Vector2(bx+80,520),Vector2(bx+40,580),Vector2(bx,520)])
			draw_colored_polygon(pts,Color("4a0f18"))
			draw_polyline(PackedVector2Array([Vector2(bx,0),Vector2(bx,520),Vector2(bx+40,580),Vector2(bx+80,520),Vector2(bx+80,0)]),Color(U.GOLD,0.55),2)
			U.draw_sigil(self,Vector2(bx+40,300),22,U.GOLD,t,1.0,false)
		# 床
		draw_rect(Rect2(800,860,1120,220),Color("0a0607"))
		for i in 12:
			draw_line(Vector2(820+i*96,860),Vector2(760+i*110,1080),Color(0.35,0.22,0.2,0.2),2.0)
		draw_line(Vector2(800,860),Vector2(1920,860),Color(U.GOLD,0.3),2.0)
		U.draw_sigil(self,Vector2(1330,868),380,U.CRIMSON.lightened(0.25),t,0.22)
		# 松明
		for px in [880.0,1780.0]:
			var fl: float=0.9+0.1*sin(t*9.0+px)+0.06*sin(t*21.0+px)
			var top:=Vector2(px,420)
			for i in 6:draw_circle(top,140*fl-i*20,Color(1.0,0.5,0.15,0.025))
			draw_rect(Rect2(px-6,top.y,12,34),Color("3a2618"))
			draw_colored_polygon(PackedVector2Array([top+Vector2(-12,2),top+Vector2(12,2),top+Vector2(0,-40*fl)]),Color(1.0,0.66,0.25,0.95))
			draw_colored_polygon(PackedVector2Array([top+Vector2(-6,1),top+Vector2(6,1),top+Vector2(0,-20*fl)]),Color(1.0,0.95,0.7,0.95))
		# 左側を暗くして文字を読みやすくする
		for i in 32:
			draw_rect(Rect2(i*30,0,30,H),Color(0.02,0.01,0.015,clampf(0.95-i*0.03,0,0.95)))
