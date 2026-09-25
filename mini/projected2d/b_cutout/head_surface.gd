extends RefCounted
var grids:Dictionary={}
var classes:Dictionary={}
var indices:=PackedInt32Array()
func _init(marks:Array,source_views:Array=[])->void:
	var views:=[0,1,2,3,3,3,2,1,3]
	if source_views.is_empty() and marks.size()==5:
		source_views=["front","front_three_quarter_left","left","back","back_three_quarter_left"]
	if not source_views.is_empty():
		var runtime:=["front","front_three_quarter_left","left","back_three_quarter_left","back","back_three_quarter_left","left","front_three_quarter_left","back"]
		for i in range(9):
			views[i]=source_views.find(runtime[i])
			assert(views[i]>=0,"Missing authored direction: "+runtime[i])
	for id in range(9):
		var m:Array=marks[views[id]].duplicate()
		if id in [6,7] or (id==5 and source_views.has("back_three_quarter_left")):
			var left:float=m[0];m[0]=1-m[1];m[1]=1-left
			for k in [3,5,7]:m[k]=1-m[k]
		var ys:=[0.0,.27,m[2],m[4],m[6],m[8],1.0]
		var grid:=PackedVector2Array()
		for y in range(7):
			var xs:Array=[0.0,.16,.34,.5,.66,.84,1.0]
			if y==2:xs=[0.0,m[0]*.5,m[0],(m[0]+m[1])*.5,m[1],(m[1]+1)*.5,1.0]
			elif y in [3,4,5]:
				var x:float=m[3 if y==3 else (5 if y==4 else 7)]
				xs=[0.0,x*.33,x*.66,x,x+(1-x)*.33,x+(1-x)*.66,1.0]
			for x in xs:grid.append(Vector2(x,ys[y]))
		grids[id]=grid;classes[id]=2 if id in [0,1,7] else (1 if id in [2,6] else 0)
	for y in range(6):
		for x in range(6):
			var a:=y*7+x;indices.append_array(PackedInt32Array([a,a+1,a+8,a,a+8,a+7]))
