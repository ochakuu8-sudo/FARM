extends RefCounted
## 戦場のマスと地形・道探し・射線（設計書 3.1）。戦闘の中の位置は連続した座標（マス (x, y) の中心が x+0.5, y+0.5）で、
## 地形と道探しだけマスで扱う。マスどうしの距離は縦横斜めを同じ1と数える（配置と道探し）。
## 地形：. 床 / # 崖（通れない・射線も通らない）/ ~ 川（中では動きが半分の速さ）/ " 森（離れた所からの攻撃は半分）。
const DIRS:=[Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
var w:=8
var h:=8
var rows: Array=[]

func setup(board_rows: Array) -> void:
	rows=board_rows.duplicate()
	h=rows.size()
	w=str(rows[0]).length() if h>0 else 0

func tile(c: Vector2i) -> String:
	if not inside(c):return "#"
	return str(rows[c.y]).substr(c.x,1)

func inside(c: Vector2i) -> bool:
	return c.x>=0 and c.y>=0 and c.x<w and c.y<h

func passable(c: Vector2i) -> bool:
	return tile(c)!="#"

static func dist(a: Vector2i,b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

## 射線：間のマスに崖がなければ通る。
func los(a: Vector2i,b: Vector2i) -> bool:
	var n: int=dist(a,b)
	if n<=1:return true
	for i in range(1,n):
		var t: float=float(i)/n
		var c:=Vector2i(int(round(lerpf(a.x,b.x,t))),int(round(lerpf(a.y,b.y,t))))
		if tile(c)=="#":return false
	return true

## 斜めに動くとき、両脇が崖なら通れない（角を抜けない）。
func can_step(a: Vector2i,d: Vector2i) -> bool:
	var c: Vector2i=a+d
	if not passable(c):return false
	if d.x!=0 and d.y!=0:
		if not passable(a+Vector2i(d.x,0)) and not passable(a+Vector2i(0,d.y)):return false
	return true

## start から、goal まで reach 以内（射線が通る）のマスへの最短の道（start は含まない）。blocked は人のいるマス。
## 見つからなければ [] 。並びは DIRS の順で決まる（同じ入力なら同じ道）。
func path_to(start: Vector2i,goal: Vector2i,reach: int,blocked: Dictionary) -> Array:
	if dist(start,goal)<=reach and los(start,goal):return []
	var prev: Dictionary={start:start}
	var queue: Array=[start]
	var head:=0
	var found:=Vector2i(-1,-1)
	while head<queue.size():
		var c: Vector2i=queue[head];head+=1
		for d in DIRS:
			var n: Vector2i=c+d
			if prev.has(n) or not inside(n) or not can_step(c,d) or blocked.has(n):continue
			prev[n]=c
			if dist(n,goal)<=reach and los(n,goal):found=n;break
			queue.append(n)
		if found.x>=0:break
	if found.x<0:return []
	var path: Array=[]
	var p: Vector2i=found
	while p!=start:
		path.push_front(p)
		p=prev[p]
	return path

## 隣の空いているマスのうち、from に一番近いもの（跳ぶ技の着地点）。なければ (-1,-1)。
func free_near(target: Vector2i,from: Vector2i,blocked: Dictionary) -> Vector2i:
	var best:=Vector2i(-1,-1);var bd:=999
	for d in DIRS:
		var c: Vector2i=target+d
		if not inside(c) or not passable(c) or blocked.has(c):continue
		var dd: int=dist(c,from)
		if dd<bd:bd=dd;best=c
	return best

# ───────── 連続した座標（戦闘の中） ─────────
static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)),int(floor(p.y)))

## 2点を結ぶ線が崖を通らなければ true（見通しと、まっすぐ歩けるか）。
func clear_line(a: Vector2,b: Vector2) -> bool:
	var n: int=maxi(1,int(ceil(a.distance_to(b)/0.25)))
	for i in range(1,n):
		if tile(cell_of(a.lerp(b,float(i)/n)))=="#":return false
	return true

## 崖を回り込むときの次の目印（マスの道の、見通しの利く一番先のマスの中心）。道がなければ goal。
func waypoint(from: Vector2,goal: Vector2) -> Vector2:
	var path: Array=path_to(cell_of(from),cell_of(goal),0,{})
	if path.is_empty():return goal
	var best: Vector2=Vector2(path[0])+Vector2(0.5,0.5)
	for c in path:
		var p: Vector2=Vector2(c)+Vector2(0.5,0.5)
		if clear_line(from,p):best=p
		else:break
	return best

## 盤の外と崖のマスから押し出す（半径 r の丸として）。
func keep_inside(u: Dictionary,r: float) -> void:
	var p: Vector2=u.pos
	p.x=clampf(p.x,r,w-r);p.y=clampf(p.y,r,h-r)
	var c: Vector2i=cell_of(p)
	for dy in range(-1,2):
		for dx in range(-1,2):
			var cc: Vector2i=c+Vector2i(dx,dy)
			if not inside(cc) or tile(cc)!="#":continue
			var q:=Vector2(clampf(p.x,cc.x,cc.x+1),clampf(p.y,cc.y,cc.y+1))
			var d: Vector2=p-q
			var l: float=d.length()
			if l<r:
				if l<1e-5:
					# 真ん中に入り込んだ：一番近い辺へ出す
					var outs:=[Vector2(cc.x-r,p.y),Vector2(cc.x+1+r,p.y),Vector2(p.x,cc.y-r),Vector2(p.x,cc.y+1+r)]
					var bp: Vector2=outs[0]
					for o in outs:
						if p.distance_to(o)<p.distance_to(bp):bp=o
					p=bp
				else:p=q+d/l*r
	u.pos=p
