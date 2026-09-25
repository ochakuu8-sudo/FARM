extends RefCounted
## 処理時間の積算（重い所を探す）。Prof.on=true のときだけ測る。
##   var t:=Prof.start() … Prof.add("名前",t)
static var on:=false
static var total: Dictionary={}   # 名前 → [回数, マイクロ秒, いちばん長い1回]

static func start() -> int:
	return Time.get_ticks_usec() if on else 0

static func add(name: String,started: int) -> void:
	if not on:return
	var e: Array=total.get(name,[0,0,0])
	var d: int=Time.get_ticks_usec()-started
	e[0]+=1;e[1]+=d;e[2]=maxi(e[2],d)
	total[name]=e

static func report() -> String:
	var names: Array=total.keys()
	names.sort_custom(func(a,b):return total[a][1]>total[b][1])
	var lines: Array=[]
	for n in names:lines.append("%s %.1fms（%d回、最長 %.1fms）"%[n,total[n][1]/1000.0,total[n][0],total[n][2]/1000.0])
	return "\n".join(lines)

static func reset() -> void:
	total={}
