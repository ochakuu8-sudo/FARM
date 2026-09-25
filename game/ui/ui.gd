extends RefCounted
## UIの共通部品。色・字体・テーマ・よく使う部品をここから作る（設計書 4.0）。
## 見た目の方針（2026-09-24〜）：魔王城のダークファンタジー。飾りの量はゲームらしく多め（記号・立ち姿・札・宝石）、
## ただし色は革と鉄と古い金、差し色は深紅。見出しは明朝に縁取り、面は角飾りのある枠（Ornate）。記号は金属の円盤に色の線で載せる。
const Icons=preload("res://game/ui/icons.gd")

# ───────── 色（全画面で意味を固定する） ─────────
const BG:=Color("0e0a0c")
const PANEL:=Color("1a1216")       # 面
const PANEL_2:=Color("231a1e")     # 行・一段上の面
const PANEL_3:=Color("33242a")     # 選んでいるもの
const LINE:=Color("4d3a30")        # 枠（くすんだ青銅）
const LINE_SOFT:=Color("2c2024")   # 面の中の区切り
const GOLD:=Color("c9a45c")        # 古い金（枠・大事な数）
const GOLD_HI:=Color("ecd39a")
const CRIMSON:=Color("8c1f30")     # 深紅（決める・進む）
const INK:=Color("1a0e08")
const TEXT:=Color("eee2cc")        # 骨の白
const DIM:=Color("a8988a")
const FAINT:=Color("6a5a52")
const DANGER:=Color("d0463e")
const GOOD:=Color("84ad6c")
const INFO:=Color("7299bf")
const PURPLE:=Color("9c6cc4")
const PINK:=Color("c4628c")
const OUTLINE:=Color("0a0506")     # 見出しの縁取り

const RES:={
	"money":{"name":"お金","glyph":"金","icon":"coin","color":Color("d8b050")},
	"essence":{"name":"精気","glyph":"精","icon":"drop","color":Color("c4628c")},
}
const CAPTURE:={
	"force":{"name":"組み伏せ","glyph":"組","color":Color("c05a40")},
	"bind":{"name":"縛り","glyph":"縛","color":Color("9068b8")},
	"charm":{"name":"催眠","glyph":"催","color":Color("c4628c")},
	"poison":{"name":"毒","glyph":"毒","color":Color("7ea452")},
	"harm":{"name":"傷つける","glyph":"傷","color":Color("a04848")},
}
## 4つの能力（企画書 8.1）。房の名前も同じ色で見せる。
const STATS:=["str","mag","spd","end"]
const STAT:={
	"str":{"name":"力","glyph":"力","color":Color("c8503e"),"house":"力の房"},
	"mag":{"name":"魔","glyph":"魔","color":Color("9a68c6"),"house":"魔の房"},
	"spd":{"name":"速","glyph":"速","color":Color("4ea39c"),"house":"速の房"},
	"end":{"name":"耐","glyph":"耐","color":Color("5f8cb8"),"house":"耐の房"},
}
## 罠の分類
const TRAP_CAT:={
	"slow":{"name":"足止め","color":Color("6aa6a0"),"icon":"drop"},
	"catch":{"name":"捕獲","color":Color("c4628c"),"icon":"chain"},
	"split":{"name":"分断","color":Color("cc9440"),"icon":"door"},
	"carry":{"name":"運搬","color":Color("8a7a6a"),"icon":"hand"},
}
## 格：鉄・青銅の緑青・鋼・金。
const GRADE:=[{"name":"並","color":Color("938a84")},{"name":"良","color":Color("84ad6c")},{"name":"稀","color":Color("76a2cc")},{"name":"伝説","color":Color("e2b24c")}]
const RANK_COLOR:={"S":Color("e8c060"),"A":Color("cc7c3c"),"B":Color("84ad6c"),"C":Color("7299bf"),"D":Color("766870")}
const STAGES:=["反抗","動揺","従順","堕落","心酔"]
const STAGE_COLORS:=[Color("c8503e"),Color("cc9440"),Color("c8b458"),Color("c4628c"),Color("9a68c6")]
const ROOM_KIND:={
	"hold":{"name":"収容","glyph":"収","color":Color("9a8470")},
	"train":{"name":"調教","glyph":"調","color":Color("b84874")},
	"breed":{"name":"繁殖","glyph":"繁","color":Color("c4628c")},
	"work":{"name":"働き","glyph":"働","color":Color("b08a58")},
	"rest":{"name":"休養","glyph":"休","color":Color("5e9eb0")},
	"military":{"name":"軍事","glyph":"軍","color":Color("c8503e")},
}
const SQUAD_COLORS:=[Color("9c6cc4"),Color("4ea39c"),Color("cc9440"),Color("c4586c")]

static var body_font: Font
static var bold_font: Font
static var head_font: Font
static var caps_font: Font
static var num_font: Font
static var theme: Theme

