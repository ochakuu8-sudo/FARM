extends SceneTree
## 焼いた見た目の読み込みの内訳（画面なしでよい）：WebP の復号・hash・詰める（blit）の時間。
##   Godot_console --headless --path . --script res://game/tests/looks_decode_bench.gd
const Looks=preload("res://mini/layered2d/prepare/looks.gd")
func _initialize():call_deferred("run")
func run():
	var cells: Array=[]
	for f in ["s0","s5","s12","s20","s33"]:
		var d: Dictionary=Looks.data(f)
		for k in d.body:cells.append_array(d.body[k].cells)
	var t0:=Time.get_ticks_usec()
	var images: Array=[]
	for b in cells:images.append(Looks.decode(b))
	var t_dec:=Time.get_ticks_usec()-t0
	t0=Time.get_ticks_usec()
	for im in images:hash(im.get_data())
	var t_hash:=Time.get_ticks_usec()-t0
	var page:=Image.create(2048,2048,false,Image.FORMAT_RGBA8)
	t0=Time.get_ticks_usec()
	var i:=0
	for im in images:
		page.blit_rect(im,Rect2i(0,0,128,128),Vector2i((i%16)*128,(i/16%16)*128));i+=1
	var t_blit:=Time.get_ticks_usec()-t0
	t0=Time.get_ticks_usec()
	for b in cells:
		var im:=Image.new();im.load_webp_from_buffer(b)
	var t_raw:=Time.get_ticks_usec()-t0
	# 形式ごとの復号の速さ：PNG・生の画素を zstd で圧縮したもの
	var pngs: Array=[];var raws: Array=[];var png_bytes:=0;var raw_bytes:=0
	for im in images:
		var pb: PackedByteArray=im.save_png_to_buffer();pngs.append(pb);png_bytes+=pb.size()
		var rb: PackedByteArray=im.get_data().compress(FileAccess.COMPRESSION_ZSTD);raws.append(rb);raw_bytes+=rb.size()
	t0=Time.get_ticks_usec()
	for b in pngs:
		var im2:=Image.new();im2.load_png_from_buffer(b)
	var t_png:=Time.get_ticks_usec()-t0
	t0=Time.get_ticks_usec()
	for b in raws:
		var data: PackedByteArray=b.decompress(128*128*4,FileAccess.COMPRESSION_ZSTD)
		var im3:=Image.create_from_data(128,128,false,Image.FORMAT_RGBA8,data)
	var t_zstd:=Time.get_ticks_usec()-t0
	var webp_bytes:=0
	for b in cells:webp_bytes+=b.size()
	print("LOOKS_FORMATS webp=%.2fms/%.1fKB png=%.2fms/%.1fKB zstd=%.3fms/%.1fKB（1升目あたり 復号/大きさ）"%[t_raw/1000.0/cells.size(),webp_bytes/1024.0/cells.size(),t_png/1000.0/cells.size(),png_bytes/1024.0/cells.size(),t_zstd/1000.0/cells.size(),raw_bytes/1024.0/cells.size()])
	print("LOOKS_DECODE cells=%d decode=%.2fms/升目（変換なし %.2f） hash=%.3fms blit=%.3fms"%[cells.size(),t_dec/1000.0/cells.size(),t_raw/1000.0/cells.size(),t_hash/1000.0/cells.size(),t_blit/1000.0/cells.size()])
	quit()
