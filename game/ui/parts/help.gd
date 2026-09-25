extends RefCounted
## 画面ごとの短い案内（初めて開いたときに1度だけ。右上の「？」でもう一度見られる）。
const G=preload("res://game/core/g.gd")
const Ui=preload("res://game/ui/ui.gd")
const Icons=preload("res://game/ui/icons.gd")
const TOPICS:={
	"ranch":["牧場","魔王城の地下。捕らえた女を使い、魔物の卵を産ませ、魔物を育てる。
・左の一覧で女か魔物を押すと、入れられる施設が地図で光り、施設の上に見込みが出る。光る施設を押すか、札を引きずって落として入れる。
・女の入れ先：房（仕込む）・苗床（父と同じ種族の卵）・召喚陣（精気で抽選の卵）・搾り場（精気を絞る）・牢。
・魔物の入れ先：房（相手役。その房の能力が伸びる）・苗床（父）・巣（休む）。務めた晩は体力が戻らない。
・地図の施設を押すと、中の様子（場面・卵の予想）を見られる。流す場面・女の表情・服も施設ごとに選べる（見た目だけで、効き目は家具で決まる）。
・家具はほとんど1マス。詰めて並べ、「動かす」「向きを変える」で好きに組める。飾り（燭台・鎖の柱・敷物など）も置ける。
・子の素質（能力の上限）は母で決まる。強い子が欲しければ強い女を捕らえる。
・「出撃」で大陸の地図へ。スタミナの許す限り何度でも出撃できる。
・準備ができたら「一日を終える」。Q / E で視点を回し、ホイールで寄る。右ドラッグか WASD で動かす。"],
	"world":["大陸の地図","出撃先を選ぶ。
・狩場：日替わりで一行が変わる。名前なしの女とお金。遠い地方ほど強い女が出る。
・ストーリー戦：名前付きの女がいる。最後まで破ると次の地方が開く。
・出撃先ごとに使うスタミナが違う。連戦は2戦目から半分。負けてもスタミナは戻らない。"],
	"prep":["編成と配置","魔物を4体選び、左の4列に置く。戦闘が始まったら動かせないので、並べ方が作戦になる。
・右に一行の陣が見える。騎士は後衛を守り、盗賊は端を回って後ろを狙い、術と回復は奥から撃つ。騎士の守りは力の痛手だけ減らす（術は抜ける）。
・種族ごとに役割（盾・近接・暗殺・遠距離・術・妨害・回復・支援）がある。右上に出撃の役割のそろい方が出る。前に盾、後ろに遠距離や回復、のように組む。
・左の一覧で魔物を押し、盤の光るマスを押して置く。置いた魔物を押すと外せる。
・右に一行の職と能力が出る。職ごとに動き方が決まっている（騎士はかばう、神官は癒やして縛りを解く、盗賊は後ろへ回る、魔術師は離れて術、戦士は縛りを引きちぎる）。
・体力は戦闘をまたいで持ち越す。減った魔物は牧場の巣で休ませる。"],
	"battle":["戦闘","配置したら、あとは見守る。移動・通常攻撃・スキルはすべて自動で、乱数はない（同じ配置と号令なら同じ結果）。
・魔物4体の前に、雑兵が並んで盾になる。雑兵は戦闘の中だけの兵。
・号令は1戦に2回：「狙え」（F）で押した女を全員で狙い、「押し込め」（R）で全員が速まりスキルが溜まる。
・魔物は一番近い女へ向かって自由に動き、射程に入ると殴る。遠くから撃つ者は矢や術を飛ばす。
・スキルは魔物ごとに溜まり、溜まると自動で撃つ。溜まりの速さは速で、効き目は能力で決まる。
・一行が全員倒れたら勝ち。倒れた女は全員獲得する。魔物が全員倒れるか、時間切れなら負け（スタミナと体力を失う）。
・速さ×1・×2・×4、Space で止める、Q / E で視点を回す。"],
}

static func first(topic: String) -> void:
	var seen: Dictionary=G.state.flags.get("help_seen",{})
	if seen.has(topic):return
	seen[topic]=true;G.state.flags.help_seen=seen
	show_topic(topic,false)

static func show_topic(topic: String,_force: bool) -> void:
	if not TOPICS.has(topic):return
	var t: Array=TOPICS[topic]
	var icons:={"ranch":"castle","world":"map","prep":"group","battle":"sword"}
	var p:=Ui.panel(Color(Ui.PANEL,0.99),Ui.LINE,32);p.custom_minimum_size=Vector2(900,0)
	var v:=Ui.vbox(12);p.add_child(v)
	var th:=Ui.hbox(14);v.add_child(th)
	th.add_child(Ui.icon_disc(str(icons.get(topic,"scroll")),52,Ui.GOLD))
	var tv:=Ui.vbox(0);th.add_child(tv)
	tv.add_child(Ui.label("案内",14,Ui.DIM,true))
	tv.add_child(Ui.title(t[0],32))
	v.add_child(Ui.rule())
	for line in str(t[1]).split("\n"):
		var bullet: bool=line.begins_with("・")
		var lh:=Ui.hbox(10);v.add_child(lh)
		if bullet:
			var d:=Icons.rect("gem",14,Ui.GOLD);d.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;lh.add_child(d)
		lh.add_child(Ui.wrap_label(line.trim_prefix("・"),18,Ui.TEXT if bullet else Ui.GOLD_HI,820))
	var h:=Ui.hbox();h.alignment=BoxContainer.ALIGNMENT_END;v.add_child(h)
	var layer: Control
	var ok:=Ui.icon_button("star","わかった",func():G.main.close_overlay(layer),20);Ui.primary_style(ok);ok.custom_minimum_size=Vector2(220,54);h.add_child(ok)
	layer=G.main.overlay(p,0.45,true)