static func fonts() -> void:
	if body_font!=null:return
	# ブラウザ版は OS のフォントを使えないので、同梱の Noto（ゲームで使う文字だけの部分集合。game_v2/tools/web_fonts.py）を使う。
	if OS.has_feature("web") or "--bundled-fonts" in OS.get_cmdline_user_args():
		bundled_fonts();return
	var gothic:=PackedStringArray(["Yu Gothic UI","Meiryo UI","Meiryo","Noto Sans JP","MS UI Gothic"])
	var body:=SystemFont.new()
	body.font_names=gothic
	body.font_weight=500
	body.antialiasing=TextServer.FONT_ANTIALIASING_GRAY
	body.hinting=TextServer.HINTING_LIGHT
	body_font=body
	var bold:=SystemFont.new()
	bold.font_names=gothic
	bold.font_weight=700
	bold.antialiasing=TextServer.FONT_ANTIALIASING_GRAY
	bold_font=bold
	var mincho:=SystemFont.new()
	mincho.font_names=PackedStringArray(["Yu Mincho","YuMincho","HGS明朝E","Noto Serif JP","MS PMincho"])
	mincho.font_weight=700
	mincho.antialiasing=TextServer.FONT_ANTIALIASING_GRAY
	var head:=FontVariation.new();head.base_font=mincho;head.spacing_glyph=1
	head_font=head
	var caps:=FontVariation.new();caps.base_font=mincho;caps.spacing_glyph=2
	caps_font=caps
	var num:=FontVariation.new();num.base_font=bold
	num.opentype_features={"tnum":1}
	num_font=num

static func bundled_fonts() -> void:
	var sans: FontFile=load("res://game/ui/fonts/NotoSansJP-sub.ttf")
	var serif: FontFile=load("res://game/ui/fonts/NotoSerifJP-sub.ttf")
	for f in [sans,serif]:
		f.antialiasing=TextServer.FONT_ANTIALIASING_GRAY;f.hinting=TextServer.HINTING_LIGHT
	var weight:=func(base: Font,w: int,spacing: int=0) -> FontVariation:
		var v:=FontVariation.new();v.base_font=base;v.variation_opentype={TextServerManager.get_primary_interface().name_to_tag("wght"):w};v.spacing_glyph=spacing
		return v
	body_font=weight.call(sans,500)
	bold_font=weight.call(sans,700)
	head_font=weight.call(serif,700,1)
	caps_font=weight.call(serif,700,2)
	var num: FontVariation=weight.call(sans,700);num.opentype_features={"tnum":1}
	num_font=num

## 平らな面（小物・行の地）。
static func box(color: Color,border: Color=Color.TRANSPARENT,width: int=0,radius: int=3,pad: int=10,shadow: int=0) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new()
	s.bg_color=color;s.border_color=border
	s.set_border_width_all(width);s.set_corner_radius_all(radius)
	s.content_margin_left=pad;s.content_margin_right=pad;s.content_margin_top=pad*0.7;s.content_margin_bottom=pad*0.7
	s.anti_aliasing=true
	if shadow>0:
		s.shadow_size=shadow;s.shadow_color=Color(0,0,0,0.55);s.shadow_offset=Vector2(0,shadow*0.4)
	return s

## 角飾りのある枠（大きな面・窓・区切りの箱）。
static func ornate(bg: Color=PANEL,frame: Color=GOLD,pad: int=16,corner: int=14) -> StyleBox:
	var s:=Ornate.new()
	s.bg=bg;s.frame=frame;s.corner=corner
	s.content_margin_left=pad;s.content_margin_right=pad;s.content_margin_top=pad;s.content_margin_bottom=pad
	return s

## 押せる板：暗い地に細い金の縁、下に厚み。押すと沈む。
static func bevel(fill: Color,pressed: bool=false,pad: int=16,edge: Color=Color.TRANSPARENT) -> StyleBoxFlat:
	var e: Color=edge if edge.a>0 else fill.lightened(0.35).lerp(GOLD,0.45)
	var s:=box(fill,e,1,3,pad)
	s.border_width_bottom=1 if pressed else 3
	s.border_color=e
	s.content_margin_top=pad*0.5+(2 if pressed else 0);s.content_margin_bottom=pad*0.5
	s.shadow_size=4;s.shadow_color=Color(0,0,0,0.45);s.shadow_offset=Vector2(0,2)
	return s

static func ghost(alpha: float,border: Color,pad: int=14,width: int=1) -> StyleBoxFlat:
	return box(Color(1,1,1,alpha),border,width,3,pad)

