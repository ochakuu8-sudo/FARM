extends RefCounted
## 設定の窓（音量・画面・戦闘・牧場の見え方）。変えたらすぐ保存する。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Save=preload("res://game/core/save.gd")
const Icons=preload("res://game/ui/icons.gd")

static func open_panel() -> void:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,32);p.custom_minimum_size=Vector2(760,0)
	var v:=Ui.vbox(14);p.add_child(v)
	var th:=Ui.hbox(14);v.add_child(th)
	th.add_child(Ui.icon_disc("gear",48,Ui.GOLD));th.add_child(Ui.title("設定",32))
	v.add_child(Ui.rule())
	var s: Dictionary=G.settings
	v.add_child(slider("全体の音量","master",0,1,0.05))
	v.add_child(slider("効果音","sfx",0,1,0.05))
	v.add_child(slider("文字とUIの大きさ","ui_scale",0.9,1.3,0.05,func(val):G.main.get_window().content_scale_factor=val))
	v.add_child(choice("戦闘の既定の速さ","battle_speed",[["×1",1],["×2",2],["×3",3]]))
	v.add_child(toggle("戦闘で見どころに寄る","follow"))
	v.add_child(toggle("牧場の場面を自動で回す","auto_rotate"))
	v.add_child(toggle("全画面（F11）","fullscreen",func(val):G.main.get_window().mode=Window.MODE_FULLSCREEN if val else Window.MODE_WINDOWED))
	var layer: Control
	var h:=Ui.hbox();h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var cb:=Ui.icon_button("close","閉じる",func():
		Save.save_settings(G.settings);G.main.close_overlay(layer),19)
	Ui.primary_style(cb);h.add_child(cb)
	layer=G.main.overlay(p,0.6)

static func row(text: String) -> HBoxContainer:
	var h:=Ui.hbox(16)
	var d:=Icons.rect("gem",12,Ui.GOLD);d.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(d)
	var l:=Ui.label(text,18,Ui.TEXT,true);l.custom_minimum_size.x=290;h.add_child(l)
	return h

static func slider(text: String,key: String,lo: float,hi: float,step: float,apply: Callable=Callable()) -> Control:
	var h:=row(text)
	var sl:=HSlider.new();sl.min_value=lo;sl.max_value=hi;sl.step=step;sl.value=float(G.settings.get(key,lo))
	sl.custom_minimum_size=Vector2(300,24);sl.focus_mode=Control.FOCUS_NONE
	var val:=Ui.label("%d%%"%int(sl.value*100),18,Ui.DIM)
	sl.value_changed.connect(func(x):
		G.settings[key]=x;val.text="%d%%"%int(x*100)
		if apply.is_valid():apply.call(x))
	h.add_child(sl);h.add_child(val)
	return h

static func toggle(text: String,key: String,apply: Callable=Callable()) -> Control:
	var h:=row(text)
	var c:=CheckButton.new();c.button_pressed=bool(G.settings.get(key,false));c.focus_mode=Control.FOCUS_NONE
	c.toggled.connect(func(x):
		G.settings[key]=x
		if apply.is_valid():apply.call(x))
	h.add_child(c)
	return h

static func choice(text: String,key: String,options: Array) -> Control:
	var h:=row(text)
	var o:=OptionButton.new();o.focus_mode=Control.FOCUS_NONE
	for i in options.size():
		o.add_item(options[i][0])
		if options[i][1]==G.settings.get(key):o.select(i)
	o.item_selected.connect(func(i):G.settings[key]=options[i][1])
	h.add_child(o)
	return h
