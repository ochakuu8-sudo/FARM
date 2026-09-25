extends RefCounted
## 端末に合わせた軽さ。スマホ（ブラウザ・アプリ）では自動で軽量にする（姿勢の計算を毎秒30回・動作の置き場16ページ・フレームは30まで）。
## 確認用にコマンドラインの --lite / --full で上書きできる（デスクトップでスマホの設定を試す）。
static var lite: bool=detect()

static func detect() -> bool:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if "--full" in args:return false
	if "--lite" in args:return true
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

## アニメーション（姿勢の計算）を進める回数（毎秒）。0 は毎フレーム。表示と画面の移動は毎フレームのまま。
static func anim_hz() -> float:
	return 30.0 if lite else 0.0