static func build_theme() -> Theme:
	if theme!=null:return theme
	fonts()
	var t:=Theme.new()
	t.default_font=body_font
	t.default_font_size=19
	t.set_color("font_color","Label",TEXT)
	for kind in ["Button","MenuButton","OptionButton","CheckBox","CheckButton"]:
		t.set_color("font_color",kind,TEXT)
		t.set_color("font_hover_color",kind,GOLD_HI)
		t.set_color("font_pressed_color",kind,GOLD_HI)
		t.set_color("font_hover_pressed_color",kind,GOLD_HI)
		t.set_color("font_disabled_color",kind,FAINT)
		t.set_color("font_focus_color",kind,TEXT)
		t.set_color("icon_normal_color",kind,GOLD)
		t.set_color("icon_hover_color",kind,GOLD_HI)
		t.set_color("icon_pressed_color",kind,GOLD_HI)
	t.set_font("font","Button",bold_font)
	t.set_font("font","OptionButton",bold_font)
	t.set_stylebox("normal","Button",bevel(Color("2b1d22")))
	t.set_stylebox("hover","Button",bevel(Color("3a262c"),false,16,GOLD))
	t.set_stylebox("pressed","Button",bevel(Color("2b1d22"),true,16,GOLD_HI))
	t.set_stylebox("disabled","Button",bevel(Color("1a1215"),false,16,Color("33262a")))
	t.set_stylebox("focus","Button",StyleBoxEmpty.new())
	t.set_stylebox("panel","PanelContainer",ornate())
	t.set_stylebox("panel","Panel",ornate())
	t.set_stylebox("panel","TooltipPanel",box(Color("1e1519",0.98),GOLD.darkened(0.3),1,3,12,10))
	t.set_color("font_color","TooltipLabel",TEXT)
	t.set_font_size("font_size","TooltipLabel",16)
	t.set_stylebox("normal","LineEdit",box(Color("0f0a0c"),LINE,1,3,12))
	t.set_stylebox("focus","LineEdit",box(Color("0f0a0c"),GOLD,1,3,12))
	t.set_color("caret_color","LineEdit",GOLD_HI)
	t.set_stylebox("background","ProgressBar",box(Color("0f0a0c"),LINE_SOFT,1,2,0))
	t.set_stylebox("fill","ProgressBar",box(GOLD,Color.TRANSPARENT,0,2,0))
	t.set_stylebox("normal","OptionButton",bevel(Color("241a1e"),false,14))
	t.set_stylebox("hover","OptionButton",bevel(Color("33242a"),false,14,GOLD))
	t.set_stylebox("pressed","OptionButton",bevel(Color("241a1e"),true,14,GOLD_HI))
	t.set_stylebox("focus","OptionButton",StyleBoxEmpty.new())
	t.set_stylebox("panel","PopupMenu",box(Color("1e1519"),GOLD.darkened(0.3),1,3,8,14))
	t.set_color("font_color","PopupMenu",TEXT)
	t.set_color("font_hover_color","PopupMenu",GOLD_HI)
	t.set_stylebox("hover","PopupMenu",box(Color("3a242a"),Color.TRANSPARENT,0,2,6))
	t.set_constant("v_separation","PopupMenu",8)
	t.set_font("font","PopupMenu",bold_font)
	t.set_stylebox("tab_selected","TabContainer",box(PANEL_3,GOLD,1,3,12))
	t.set_stylebox("tab_unselected","TabContainer",box(PANEL,LINE,1,3,12))
	t.set_stylebox("panel","TabContainer",ornate())
	for sb in ["VScrollBar","HScrollBar"]:
		t.set_stylebox("grabber",sb,box(Color("4d3a30"),Color.TRANSPARENT,0,2,0))
		t.set_stylebox("grabber_highlight",sb,box(GOLD.darkened(0.2),Color.TRANSPARENT,0,2,0))
		t.set_stylebox("grabber_pressed",sb,box(GOLD,Color.TRANSPARENT,0,2,0))
		var track:=box(Color(0,0,0,0.35),Color.TRANSPARENT,0,2,0)
		track.content_margin_left=4;track.content_margin_right=4;track.content_margin_top=4;track.content_margin_bottom=4
		t.set_stylebox("scroll",sb,track)
	# スライダー：暗い溝に深紅の塗り
	var track:=box(Color("0f0a0c"),LINE,1,2,0);track.content_margin_top=4;track.content_margin_bottom=4
	t.set_stylebox("slider","HSlider",track)
	t.set_stylebox("grabber_area","HSlider",box(CRIMSON.lightened(0.1),Color.TRANSPARENT,0,2,0))
	t.set_stylebox("grabber_area_highlight","HSlider",box(CRIMSON.lightened(0.25),Color.TRANSPARENT,0,2,0))
	t.set_constant("separation","HBoxContainer",10)
	t.set_constant("separation","VBoxContainer",8)
	theme=t
	return t

# ───────── 字 ─────────
static func label(text: String,size: int=20,color: Color=TEXT,head: bool=false) -> Label:
	fonts()
	var l:=Label.new()
	l.text=text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	if head:
		l.add_theme_font_override("font",head_font)
		outline(l,maxi(4,size/6))
	return l

## 濃い縁取り（見出し・名前・大事な数）。
static func outline(l: Label,px: int=5) -> Label:
	l.add_theme_constant_override("outline_size",px)
	l.add_theme_color_override("font_outline_color",OUTLINE)
	return l

