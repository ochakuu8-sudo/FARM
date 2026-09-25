extends RefCounted
## 焼いた動作を「描画にそのまま載せられる形」に分けて書き出す（packs/）。ゲームはこれを必要な分だけ読む。
##   clips_<原型>.pack                 その原型の単体動作すべて
##   pair_<場面>__<受け>__<相手>.pack   2体場面（その組み合わせの全段階）
##   recipes.pack                      追加素材（four_adventurers.bin 等）の原型のレシピ
##   index.json                        目録（どのファイルに何があるか、元ファイルの更新時刻）
## 各トラックは「目録の情報（frames を除いたもの）」と「動作テクスチャの生のバイト列」に分ける。
## 生のバイト列は ResourceStore.add_track が書くのと同じ並び（1フレーム128テクセル、RGBAF）なので、読むときは写すだけでよい。
## 焼き込み（bake.gd）と four_clips_add.gd の最後に呼ばれる。手で作り直すとき：
##   --headless --path . --script res://game_v2/animation/pack_run.gd
const Store=preload("res://mini/layered2d/prepare/resource_store.gd")
const Neck=preload("res://mini/layered2d/data/neck_attachment.gd")
const Profiles=preload("res://game_v2/animation/profiles.gd")
const DIR:="res://game_v2/assets/bakes/packs/"
const PC:="res://game_v2/assets/bakes/pc.bin"
## 2: 各 pack を zstd で圧縮（動作データは6分の1ほどになる。ブラウザ版のダウンロードを小さくする）
const VERSION:=2

## 元（pc.bin と追加素材の束）の更新時刻。目録と比べて古ければ作り直しが要る。
static func sources() -> Dictionary:
	var out: Dictionary={}
	for path in [PC]+Profiles.bundle_paths():
		out[path]=FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	return out

static func index() -> Dictionary:
	var path:=DIR+"index.json"
	if not FileAccess.file_exists(path):return {}
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

## 目録があり、元より新しければ true。
static func fresh() -> bool:
	var idx: Dictionary=index()
	if idx.is_empty() or int(idx.get("version",0))!=VERSION:return false
	# 書き出した版（ブラウザ版など）は焼いた packs だけを持つ。元と比べる必要がない。
	if OS.has_feature("template"):return true
	var now: Dictionary=sources()
	for path in now:
		if int(idx.get("sources",{}).get(path,-1))!=int(now[path]):return false
	return true

## 1つのトラックを目録の情報と生のバイト列に分ける。
## 2体場面の重ね順（[{actor, slot}, …] の配列）を数字の並び（actor*32+slot）に詰める。首の順は先に並べ替えておく。
static func pack_orders(orders: Array) -> Array:
	var out: Array=[]
	for direction in orders:
		var frames: Array=[]
		for order in direction:
			var sorted: Array=Neck.order_members(order)
			var packed:=PackedInt32Array()
			for part in sorted:packed.append(int(part.actor)*32+int(part.slot))
			frames.append(packed)
		out.append(frames)
	return out

static func encode(track: Dictionary,keep_orders: bool=true) -> Array:
	var frames: Array=track.frames
	var data:=PackedFloat32Array();data.resize(frames.size()*128*4)
	var rest: Array=track.rest_radii
	for f in range(frames.size()):
		var parts: Array=frames[f].parts
		for slot in range(parts.size()):
			var part: Dictionary=parts[slot]
			var pos: Vector3=part.center
			var q: Quaternion=part.rotation
			var d: Vector3=part.radii/rest[slot]
			var anchor: Vector3=part.get("anchor",pos)
			var soft: Vector3=Store.soft_value(parts,slot)
			var i: int=(f*128+slot*4)*4
			data[i]=pos.x;data[i+1]=pos.y;data[i+2]=pos.z;data[i+3]=soft.x
			data[i+4]=q.x;data[i+5]=q.y;data[i+6]=q.z;data[i+7]=q.w
			data[i+8]=d.x;data[i+9]=d.y;data[i+10]=d.z;data[i+11]=soft.y
			data[i+12]=anchor.x;data[i+13]=anchor.y;data[i+14]=anchor.z;data[i+15]=soft.z
	var meta: Dictionary=track.duplicate(false)
	meta.erase("frames")
	# 2体場面のトラックの重ね順は使わない（場面全体の重ね順 orders_packed で描く）。
	if not keep_orders:meta.erase("orders")
	if meta.has("orders"):
		meta.orders=meta.orders.duplicate(true)
		for direction in range(meta.orders.size()):
			for frame in range(meta.orders[direction].size()):meta.orders[direction][frame]=Neck.order_slots(meta.orders[direction][frame])
	meta.orders_normalized=true
	meta.frame_count=frames.size()
	return [meta,data.to_byte_array()]

static func write_pack(path: String,head: Dictionary,raws: Array) -> bool:
	var f:=FileAccess.open_compressed(path+".tmp",FileAccess.WRITE,FileAccess.COMPRESSION_ZSTD)
	if f==null:return false
	f.store_var(head)
	for raw in raws:f.store_var(raw)
	f.close()
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(path+".tmp",path)==OK

