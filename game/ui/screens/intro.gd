extends Control
## 始まりの語り。クリックかSpaceで進む。暗い地に明朝の語りと飾り線、背後で魔法陣がゆっくり回る。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
var lines: Array=[]
var index:=0
var label: Label
var hint: Label
var pips: HBoxContainer
var back: Back

func open(_p: Dictionary) -> void:
	lines=G.db.texts.get("intro",[])
	back=Back.new();Ui.full(back);back.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(back)
	var c:=CenterContainer.new();Ui.full(c);c.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(c)
	var v:=Ui.vbox(26);c.add_child(v)
	v.add_child(Ui.flourish(640))
	label=Ui.label("",34,Ui.TEXT,true);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size=Vector2(1400,120);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing",10)
	v.add_child(label)
	v.add_child(Ui.flourish(640))
	pips=Ui.hbox(8);pips.alignment=BoxContainer.ALIGNMENT_CENTER;v.add_child(pips)
	hint=Ui.label("クリックで進む",16,Ui.FAINT);hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(hint)
	var skip:=Ui.icon_button("arrow","飛ばす",finish,16);skip.position=Vector2(1740,1000);add_child(skip)
	show_line()

func show_line() -> void:
	if index>=lines.size():finish();return
	label.text=str(lines[index])
	label.modulate.a=0.0
	var tw:=create_tween();tw.tween_property(label,"modulate:a",1.0,0.6)
	for c in pips.get_children():c.queue_free()
	for i in lines.size():
		var d:=ColorRect.new();d.custom_minimum_size=Vector2(8,8);d.color=Ui.GOLD if i<=index else Color(1,1,1,0.12);pips.add_child(d)

func _process(delta: float) -> void:
	if back!=null:back.t+=delta;back.queue_redraw()
	if hint!=null:hint.modulate.a=0.5+0.5*sin(back.t*2.5)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index==MOUSE_BUTTON_LEFT or e is InputEventKey and e.pressed and e.keycode in [KEY_SPACE,KEY_ENTER]:
		index+=1;show_line()

func finish() -> void:
	set_process_unhandled_input(false)
	preload("res://game/core/day.gd").first_morning()
	G.main.goto("ranch",{})

class Back extends Control:
	var t:=0.0
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		U.draw_sigil(self,Vector2(size.x*0.5,size.y*0.5),480,Color(U.CRIMSON.lightened(0.2),0.16),t*0.5,1.0,false)