## 大きな見出し：明朝に縁取りと、下へ落ちる影。
static func title(text: String,size: int=34,color: Color=GOLD_HI) -> Label:
	var l:=label(text,size,color,true)
	outline(l,7)
	l.add_theme_color_override("font_shadow_color",Color(0,0,0,0.6))
	l.add_theme_constant_override("shadow_offset_y",3);l.add_theme_constant_override("shadow_offset_x",0)
	return l

static func wrap_label(text: String,size: int=18,color: Color=TEXT,width: float=0) -> Label:
	var l:=label(text,size,color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if width>0:l.custom_minimum_size.x=width
	return l

static func rich(text: String,size: int=18) -> RichTextLabel:
	var r:=RichTextLabel.new()
	r.bbcode_enabled=true;r.fit_content=true;r.scroll_active=false
	r.add_theme_font_size_override("normal_font_size",size)
	r.add_theme_font_size_override("bold_font_size",size)
	r.add_theme_color_override("default_color",TEXT)
	r.text=text
	return r

static func num(text: String,size: int=18,color: Color=TEXT) -> Label:
	fonts()
	var l:=label(text,size,color);l.add_theme_font_override("font",num_font)
	return l

## 小見出し（明朝、字間を少し空ける）。
static func eyebrow(text: String,color: Color=DIM,size: int=13) -> Label:
	fonts()
	var l:=label(text,size,color)
	l.add_theme_font_override("font",caps_font)
	return l

# ───────── ボタン ─────────
static func button(text: String,callback: Callable=Callable(),size: int=20,primary: bool=false) -> Button:
	var b:=Button.new()
	b.text=text
	b.add_theme_font_size_override("font_size",size)
	b.focus_mode=Control.FOCUS_NONE
	if primary:primary_style(b)
	if callback.is_valid():b.pressed.connect(callback)
	b.pressed.connect(func():press_feedback(b))
	b.mouse_entered.connect(func():
		var main=preload("res://game/core/g.gd").main
		if main!=null and main.has_method("sfx"):main.sfx("hover"))
	return b

## 記号つきのボタン。color を渡すとその色の板になる。
static func icon_button(icon: String,text: String,callback: Callable=Callable(),size: int=18,color: Color=Color.TRANSPARENT) -> Button:
	var b:=button(text,callback,size)
	b.icon=Icons.tex(icon,size+4)
	b.add_theme_constant_override("h_separation",8)
	b.add_theme_constant_override("icon_max_width",size+4)
	if color.a>0.0:color_style(b,color)
	return b

## 色の板のボタン（深紅・青など。縁は金）。
static func color_style(b: Button,fill: Color) -> void:
	b.add_theme_stylebox_override("normal",bevel(fill,false,16,GOLD.darkened(0.15)))
	b.add_theme_stylebox_override("hover",bevel(fill.lightened(0.12),false,16,GOLD_HI))
	b.add_theme_stylebox_override("pressed",bevel(fill,true,16,GOLD_HI))
	b.add_theme_stylebox_override("disabled",bevel(Color("1a1215"),false,16,Color("33262a")))
	for k in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color"]:
		b.add_theme_color_override(k,GOLD_HI if k!="font_color" else TEXT)
	for k in ["icon_normal_color","icon_hover_color","icon_pressed_color"]:b.add_theme_color_override(k,GOLD_HI)

## 主ボタン：深紅の板に金の縁と金の字。1画面に1つ（決める・進む）。
static func primary_style(b: Button,fill: Color=CRIMSON) -> void:
	fonts()
	color_style(b,fill)
	for k in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		b.add_theme_color_override(k,GOLD_HI)
	b.add_theme_color_override("font_disabled_color",FAINT)
	b.add_theme_font_override("font",head_font)
	b.add_theme_constant_override("outline_size",4);b.add_theme_color_override("font_outline_color",OUTLINE)

## 取り消せない操作の主ボタン（赤）。
static func danger_style(b: Button) -> void:
	primary_style(b,Color("a02a28"))

## ボタンの左右の余白を詰める（狭い所に並べるとき）。
static func compact(b: Button,pad: int=8) -> Button:
	for k in ["normal","hover","pressed","disabled"]:
		var sb: StyleBox=b.get_theme_stylebox(k)
		if sb==null:continue
		var d: StyleBox=sb.duplicate()
		d.content_margin_left=pad;d.content_margin_right=pad
		b.add_theme_stylebox_override(k,d)
	return b

## 板のない文字だけのボタン（戻る・閉じるなど）。
static func text_button(text: String,callback: Callable=Callable(),size: int=17) -> Button:
	var b:=button(text,callback,size)
	var e:=StyleBoxEmpty.new();e.content_margin_left=8;e.content_margin_right=8;e.content_margin_top=4;e.content_margin_bottom=4
	for k in ["normal","hover","pressed","disabled"]:b.add_theme_stylebox_override(k,e)
	b.add_theme_color_override("font_color",DIM)
	return b

static func press_feedback(b: Control) -> void:
	var main=preload("res://game/core/g.gd").main
	if main!=null and main.has_method("sfx"):main.sfx("click")
	if not b.is_inside_tree():return
	b.pivot_offset=b.size*0.5
	var tw:=b.create_tween()
	tw.tween_property(b,"scale",Vector2(0.96,0.96),0.05)
	tw.tween_property(b,"scale",Vector2.ONE,0.1)

# ───────── 面 ─────────
## 面（角飾りの枠）。border に色を渡すと、枠の金の代わりにその色。
static func panel(color: Color=Color(PANEL,0.96),border: Color=LINE,pad: int=14) -> PanelContainer:
	var p:=PanelContainer.new()
	p.add_theme_stylebox_override("panel",ornate(color,GOLD if border==LINE else border,pad))
	return p

## 見出しの帯：金属の円盤に記号、明朝の題、右に添え字。下に金の細線。
static func header(icon: String,text: String,color: Color=GOLD,right: String="") -> VBoxContainer:
	var v:=vbox(6)
	var h:=hbox(10);v.add_child(h)
	h.add_child(icon_disc(icon,30,color))
	var l:=label(text,20,GOLD_HI,true);l.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(l)
	h.add_child(spacer())
	if right!="":
		var r:=label(right,15,DIM);r.size_flags_vertical=Control.SIZE_SHRINK_CENTER;h.add_child(r)
	v.add_child(rule())
	return v

## 金の細線（中央に菱形の飾り）。
static func rule() -> Control:
	var r:=Rule.new();r.custom_minimum_size=Vector2(0,7);r.size_flags_horizontal=Control.SIZE_EXPAND_FILL;r.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return r

static func section(text: String,right: String="") -> Control:
	var h:=hbox(10)
	var l:=label(text,17,GOLD_HI,true);h.add_child(l)
	var line:=rule();line.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	if right!="":h.add_child(label(right,14,DIM))
	return h

## 金属の円盤に色の記号（縁は色の輪と金の細輪）。
static func icon_disc(icon: String,px: int,color: Color,ring: bool=true) -> Control:
	var d:=Disc.new();d.color=color;d.ring=ring;d.icon=Icons.tex(icon,int(px*0.6))
	d.custom_minimum_size=Vector2(px,px);d.size_flags_vertical=Control.SIZE_SHRINK_CENTER;d.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	return d

## 札（暗い地に色の縁と色の字）。記号を添えられる。
static func pill(text: String,color: Color,icon: String="",size: int=14) -> PanelContainer:
	var p:=PanelContainer.new()
	var s:=box(color.darkened(0.62),color.darkened(0.1),1,2,0)
	s.content_margin_left=9;s.content_margin_right=10;s.content_margin_top=1;s.content_margin_bottom=2
	p.add_theme_stylebox_override("panel",s)
	var h:=hbox(5);p.add_child(h)
	if icon!="":h.add_child(Icons.rect(icon,size+2,color.lightened(0.25)))
	var l:=label(text,size,color.lightened(0.35));l.add_theme_font_override("font",bold_font);outline(l,3)
	h.add_child(l)
	p.mouse_filter=Control.MOUSE_FILTER_PASS
	p.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return p

## 小さな札（pill より控えめ）。
static func chip(text: String,color: Color=DIM,size: int=13,icon: String="") -> PanelContainer:
	var p:=PanelContainer.new()
	var s:=box(Color(color.darkened(0.7),0.85),Color(color,0.45),1,2,0)
	s.content_margin_left=8;s.content_margin_right=10;s.content_margin_top=1;s.content_margin_bottom=2
	p.add_theme_stylebox_override("panel",s)
	var h:=hbox(5);p.add_child(h)
	if icon!="":h.add_child(Icons.rect(icon,size+2,color.lightened(0.15)))
	var l:=label(text,size,color.lightened(0.25));l.add_theme_font_override("font",bold_font)
	h.add_child(l)
	p.mouse_filter=Control.MOUSE_FILTER_PASS
	p.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return p

## 素質などの文字の紋章（暗い地に色の縁と色の字の小さな盾）。
static func gem(text: String,color: Color,px: int=26) -> Control:
	var g:=Gem.new();g.text=text;g.color=color;g.custom_minimum_size=Vector2(px,px);g.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return g

## 一覧の行の形。選んでいる行は金の枠と、左に深紅の帯。
static func row_box(selected: bool,accent: Color=GOLD,pad: int=12) -> StyleBoxFlat:
	var s:=box(Color("2a1c21") if selected else Color("1c1417"),accent if selected else Color("33262a"),1,2,pad)
	if selected:
		s.border_width_left=4;s.shadow_size=8;s.shadow_color=Color(accent,0.18)
	s.content_margin_left=pad+(0 if selected else 3)
	return s

## 行（押せる）。hover で明るくなる。
static func list_row(selected: bool,accent: Color=GOLD,pad: int=12) -> PanelContainer:
	var p:=PanelContainer.new()
	var normal:=row_box(selected,accent,pad)
	var hover:=row_box(selected,accent,pad);hover.bg_color=hover.bg_color.lightened(0.05)
	if not selected:hover.border_color=GOLD.darkened(0.35)
	p.add_theme_stylebox_override("panel",normal)
	p.mouse_filter=Control.MOUSE_FILTER_STOP
	p.mouse_entered.connect(func():p.add_theme_stylebox_override("panel",hover))
	p.mouse_exited.connect(func():p.add_theme_stylebox_override("panel",normal))
	return p

## 画面に入るときの動き：下から少し上がりながら現れる。
static func rise_in(c: CanvasItem,delay: float=0.0,dist: float=16.0) -> void:
	if not c is Control:return
	var ctl: Control=c
	ctl.modulate.a=0.0
	var to: Vector2=ctl.position
	ctl.position=to+Vector2(0,dist)
	var tw:=ctl.create_tween().set_parallel()
	tw.tween_property(ctl,"modulate:a",1.0,0.3).set_delay(delay)
	tw.tween_property(ctl,"position",to,0.4).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ───────── 画面の共通の形 ─────────
## 画面の見出し（左上）：戻るボタン・記号の円盤・大きな題。返り値の HBox は画面へ足してある。
static func screen_head(parent: Control,icon: String,text: String,back_text: String="",back_cb: Callable=Callable(),color: Color=Color.TRANSPARENT) -> HBoxContainer:
	var head:=hbox(16);head.position=Vector2(28,80);parent.add_child(head)
	if back_cb.is_valid():
		var b:=icon_button("back",back_text,back_cb,16);b.size_flags_vertical=Control.SIZE_SHRINK_CENTER;head.add_child(b)
	head.add_child(icon_disc(icon,46,color if color.a>0 else CRIMSON.lightened(0.3)))
	head.add_child(title(text,38))
	rise_in(head,0.0,10.0)
	return head

## 決まった位置と大きさの面（枠つき）を parent に置く。
static func placed_panel(parent: Control,rect: Rect2,pad: int=16,bg: Color=Color(PANEL,0.95)) -> PanelContainer:
	var p:=panel(bg,LINE,pad)
	p.position=rect.position;p.size=rect.size;p.custom_minimum_size=rect.size
	parent.add_child(p)
	return p

## 縦に流れる中身（はみ出したら縦に送る）。panel の中に置く。
static func scroll_box(parent: Control,sep: int=8) -> VBoxContainer:
	var sc:=ScrollContainer.new();sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical=Control.SIZE_EXPAND_FILL;sc.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(sc)
	var pad:=MarginContainer.new();pad.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pad.add_theme_constant_override("margin_right",10)
	sc.add_child(pad)
	var v:=vbox(sep);v.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pad.add_child(v)
	return v

## 床の魔法陣（楕円に潰す）。ci の _draw から呼ぶ。t は回る時間。
static func draw_sigil(ci: CanvasItem,center: Vector2,R: float,color: Color,t: float,squash: float=0.32,glow: bool=true) -> void:
	ci.draw_set_transform(center,0,Vector2(1,squash))
	if glow:
		ci.draw_circle(Vector2.ZERO,R*1.05,Color(0,0,0,0.45))
		ci.draw_circle(Vector2.ZERO,R*0.95,Color(color,0.14+0.05*sin(t*2.0)))
	ci.draw_arc(Vector2.ZERO,R,0,TAU,96,Color(color,0.85),3,true)
	ci.draw_arc(Vector2.ZERO,R*0.9,0,TAU,96,Color(color,0.6),1.5,true)
	ci.draw_arc(Vector2.ZERO,R*0.55,0,TAU,72,Color(color,0.6),1.5,true)
	var a0: float=t*0.25
	var star:=PackedVector2Array()
	for i in 6:
		var a: float=a0+TAU*float((i*2)%5)/5.0-PI*0.5
		star.append(Vector2(cos(a),sin(a))*R*0.9)
	ci.draw_polyline(star,Color(color,0.7),2,true)
	for i in 24:
		var a: float=-a0*0.6+TAU*i/24.0
		ci.draw_line(Vector2(cos(a),sin(a))*R*0.9,Vector2(cos(a),sin(a))*(R*(0.97 if i%2==0 else 0.94)),Color(color,0.7),1.5)
	ci.draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

## 飾りの横線（中央に菱形、両側へ細る）。見出しの上下などに。
static func flourish(width: float=520) -> Control:
	var f:=Flourish.new();f.custom_minimum_size=Vector2(width,14);f.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;f.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return f

class Flourish extends Control:
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var y:=size.y*0.5;var c:=size.x*0.5
		for i in 2:
			var s: float=-1.0 if i==0 else 1.0
			var pts:=PackedVector2Array([Vector2(c+s*12,y-1.2),Vector2(c+s*c,y),Vector2(c+s*12,y+1.2)])
			draw_colored_polygon(pts,Color(U.GOLD,0.7))
			draw_circle(Vector2(c+s*26,y),2.2,Color(U.GOLD,0.8))
		draw_colored_polygon(PackedVector2Array([Vector2(c,y-6),Vector2(c+6,y),Vector2(c,y+6),Vector2(c-6,y)]),U.GOLD)
		draw_colored_polygon(PackedVector2Array([Vector2(c,y-2.5),Vector2(c+2.5,y),Vector2(c,y+2.5),Vector2(c-2.5,y)]),U.CRIMSON)

static func vbox(sep: int=8) -> VBoxContainer:
	var v:=VBoxContainer.new();v.add_theme_constant_override("separation",sep);return v

static func hbox(sep: int=10) -> HBoxContainer:
	var h:=HBoxContainer.new();h.add_theme_constant_override("separation",sep);return h

static func spacer(expand: bool=true) -> Control:
	var c:=Control.new()
	if expand:c.size_flags_horizontal=Control.SIZE_EXPAND_FILL;c.size_flags_vertical=Control.SIZE_EXPAND_FILL
	return c

static func gap(px: int) -> Control:
	var c:=Control.new();c.custom_minimum_size=Vector2(px,px);return c

static func separator() -> ColorRect:
	var c:=ColorRect.new();c.color=Color(GOLD,0.22);c.custom_minimum_size=Vector2(1,1);c.mouse_filter=Control.MOUSE_FILTER_IGNORE;return c

static func full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT);c.offset_left=0;c.offset_top=0;c.offset_right=0;c.offset_bottom=0
	return c

