extends CanvasLayer
## 診断の表示（スマホなど手元で原因を見られない端末用）。ブラウザ版は URL に ?diag=1 を付けると出る（デスクトップは --diag）。
## GPU の名前・WebGL の上限・ゲームの状態（役者・場面・FPS）と、エンジンのエラー（シェーダーの失敗など）を画面に出す。
const G=preload("res://game/core/g.gd")
const Perf=preload("res://game/core/perf.gd")

class Catch extends Logger:
	var owner_ref: WeakRef
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,editor_notify: bool,error_type: int,script_backtraces: Array[ScriptBacktrace]) -> void:
		var d=owner_ref.get_ref()
		if d!=null:d.add_error((code+" "+rationale).strip_edges())
	func _log_message(message: String,error: bool) -> void:
		var d=owner_ref.get_ref()
		if d!=null and error:d.add_error(message.strip_edges())

var errors: Dictionary={}     # 文 → 回数
var order: Array=[]
var label: Label
var gpu:=""
var t:=0.0

static func wanted() -> bool:
	if "--diag" in OS.get_cmdline_user_args():return true
	if OS.has_feature("web"):
		var q=JavaScriptBridge.eval("window.location.search",true)
		return q is String and "diag" in q
	return false

func _ready() -> void:
	layer=4000
	var c:=Catch.new();c.owner_ref=weakref(self);OS.add_logger(c)
	label=Label.new();label.position=Vector2(8,8);label.custom_minimum_size=Vector2(1180,0);label.autowrap_mode=TextServer.AUTOWRAP_ARBITRARY
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var sb:=StyleBoxFlat.new();sb.bg_color=Color(0,0,0,0.78);sb.set_content_margin_all(10);label.add_theme_stylebox_override("normal",sb)
	# 画面の UI とは別の層なので、文字は同梱のフォントを直接当てる（ブラウザ版は OS のフォントが無い）
	label.add_theme_font_override("font",load("res://game/ui/fonts/NotoSansJP-sub.ttf"))
	label.add_theme_font_size_override("font_size",20);label.add_theme_color_override("font_color",Color("f0e6c8"));add_child(label)
	if OS.has_feature("web"):
		gpu=str(JavaScriptBridge.eval("""(() => { try { const c=document.createElement('canvas').getContext('webgl2'); if(!c) return 'WebGL2 なし';
const d=c.getExtension('WEBGL_debug_renderer_info'); const g=(n)=>c.getParameter(c[n]);
const hp=c.getShaderPrecisionFormat(c.FRAGMENT_SHADER,c.HIGH_FLOAT);
return (d?c.getParameter(d.UNMASKED_RENDERER_WEBGL):c.getParameter(c.RENDERER))+' / 頂点テクスチャ '+g('MAX_VERTEX_TEXTURE_IMAGE_UNITS')+' / 最大 '+g('MAX_TEXTURE_SIZE')+' / 配列 '+g('MAX_ARRAY_TEXTURE_LAYERS')+' / 頂点uniform '+g('MAX_VERTEX_UNIFORM_VECTORS')+' / 断片highp '+hp.precision+' / float線形 '+(!!c.getExtension('OES_texture_float_linear'))+' / DPR '+window.devicePixelRatio+' / '+navigator.userAgent;
} catch(e) { return 'ERR '+e; } })()""",true))
	else:
		gpu=RenderingServer.get_video_adapter_name()+" / "+RenderingServer.get_video_adapter_api_version()

func add_error(text: String) -> void:
	if text=="":return
	text=text.substr(0,300)
	if not errors.has(text):order.append(text);errors[text]=0
	errors[text]=int(errors[text])+1

func _process(delta: float) -> void:
	t+=delta
	if t<0.5:return
	t=0.0
	var lines: Array=["【診断】 "+gpu]
	lines.append("軽量 %s　FPS %d　画面 %s　描画命令 %d"%[str(Perf.lite),Engine.get_frames_per_second(),str(G.main.current_name) if G.main!=null else "-",int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if G.anim!=null:
		var br=G.anim.bridge
		var shown:=0
		if br!=null and br.world!=null:
			for m in br.world.meshes:
				if is_instance_valid(m) and m.visible:shown+=1
		lines.append("動作データ ready=%s loading=%s 誤り=%s　借りた役者 %d　見えている役者 %d　場面 %d"%[str(G.anim.ready_ok),str(G.anim.loading),str(G.anim.error),G.anim.used.size() if "used" in G.anim else -1,shown,br.pairs.size() if br!=null else -1])
		if br!=null and br.resources!=null:
			var rs=br.resources
			lines.append("絵のページ %d　顔 %d　動作のページ %d　表示表 %d　見た目の焼き込み %s"%[rs.body_images.size(),rs.face_images.size(),rs.page_bytes.size(),rs.views.size(),str(preload("res://mini/layered2d/prepare/looks.gd").enabled)])
	lines.append("エラー %d 種類："%order.size())
	for e in order.slice(maxi(0,order.size()-14)):lines.append("×%d  %s"%[int(errors[e]),e])
	label.text="\n".join(lines)
