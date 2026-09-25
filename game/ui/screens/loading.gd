extends Control
## 起動時の読み込み。動作データ（pc.bin ほか）を一度だけ読み、全画面で使い回す（7〜10秒）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Anim=preload("res://game/core/anim.gd")
var status: Label
var dots:=0.0
var sigil: Sigil

func open(_p: Dictionary) -> void:
	var c:=CenterContainer.new();Ui.full(c);add_child(c)
	var v:=Ui.vbox(16);v.alignment=BoxContainer.ALIGNMENT_CENTER;c.add_child(v)
	sigil=Sigil.new();sigil.custom_minimum_size=Vector2(220,120);sigil.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;v.add_child(sigil)
	var t:=Ui.title("魔王の娘の魔物牧場",54);t.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(t)
	v.add_child(Ui.flourish(520))
	status=Ui.label("動作データを読み込んでいます",20,Ui.DIM);status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;v.add_child(status)
	if not G.db.problems.is_empty():
		status.text="データに問題があります（game/data）"
		var box:=Ui.panel();box.custom_minimum_size=Vector2(900,0);v.add_child(box)
		box.add_child(Ui.wrap_label("\n".join(G.db.problems.slice(0,20)),18,Ui.DANGER,860))
		return
	start.call_deferred()

func start() -> void:
	# 読み込みの文字を描いてから重い処理に入る。
	await get_tree().process_frame
	await get_tree().process_frame
	# 動作データは裏で読み込み、タイトルはすぐ出す（読み終わるまで始める・続きのボタンは待つ）。
	if G.anim==null:
		G.anim=Anim.new();G.anim.name="Anim"
		G.main.add_child(G.anim)
		G.main.move_child(G.anim,0)
		G.anim.setup_async()
	G.main.after_loading()

func _process(delta: float) -> void:
	dots+=delta
	if sigil!=null:sigil.t=dots;sigil.queue_redraw()
	if status!=null and status.text.begins_with("動作データを読み込んでいます"):
		status.text="動作データを読み込んでいます"+".".repeat(int(dots*3)%4)

class Sigil extends Control:
	var t:=0.0
	func _draw() -> void:
		var U=preload("res://game/ui/ui.gd")
		U.draw_sigil(self,size*0.5,56,U.CRIMSON.lightened(0.3),t*2.0,1.0)