## 円の中に一文字の記号（資源・型・堕ち方・部屋の種類）。色と字で区別できるようにする。
static func badge(glyph: String,color: Color,size: int=26,tip: String="") -> Control:
	var b:=Badge.new()
	b.glyph=glyph;b.color=color;b.custom_minimum_size=Vector2(size,size)
	b.tooltip_text=tip
	return b

## 資源は記号（金貨・しずく）の円盤で出す。
static func res_badge(kind: String,size: int=26) -> Control:
	var r: Dictionary=RES[kind]
	var d:=icon_disc(str(r.icon),size,r.color)
	d.tooltip_text=r.name
	return d

## 値の棒。max に対する割合で塗る。
static func meter(value: float,maximum: float,color: Color,width: float=160,height: float=10) -> Control:
	var m:=Meter.new()
	m.value=value;m.maximum=maximum;m.color=color;m.custom_minimum_size=Vector2(width,height)
	return m

static func stage_track(stage: int,size: int=18) -> Control:
	var h:=hbox(4)
	for i in STAGES.size():
		var l:=label(STAGES[i],size,STAGE_COLORS[i] if i==stage else (DIM if i<stage else FAINT))
		if i==stage:l.add_theme_font_override("font",head_font)
		h.add_child(l)
		if i<STAGES.size()-1:h.add_child(label("›",size,FAINT))
	return h