## pack を読む。{head, raws}
static func read_pack(file: String) -> Dictionary:
	var path:=DIR+file
	if not FileAccess.file_exists(path):return {}
	var f:=FileAccess.open_compressed(path,FileAccess.READ,FileAccess.COMPRESSION_ZSTD)
	if f==null:f=FileAccess.open(path,FileAccess.READ)   # 圧縮していない古い pack
	var head=f.get_var()
	var raws: Array=[]
	while f.get_position()<f.get_length():raws.append(f.get_var())
	return {"head":head,"raws":raws}

static func pair_file(scene: String,taker: String,partner: String) -> String:
	return "pair_%s__%s__%s.pack"%[scene,taker,partner]

## pc.bin と追加素材の束から packs/ を作る。bundle を渡せば pc.bin を読み直さない。
static func build(bundle: Variant=null) -> Dictionary:
	var begin:=Time.get_ticks_msec()
	if bundle==null:
		if not FileAccess.file_exists(PC):return {"ok":false,"error":"pc.bin がない"}
		bundle=FileAccess.open(PC,FileAccess.READ).get_var()
	var clips: Dictionary=bundle.get("clips",{}).duplicate()
	var recipes: Dictionary={}
	for path in Profiles.bundle_paths():
		if not FileAccess.file_exists(path):continue
		var extra=FileAccess.open(path,FileAccess.READ).get_var()
		if not extra is Dictionary:continue
		clips.merge(extra.get("clips",{}),true)
		recipes.merge(extra.get("recipes",{}),true)
	DirAccess.make_dir_recursive_absolute(DIR)
	var idx: Dictionary={"version":VERSION,"built":Time.get_datetime_string_from_system(),"sources":sources(),"clips":{},"pairs":{},"recipes":"recipes.pack"}
	var bytes:=0
	for profile in clips:
		var metas: Dictionary={};var raws: Array=[];var names: Array=[]
		for clip in clips[profile]:
			var pair: Array=encode(clips[profile][clip])
			metas[clip]=pair[0];raws.append(pair[1]);names.append(clip);bytes+=pair[1].size()
		var file:="clips_%s.pack"%profile
		if not write_pack(DIR+file,{"kind":"clips","profile":profile,"clips":metas,"order":names},raws):return {"ok":false,"error":"書けない: "+file}
		idx.clips[profile]=file
	for key in bundle.get("pair_sets",{}):
		var cast: PackedStringArray=str(key).split("|")
		idx.pairs[key]={}
		for scene in bundle.pair_sets[key]:
			var stages: Dictionary={};var raws2: Array=[]
			for stage in bundle.pair_sets[key][scene]:
				var compiled: Dictionary=bundle.pair_sets[key][scene][stage].duplicate(false)
				var metas2: Array=[]
				for track in compiled.tracks:
					var pair2: Array=encode(track,false)
					# 効果の層（汗・紅潮など）は部位の位置を CPU で投影するので、効果のある場面だけ位置と向きを残す。
					if not compiled.get("effects",[]).is_empty() or not compiled.get("walls",[]).is_empty() or not compiled.get("blocks",[]).is_empty() or not compiled.get("lines",[]).is_empty():
						var light: Array=[]
						for fr in track.frames:
							var parts: Array=[]
							for part in fr.parts:parts.append({"center":part.center,"rotation":part.rotation})
							light.append({"parts":parts})
						pair2[0].frames=light
					metas2.append(pair2[0]);raws2.append(pair2[1]);bytes+=pair2[1].size()
				compiled.tracks=metas2
				compiled.orders_packed=pack_orders(compiled.orders)
				compiled.erase("orders")
				stages[stage]=compiled
			var file2: String=pair_file(scene,cast[0],cast[1])
			if not write_pack(DIR+file2,{"kind":"pair","key":key,"scene":scene,"stages":stages},raws2):return {"ok":false,"error":"書けない: "+file2}
			idx.pairs[key][scene]={"file":file2,"stages":stages.keys()}
	var rf:=FileAccess.open(DIR+"recipes.pack",FileAccess.WRITE);rf.store_var(recipes);rf.close()
	var jf:=FileAccess.open(DIR+"index.json",FileAccess.WRITE);jf.store_string(JSON.stringify(idx,"\t"));jf.close()
	# 目録に載らなくなった古いファイル（骨格に寄せる前の見た目ごとの動作など）を消す。
	var keep: Dictionary={"recipes.pack":true}
	for p in idx.clips:keep[str(idx.clips[p])]=true
	for key in idx.pairs:
		for scene in idx.pairs[key]:keep[str(idx.pairs[key][scene].file)]=true
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".pack") and not keep.has(file):DirAccess.remove_absolute(DIR+file)
	return {"ok":true,"ms":Time.get_ticks_msec()-begin,"motion_mb":bytes/1048576.0}
