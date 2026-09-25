extends SceneTree
## UIの記号の一覧を1枚に並べて書き出す（見た目の確認用）。
##   "<Godot>" --headless --path . --script res://game/tests/icon_sheet.gd -- --out=<png>
const Icons=preload("res://game/ui/icons.gd")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var out:="res://game/tests/icon_sheet.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):out=a.substr(6)
	var names: Array=Icons.SVG.keys()
	var cols:=10;var cell:=72
	var sheet:=Image.create(cols*cell,int(ceil(names.size()/float(cols)))*cell,false,Image.FORMAT_RGBA8)
	sheet.fill(Color("1c1826"))
	for i in names.size():
		var t: Texture2D=Icons.tex(names[i],24)
		if t==null:print("BAD ",names[i]);continue
		var img: Image=t.get_image()
		if img.is_compressed():img.decompress()
		img.clear_mipmaps();img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),Vector2i((i%cols)*cell+12,(i/cols)*cell+12))
	sheet.save_png(out)
	print("ICONS ",names.size()," ",out)
	quit()