static func fmt(n: float) -> String:
	var v:=int(round(n))
	var s:=str(absi(v))
	var out:=""
	while s.length()>3:
		out=","+s.substr(s.length()-3)+out;s=s.substr(0,s.length()-3)
	return ("-" if v<0 else "")+s+out

static func signed(n: float) -> String:
	return ("+" if n>=0 else "")+fmt(n)

## 角飾りの枠：地は上がわずかに明るい。外に濃い線、内に金の細線、四隅に金のかぎと菱形。
class Ornate extends StyleBox:
	var bg:=Color("1a1216")
	var frame:=Color("c9a45c")
	var corner:=14
	func _draw(ci: RID,r: Rect2) -> void:
		var RS:=RenderingServer
		# 影
		for i in 3:
			var g:=r.grow(3+i*3);g.position.y+=3
			RS.canvas_item_add_rect(ci,g,Color(0,0,0,0.13))
		# 地（上から下へわずかに暗く）
		var top:=bg.lightened(0.05);var bot:=bg.darkened(0.12)
		RS.canvas_item_add_polygon(ci,PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]),PackedColorArray([top,top,bot,bot]))
		# 外の濃い線と内の金の細線
		var o:=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y),r.position])
		RS.canvas_item_add_polyline(ci,o,PackedColorArray([Color("0a0607")]),2.0)
		var q:=r.grow(-4)
		var inner:=PackedVector2Array([q.position,Vector2(q.end.x,q.position.y),q.end,Vector2(q.position.x,q.end.y),q.position])
		RS.canvas_item_add_polyline(ci,inner,PackedColorArray([Color(frame,0.38)]),1.0)
		# 四隅のかぎと菱形
		var c: float=float(corner)
		for k in 4:
			var p: Vector2=[q.position,Vector2(q.end.x,q.position.y),q.end,Vector2(q.position.x,q.end.y)][k]
			var dx: float=1.0 if k in [0,3] else -1.0
			var dy: float=1.0 if k in [0,1] else -1.0
			RS.canvas_item_add_polyline(ci,PackedVector2Array([p+Vector2(0,dy*c),p,p+Vector2(dx*c,0)]),PackedColorArray([frame]),2.0)
			var d:=p+Vector2(dx*4,dy*4)
			RS.canvas_item_add_polygon(ci,PackedVector2Array([d+Vector2(0,-3.5),d+Vector2(3.5,0),d+Vector2(0,3.5),d+Vector2(-3.5,0)]),PackedColorArray([frame.lightened(0.2)]))

