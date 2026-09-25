extends Control
## 終わり（勇者パーティを捕らえた）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
var lines: Array=[]
var index:=0
var label: Label
var back: Back

func open(p: Dictionary) -> void:
	var victory:=true
	lines=G.db.texts.get("ending",[]).duplicate()
	lines.append("%d日で勇者を捕らえた。捕らえた女 %d人、孵った魔物 %d体、見た結末 %d。"%[G.state.day,int(G.state.records.captured),int(G.state.records.born),G.state.records.endings.size()])
	back=Back.new();back.color=Ui.GOLD if victory else Ui.DANGER;Ui.full(back);back.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(back)
	var c:=CenterContainer.new();Ui.full(c);c.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(c)
	var v:=Ui.vbox(26);c.add_child(v)
	var ic:=Ui.icon_disc("crown" if victory else "skull",84,Ui.GOLD if victory else Ui.DANGER);v.add_child(ic)
	var t:=Ui.title("父の仇を捕らえた" if victory else "敗北",64,Ui.GOLD_HI if victory else Ui.DANGER.lightened(0.2));t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(t)
	v.add_child(Ui.flourish(640))
	label=Ui.label("",30,Ui.TEXT,true);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.custom_minimum_size=Vector2(1400,120);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;v.add_child(label)
	var h:=Ui.hbox(14);h.alignment=BoxContainer.ALIGNMENT_CENTER;v.add_child(h)
	h.add_child(Ui.icon_button("arrow","次へ",advance,20))
	var tb:=Ui.icon_button("castle","タイトルへ",func():G.main.goto("title"),20);Ui.primary_style(tb);h.add_child(tb)
	show_line()

func advance() -> void:
	index=mini(index+1,lines.size()-1);show_line()

func show_line() -> void:
	if lines.is_empty():return
	label.text=str(lines[index]);label.modulate.a=0.0
	var tw:=create_tween();tw.tween_property(label,"modulate:a",1.0,0.6)

func _process(delta: float) -> void:
	if back!=null:back.t+=delta;back.queue_redraw()

class Back extends Control:
	var t:=0.0
	var color:=Color.WHITE
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		U.draw_sigil(self,Vector2(size.x*0.5,size.y*0.55),520,Color(color,0.16),t*0.4,1.0,false)
