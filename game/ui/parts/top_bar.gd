extends PanelContainer
## 上端の帯：日付・章（地方）・資源・スタミナ・牢・メニュー。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Save=preload("res://game/core/save.gd")
const Settings=preload("res://game/ui/parts/settings_panel.gd")
var row: HBoxContainer
var help_topic:=""

func _ready() -> void:
	var st:=Ui.box(Color("120c0e",0.95),Color.TRANSPARENT,0,0,22)
	st.border_color=Ui.GOLD.darkened(0.35);st.border_width_bottom=2
	st.content_margin_top=0;st.content_margin_bottom=0
	st.shadow_size=12;st.shadow_color=Color(0,0,0,0.35);st.shadow_offset=Vector2(0,4)
	add_theme_stylebox_override("panel",st)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);offset_bottom=62
	row=Ui.hbox(20);add_child(row)
	G.main.changed.connect(refresh)
	refresh()

func counter(icon: String,color: Color,value: String,warn: bool=false,px: int=28) -> HBoxContainer:
	var h:=Ui.hbox(8)
	h.add_child(Ui.icon_disc(icon,px,color))
	var n:=Ui.num(value,21,Ui.DANGER if warn else Ui.TEXT);Ui.outline(n,4);n.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	h.mouse_filter=Control.MOUSE_FILTER_STOP
	return h

func refresh() -> void:
	if not is_inside_tree():return
	for c in row.get_children():c.queue_free()
	var st=G.state
	var day:=Ui.title("%d日目"%st.day,26);day.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(day)
	var reg: Dictionary=G.db.region(st.chapter)
	var cl:=Ui.label("%s　%s"%["序章" if st.chapter==0 else "第%d章"%st.chapter,str(reg.name)],15,Ui.DIM);cl.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(cl)
	row.add_child(Ui.gap(4))
	for k in ["money","essence"]:
		var h:=counter(str(Ui.RES[k].icon),Ui.RES[k].color,Ui.fmt(float(st.res.get(k,0))))
		h.tooltip_text=tip(k)
		row.add_child(h)
	var sh:=Ui.hbox(8)
	sh.add_child(Ui.icon_disc("bolt",26,Ui.INFO))
	var sm=Ui.meter(float(st.stamina.now),float(st.stamina.max),Ui.INFO,120,12);sm.size_flags_vertical=Control.SIZE_SHRINK_CENTER;sh.add_child(sm)
	var sn:=Ui.num("%d/%d"%[int(st.stamina.now),int(st.stamina.max)],19,Ui.TEXT);Ui.outline(sn,4);sn.size_flags_vertical=Control.SIZE_SHRINK_CENTER;sh.add_child(sn)
	sh.tooltip_text="スタミナ：出撃先ごとに使う量が違う。負けても戻らない。夜が明けると戻る。"
	sh.mouse_filter=Control.MOUSE_FILTER_STOP
	row.add_child(sh)
	var cells: int=st.cell_count()
	var ch2:=counter("cage",Ui.PINK,"%d/%d"%[cells,int(st.caps.cell)],cells>int(st.caps.cell),26)
	ch2.tooltip_text="牢の女／牢の定員。あふれていると出撃できない。"
	row.add_child(ch2)
	var eggs:=counter("egg",Ui.PINK,str(st.eggs.size()),false,26)
	eggs.tooltip_text="孵るのを待つ卵"
	row.add_child(eggs)
	row.add_child(Ui.spacer())
	if help_topic!="":
		var hb:=Ui.button("？",func():preload("res://game/ui/parts/help.gd").show_topic(help_topic,true),18);hb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(hb)
	var mb:=Ui.button("メニュー",open_menu,17);mb.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(mb)

func tip(k: String) -> String:
	match k:
		"money":return "お金（攻略で稼ぐ）：戦闘の報酬と、捕らえた女の持ち物。\n施設を建てる・枠を増やす・魔物をすぐ回復させるのに使う。"
		"essence":return "精気（経営で増やす）：搾り場と、房で心の段階を越えたとき。\n召喚陣の卵と、魔物の育成を早めるのに使う。"
	return k

func open_menu() -> void:
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,28);p.custom_minimum_size=Vector2(460,0)
	var v:=Ui.vbox(10);p.add_child(v)
	v.add_child(Ui.title("メニュー",28))
	v.add_child(Ui.gap(4))
	var layer: Control
	var can_save: bool=G.state.phase=="day" and G.main.current_name=="ranch"
	for s in [1,2,3]:
		var info: Dictionary=Save.info(s)
		var text: String="枠 %d に保存　%s"%[s,"（空き）" if info.is_empty() else "（%d日目を上書き）"%info.day]
		var b:=Ui.button(text,func():
			if Save.save(s):G.main.toast("枠 %d に保存した"%s,Ui.GOOD)
			G.main.close_overlay(layer),20)
		b.disabled=not can_save
		if not can_save:b.tooltip_text="保存できるのは牧場にいるときだけ"
		v.add_child(b)
	v.add_child(Ui.button("設定",func():G.main.close_overlay(layer);Settings.open_panel(),20))
	v.add_child(Ui.button("タイトルへ戻る",func():
		G.main.close_overlay(layer)
		G.main.confirm("タイトルへ","保存していない進み具合は、今朝の自動保存まで戻ります。","戻る",func():G.main.goto("title")),20))
	v.add_child(Ui.gap(4))
	v.add_child(Ui.text_button("閉じる",func():G.main.close_overlay(layer),18))
	layer=G.main.overlay(p,0.55,true)