class Rule extends Control:
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var y:=size.y*0.5
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(U.GOLD,0.35),1.0)
		var c:=Vector2(minf(size.x*0.5,60),y)
		draw_colored_polygon(PackedVector2Array([c+Vector2(0,-3.5),c+Vector2(3.5,0),c+Vector2(0,3.5),c+Vector2(-3.5,0)]),Color(U.GOLD,0.7))

class Disc extends Control:
	var color:=Color.WHITE
	var ring:=true
	var icon: Texture2D
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_PASS
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var r:=minf(size.x,size.y)*0.5
		var c:=size*0.5
		draw_circle(c+Vector2(0,1.5),r,Color(0,0,0,0.45))
		draw_circle(c,r,Color("140d10"))
		draw_circle(c,r*0.86,color.darkened(0.72))
		if ring:
			draw_arc(c,r-1.2,0,TAU,48,U.GOLD.darkened(0.25),2.0,true)
			draw_arc(c,r*0.86,0,TAU,48,Color(color,0.8),1.5,true)
		if icon!=null:
			var w:=r*1.2
			draw_texture_rect(icon,Rect2(c-Vector2(w,w)*0.5+Vector2(0,1.2),Vector2(w,w)),false,Color(0,0,0,0.5))
			draw_texture_rect(icon,Rect2(c-Vector2(w,w)*0.5,Vector2(w,w)),false,color.lightened(0.2))

