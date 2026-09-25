extends SceneTree
func _initialize():call_deferred("run")
func run():
	var P=load("res://game_v2/animation/pack.gd")
	for file in ["pair_greeting__four_knight__1.pack","clips_four_knight.pack"]:
		var d=P.read_pack(file)
		print(file," raws=",d.raws.size())
		var head=d.head
		if head.kind=="pair":
			var st=head.stages.values()[0]
			for k in st:print("  compiled.",k," ",var_to_bytes(st[k]).size())
			for k in st.tracks[0]:print("    track.",k," ",var_to_bytes(st.tracks[0][k]).size())
		else:
			var m=head.clips.values()[0]
			for k in m:print("  clip.",k," ",var_to_bytes(m[k]).size())
	quit()