class Gem extends Control:
	var text:="?"
	var color:=Color.WHITE
	func _draw() -> void:
		# 小さな盾：上は平ら、下は尖る。
		var w:=size.x;var h:=size.y
		var pts:=PackedVector2Array([Vector2(1,1),Vector2(w-1,1),Vector2(w-1,h*0.62),Vector2(w*0.5,h-1),Vector2(1,h*0.62)])
		draw_colored_polygon(pts,color.darkened(0.7))
		var outline_pts:=pts.duplicate();outline_pts.append(pts[0])
		draw_polyline(outline_pts,color,1.5,true)
		var U=preload("res://game/ui/ui.gd")
		var f: Font=U.head_font
		if f==null:return
		var fs:=int(h*0.56)
		var tw:=f.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		draw_string(f,Vector2((w-tw)*0.5,h*0.44+fs*0.34),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color.lightened(0.3))

class Badge extends Control:
	var glyph:="?"
	var color:=Color.WHITE
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		var r:=minf(size.x,size.y)*0.5
		var c:=size*0.5
		draw_circle(c,r,Color("140d10"))
		draw_circle(c,r*0.84,color.darkened(0.6))
		draw_arc(c,r-1,0,TAU,40,U.GOLD.darkened(0.3),1.5,true)
		var f: Font=U.head_font if U.head_font!=null else U.body_font
		if f==null:return
		var fs:=int(r*1.0)
		var w:=f.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		draw_string(f,Vector2(c.x-w*0.5,c.y+fs*0.36),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color.lightened(0.35))

class Meter extends Control:
	var value:=0.0
	var maximum:=100.0
	var color:=Color.WHITE
	var ghost:=-1.0   # 予測値（-1 なら出さない）
	func _draw() -> void:
		var h:=size.y
		draw_rect(Rect2(Vector2.ZERO,size),Color("0c0809"))
		var f:=clampf(value/maxf(maximum,0.001),0,1)
		if f>0.0:
			var w:=size.x*f
			draw_rect(Rect2(0,0,w,h),color.darkened(0.15))
			draw_rect(Rect2(0,0,w,maxf(h*0.4,1)),Color(color.lightened(0.25),0.8))
			draw_rect(Rect2(w-1,0,1,h),color.lightened(0.5))
		if ghost>=0:
			var g:=clampf(ghost/maxf(maximum,0.001),0,1)
			var a:=minf(f,g);var b:=maxf(f,g)
			draw_rect(Rect2(size.x*a,0,size.x*(b-a),h),Color(1,1,1,0.3) if g>f else Color(0,0,0,0.5))
		draw_rect(Rect2(Vector2.ZERO,size),Color("3a2a26"),false,1.0)

static func stars(n: int,size: int=18) -> Label:
	return label("★".repeat(clampi(n,0,5))+"☆".repeat(clampi(5-n,0,5)),size,GOLD_HI)

## 格の星（並1・良2・稀3・伝説4）を記号で並べる。
static func grade_stars(g: int,px: int=18) -> HBoxContainer:
	var h:=hbox(1)
	var col: Color=GRADE[clampi(g,0,3)].color
	for i in 4:
		h.add_child(Icons.rect("star",px,col if i<=g else Color(1,1,1,0.1)))
	return h

static func grade_label(g: int,size: int=18) -> Label:
	var d: Dictionary=GRADE[clampi(g,0,3)]
	return label(d.name,size,d.color,true)

