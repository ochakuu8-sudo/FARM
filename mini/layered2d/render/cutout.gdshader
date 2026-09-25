shader_type canvas_item;
render_mode unshaded;
// 役者の行。材質を行ごとに分けて渡す（resource_store.gd の material_for）。
// インスタンス変数（instance uniform）は GLES3 で1ノード16枠・全体4096枠＝256ノードまでしか持てないので使わない。
uniform int actor_row = 0;
uniform sampler2D actor_state : filter_nearest, repeat_disable;
uniform sampler2D binding_table : filter_nearest, repeat_disable;
uniform sampler2D shape_edges : filter_nearest, repeat_disable;
uniform sampler2D view_table : filter_nearest, repeat_disable;
uniform sampler2D chart_table : filter_nearest, repeat_disable;
uniform sampler2DArray motion_pages : filter_nearest, repeat_disable;
uniform sampler2DArray body_pages : filter_linear, repeat_disable;
uniform sampler2DArray face_pages : filter_linear, repeat_disable;
varying flat int image_layer;
varying flat int is_face;
// 胸の領域の確認用の色付け（束縛表 soft の debug が 0 より大きいとき）。
varying float soft_debug;

vec4 frame_field(int address, int layer, int field, int slot) {
	int p = address + slot * 4 + field;
	return texelFetch(motion_pages, ivec3(p % 256,p / 256,layer),0);
}
vec4 blend_quat(vec4 a, vec4 b, float t) {
	if (dot(a,b)<0.0) b=-b;
	return normalize(mix(a,b,t));
}
vec3 rotate_q(vec4 q, vec3 p) { return p + 2.0*cross(q.xyz,cross(q.xyz,p)+q.w*p); }
vec4 multiply_q(vec4 a, vec4 b) { return vec4(a.w*b.xyz+b.w*a.xyz+cross(a.xyz,b.xyz),a.w*b.w-dot(a.xyz,b.xyz)); }
vec3 anchor_world(int slot) {
	vec4 s=texelFetch(actor_state,ivec2(0,actor_row),0);
	vec3 p=mix(frame_field(int(s.x),int(s.w),3,slot).xyz,frame_field(int(s.y),int(s.w),3,slot).xyz,s.z);
	vec4 timing=texelFetch(actor_state,ivec2(2,actor_row),0);
	if(timing.x>0.0){
		vec4 n=texelFetch(actor_state,ivec2(1,actor_row),0);
		p=mix(p,mix(frame_field(int(n.x),int(n.w),3,slot).xyz,frame_field(int(n.y),int(n.w),3,slot).xyz,n.z),timing.x);
	}
	if(texelFetch(actor_state,ivec2(3,actor_row),0).w>0.5){
		vec4 place=texelFetch(actor_state,ivec2(7,actor_row),0);
		p=rotate_q(texelFetch(actor_state,ivec2(6,actor_row),0),p*place.w)+place.xyz;
	}
	return p;
}
int binding_column(int s){return s<23?s*4:160+(s-23)*4;}
vec2 screen_point(vec3 p,vec3 right,vec3 up){return vec2(dot(p,right),-dot(p,up));}
vec2 surface_point(vec2 uv,vec2 ex,vec2 ey,float l00,float l10,float l11){
	vec2 p=(uv-0.5)*2.0;return ex*(l00*p.x)+ey*(l10*p.x+l11*p.y);
}
void projected_surface(vec4 q,vec3 radii,vec3 right,vec3 up,out vec2 ex,out vec2 ey,out vec3 size){
	vec3 bx=rotate_q(q,vec3(1,0,0)),by=rotate_q(q,vec3(0,1,0)),bz=rotate_q(q,vec3(0,0,1));
	ey=vec2(dot(by,right),-dot(by,up));
	if(dot(ey,ey)<0.000001)ey=vec2(dot(bz,right),-dot(bz,up));
	if(dot(ey,ey)<0.000001)ey=vec2(0,-1);
	ey=-normalize(ey);ex=vec2(ey.y,-ey.x);
	vec3 wx=right*ex.x-up*ex.y,wy=right*ey.x-up*ey.y;
	vec3 lx=vec3(dot(wx,bx),dot(wx,by),dot(wx,bz)),ly=vec3(dot(wy,bx),dot(wy,by),dot(wy,bz));
	vec3 rr=radii*radii;
	size.x=sqrt(max(dot(lx*lx,rr),0.00000001));size.y=dot(lx*ly,rr)/size.x;
	size.z=sqrt(max(dot(ly*ly,rr)-size.y*size.y,0.000001));
}
vec4 collar_frame(int row,vec3 view,vec3 right,vec3 up){
	// The target is the actual rendered collar, not the old skeleton's neck height.
	vec4 t=texelFetch(actor_state,ivec2(0,actor_row),0),timing=texelFetch(actor_state,ivec2(2,actor_row),0);
	vec3 c=mix(frame_field(int(t.x),int(t.w),0,2).xyz,frame_field(int(t.y),int(t.w),0,2).xyz,t.z);
	vec4 q=blend_quat(frame_field(int(t.x),int(t.w),1,2),frame_field(int(t.y),int(t.w),1,2),t.z);
	vec3 dims=mix(frame_field(int(t.x),int(t.w),2,2).xyz,frame_field(int(t.y),int(t.w),2,2).xyz,t.z);
	if(timing.x>0.0){
		vec4 n=texelFetch(actor_state,ivec2(1,actor_row),0);
		c=mix(c,mix(frame_field(int(n.x),int(n.w),0,2).xyz,frame_field(int(n.y),int(n.w),0,2).xyz,n.z),timing.x);
		q=blend_quat(q,blend_quat(frame_field(int(n.x),int(n.w),1,2),frame_field(int(n.y),int(n.w),1,2),n.z),timing.x);
		dims=mix(dims,mix(frame_field(int(n.x),int(n.w),2,2).xyz,frame_field(int(n.y),int(n.w),2,2).xyz,n.z),timing.x);
	}
	vec4 binding0=texelFetch(binding_table,ivec2(8,row),0),binding1=texelFetch(binding_table,ivec2(9,row),0);
	vec3 radii=binding0.xyz*(binding0.w>0.5?dims:vec3(1));
	c+=binding1.w>0.5?rotate_q(q,binding1.xyz):binding1.xyz;
	if(texelFetch(actor_state,ivec2(3,actor_row),0).w>0.5){
		vec4 member=texelFetch(actor_state,ivec2(6,actor_row),0),place=texelFetch(actor_state,ivec2(7,actor_row),0);
		c=rotate_q(member,c*place.w)+place.xyz;radii*=place.w;q=multiply_q(member,q);
	}
	vec3 local_view=vec3(dot(view,rotate_q(q,vec3(1,0,0))),dot(view,rotate_q(q,vec3(0,1,0))),dot(view,rotate_q(q,vec3(0,0,1))));
	int d=int(floor(mod(atan(local_view.x,local_view.z)+6.28318530718,6.28318530718)/0.78539816339+0.5))%8;
	vec2 uv=texelFetch(binding_table,ivec2(96+d,row),0).zw;
	vec2 ex,ey;vec3 size;projected_surface(q,radii,right,up,ex,ey,size);
	float scale=texelFetch(actor_state,ivec2(3,actor_row),0).w>0.5?texelFetch(actor_state,ivec2(7,actor_row),0).w:1.0;
	return vec4(screen_point(c,right,up)+surface_point(uv,ex,ey,size.x,size.y,size.z),screen_point(rotate_q(q,vec3(0,1,0))*scale,right,up));
}
// Rendered waist target includes artwork registration, body proportions and pair placement.
vec2 waist_point(int row,vec2 uv,vec3 right,vec3 up,out vec3 waist_up){
	// The target is the actual rendered collar, not the old skeleton's neck height.
	vec4 t=texelFetch(actor_state,ivec2(0,actor_row),0),timing=texelFetch(actor_state,ivec2(2,actor_row),0);
	vec3 c=mix(frame_field(int(t.x),int(t.w),0,1).xyz,frame_field(int(t.y),int(t.w),0,1).xyz,t.z);
	vec4 q=blend_quat(frame_field(int(t.x),int(t.w),1,1),frame_field(int(t.y),int(t.w),1,1),t.z);
	vec3 dims=mix(frame_field(int(t.x),int(t.w),2,1).xyz,frame_field(int(t.y),int(t.w),2,1).xyz,t.z);
	if(timing.x>0.0){
		vec4 n=texelFetch(actor_state,ivec2(1,actor_row),0);
		c=mix(c,mix(frame_field(int(n.x),int(n.w),0,1).xyz,frame_field(int(n.y),int(n.w),0,1).xyz,n.z),timing.x);
		q=blend_quat(q,blend_quat(frame_field(int(n.x),int(n.w),1,1),frame_field(int(n.y),int(n.w),1,1),n.z),timing.x);
		dims=mix(dims,mix(frame_field(int(n.x),int(n.w),2,1).xyz,frame_field(int(n.y),int(n.w),2,1).xyz,n.z),timing.x);
	}
	vec4 binding0=texelFetch(binding_table,ivec2(4,row),0),binding1=texelFetch(binding_table,ivec2(5,row),0);
	vec3 radii=binding0.xyz*(binding0.w>0.5?dims:vec3(1));
	c+=binding1.w>0.5?rotate_q(q,binding1.xyz):binding1.xyz;
	if(texelFetch(actor_state,ivec2(3,actor_row),0).w>0.5){
		vec4 member=texelFetch(actor_state,ivec2(6,actor_row),0),place=texelFetch(actor_state,ivec2(7,actor_row),0);
		c=rotate_q(member,c*place.w)+place.xyz;radii*=place.w;q=multiply_q(member,q);
	}
	vec2 ex,ey;vec3 size;projected_surface(q,radii,right,up,ex,ey,size);
	waist_up=rotate_q(q,vec3(0,1,0));
	return screen_point(c,right,up)+surface_point(uv,ex,ey,size.x,size.y,size.z);
}
// 揺れる領域（胸・尻）。column は束縛表の開始列、lag_l / lag_r は遅れを入れた部位スロット。
// 遅れ（親ローカル3D）を画面へ投影してずらし、上下の遅れで付け根（領域の上端）を固定して伸縮する。
// 中心基準で縮めると下側の輪郭が内側へ入り、下の部位が覗く。
// grow は大きさの倍率（束縛表149列。1が標準）。領域の上寄りの点を中心に網目を広げる（付け根側は動かさず、下と外へ膨らむ）。
vec2 soft_region(inout vec2 rest,inout float dbg,int column,int lag_l,int lag_r,int d,int row,int a,int b,int layer,float t,vec4 q,vec3 right,vec3 up,float actor_scale,float grow){
	vec2 shift=vec2(0.0);
	vec4 tuning=texelFetch(binding_table,ivec2(column+16,row),0);
	for(int k=0;k<2;k++){
		vec4 region=texelFetch(binding_table,ivec2(column+d*2+k,row),0);
		if(region.z<=0.0)continue;
		int ss=k==0?lag_l:lag_r;
		vec3 lag=mix(vec3(frame_field(a,layer,0,ss).w,frame_field(a,layer,2,ss).w,frame_field(a,layer,3,ss).w),vec3(frame_field(b,layer,0,ss).w,frame_field(b,layer,2,ss).w,frame_field(b,layer,3,ss).w),t)*tuning.y;
		vec2 delta=(rest-region.xy)/region.zw;
		float dist=length(delta);
		float w=1.0-smoothstep(0.25,1.0,dist);
		// 大きさの重みは輪郭の少し外まで届かせる（揺れの重みのままだと輪郭がほとんど動かない）。
		float wg=abs(grow-1.0)>0.001?1.0-smoothstep(0.5,1.6,dist):0.0;
		// 画像の下端を固定する（tuning.w が開始位置、0なら固定しない）。尻の下端はぼかした縁なので、動かすと縁が見えて崩れる。
		if(tuning.w>0.0){float pin=1.0-smoothstep(tuning.w,min(tuning.w+0.16,1.0),rest.y);w*=pin;wg*=pin;}
		dbg=max(dbg,w*tuning.z);
		if(wg>0.0){
			vec2 pivot=vec2(region.x,region.y-region.w*0.3);
			rest=mix(rest,pivot+(rest-pivot)*(1.0+(grow-1.0)*2.0),wg);
		}
		if(w<=0.0)continue;
		shift+=screen_point(rotate_q(q,lag)*actor_scale,right,up)*w;
		float stretch=clamp(1.0-lag.y*tuning.x*2.5,0.86,1.16);
		vec2 hinge=vec2(region.x,region.y-region.w);
		vec2 scaled=hinge+(rest-hinge)*vec2(inversesqrt(stretch),stretch);
		rest=mix(rest,scaled,w);
	}
	return shift;
}
void vertex() {
	int slot = int(CUSTOM0.x);
	vec4 state0 = texelFetch(actor_state,ivec2(0,actor_row),0);
	vec4 state2 = texelFetch(actor_state,ivec2(2,actor_row),0);
	vec4 state3 = texelFetch(actor_state,ivec2(3,actor_row),0);
	int binding_row = int(state3.x);
	// 付属物（枠23〜27）は束縛表の160列から。耳（25）は頭（4）の半径・位置・首の補正を使い、向きの表と広がりだけ自分の列。
	int bslot=slot==25?4:slot;
	vec4 binding0 = texelFetch(binding_table,ivec2(binding_column(bslot),binding_row),0);
	vec4 binding1 = texelFetch(binding_table,ivec2(binding_column(bslot)+1,binding_row),0);
	vec4 binding2 = texelFetch(binding_table,ivec2(binding_column(bslot)+2,binding_row),0);
	vec4 binding3 = texelFetch(binding_table,ivec2(binding_column(bslot)+3,binding_row),0);
	vec4 prop0=vec4(0.0),prop2=vec4(0.0),prop3=vec4(0.0);
	bool prop_hidden=false;
	if(slot>=23){
		prop0=texelFetch(binding_table,ivec2(binding_column(slot),binding_row),0);
		prop2=texelFetch(binding_table,ivec2(binding_column(slot)+2,binding_row),0);
		prop3=texelFetch(binding_table,ivec2(binding_column(slot)+3,binding_row),0);
		// 役者の状態の5列目：x=見せる枠の印（ビット0が枠23）、y=男性器の状態（0通常 1勃起）。
		int mask=int(texelFetch(actor_state,ivec2(5,actor_row),0).x+0.5);
		prop_hidden=prop0.x<=0.0 || ((mask>>(slot-23))&1)==0;
	}
	int a=int(state0.x); int b=int(state0.y); int layer=int(state0.w);
	vec3 center=mix(frame_field(a,layer,0,slot).xyz,frame_field(b,layer,0,slot).xyz,state0.z);
	vec4 q=blend_quat(frame_field(a,layer,1,slot),frame_field(b,layer,1,slot),state0.z);
	vec3 dims=mix(frame_field(a,layer,2,slot).xyz,frame_field(b,layer,2,slot).xyz,state0.z);
	if (state2.x > 0.0) {
		vec4 n=texelFetch(actor_state,ivec2(1,actor_row),0);
		int na=int(n.x);int nb=int(n.y);int nl=int(n.w);
		center=mix(center,mix(frame_field(na,nl,0,slot).xyz,frame_field(nb,nl,0,slot).xyz,n.z),state2.x);
		q=blend_quat(q,blend_quat(frame_field(na,nl,1,slot),frame_field(nb,nl,1,slot),n.z),state2.x);
		dims=mix(dims,mix(frame_field(na,nl,2,slot).xyz,frame_field(nb,nl,2,slot).xyz,n.z),state2.x);
	}
	vec3 radii=binding0.xyz * (binding0.w > 0.5 ? dims : vec3(1.0));
	// 男性器を場面の外で勃起させて見せるとき：付け根を軸に腰の前へ起こす（状態の5列目 z、ラジアン）。場面の中は焼いた向きのまま（z=0）。
	if(slot==27){
		float lift=texelFetch(actor_state,ivec2(5,actor_row),0).z;
		if(abs(lift)>0.001)q=multiply_q(q,vec4(sin(lift*0.5),0.0,0.0,cos(lift*0.5)));
	}
	center += binding1.w > 0.5 ? rotate_q(q,binding1.xyz) : binding1.xyz;
	if (state3.w > 0.5) {
		vec4 member=texelFetch(actor_state,ivec2(6,actor_row),0);
		vec4 place=texelFetch(actor_state,ivec2(7,actor_row),0);
		center=rotate_q(member,center*place.w)+place.xyz;
		radii*=place.w;
		q=multiply_q(member,q);
	}
	float yaw=state2.z;float pitch=state2.w;
	vec3 view=vec3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch));
	vec3 right=vec3(cos(yaw),0.0,-sin(yaw));vec3 up=cross(view,right);
	vec3 bx=rotate_q(q,vec3(1,0,0));vec3 by=rotate_q(q,vec3(0,1,0));vec3 bz=rotate_q(q,vec3(0,0,1));
	vec3 local_view=vec3(dot(view,bx),dot(view,by),dot(view,bz));
	float angle=mod(atan(local_view.x,local_view.z)+6.28318530718,6.28318530718);
	int d=int(floor(angle/0.78539816339+0.5))%8;
	int v=d;
	float elevation=degrees(asin(clamp(local_view.y,-1.0,1.0)));
	is_face=slot==4 ? 1 : 0;
	if ((is_face==1 || slot==25) && elevation>62.5) v=8;
	vec2 local_uv=UV;
	if (is_face==1) local_uv=texelFetch(chart_table,ivec2(int(CUSTOM0.y),int(binding2.y)+v),0).xy;
	vec2 rest=local_uv;
	// 耳：頭の図集の枠を上へ広げた範囲に描いた絵。形の位置は頭の枠の座標へ写す。
	if(slot==25)rest.y=-prop3.z+rest.y*(1.0+prop3.z);
	// 男性器：付け根（絵の上端）からどこまで見せるか（焼いた半径の縦の比）。
	if(slot==27){float shown=clamp(dims.y,0.0,1.0);rest.y*=shown;local_uv.y*=shown;}
	// 尻尾：付け根を固定して先ほど大きく左右へ振る。
	if(slot==26 && prop3.x>0.0)rest.x+=prop3.x*sin(TIME*6.28318530718*prop3.y+float(actor_row)*1.7)*rest.y*rest.y;
	// Optional waist taper, confined to the joining ends of existing parts.
	// White is the exact legacy path; no motion texture layout changes.
	vec4 edges=texelFetch(shape_edges,ivec2(slot,binding_row),0);
	float top_weight=1.0-smoothstep(0.0,0.36,rest.y);
	float bottom_weight=smoothstep(0.64,1.0,rest.y);
	radii.x*=1.0+(edges.x-1.0)*top_weight+(edges.z-1.0)*bottom_weight;
	radii.z*=1.0+(edges.y-1.0)*top_weight+(edges.w-1.0)*bottom_weight;
	if (is_face==1) {
		float tilt=clamp(elevation-binding3.y,0.0,binding3.w);
		rest.y += (1.0-rest.y)*sin(radians(tilt))*binding3.z*smoothstep(0.27,0.55,rest.y);
	}
	if(slot==0||slot==21||slot==22){
		// 骨盤画像の下への延長（向きごと）。上端はそのままで、伸ばした分だけ中心を下げる。
		float extension=texelFetch(binding_table,ivec2(141+d,binding_row),0).x;
		if(extension>0.0){center-=by*radii.y*extension;radii.y*=1.0+extension;}
	}
	vec2 ex,ey;vec3 size;projected_surface(q,radii,right,up,ex,ey,size);
	float l00=size.x,l10=size.y,l11=size.z;
	vec3 wx=right*ex.x-up*ex.y;
	vec2 soft_shift=vec2(0.0);soft_debug=0.0;
	float soft_scale=state3.w>0.5?texelFetch(actor_state,ivec2(7,actor_row),0).w:1.0;
	// 胸は胸の画像、尻は骨盤の画像（上部・下部左右の3スロットで同じ式を使うので継ぎ目は開かない）。
	vec4 soft_size=texelFetch(binding_table,ivec2(149,binding_row),0);
	if(slot==2)soft_shift=soft_region(rest,soft_debug,106,2,1,d,binding_row,a,b,layer,state0.z,q,right,up,soft_scale,soft_size.x>0.0?soft_size.x:1.0);
	if(slot==0||slot==21||slot==22)soft_shift=soft_region(rest,soft_debug,124,21,22,d,binding_row,a,b,layer,state0.z,q,right,up,soft_scale,soft_size.y>0.0?soft_size.y:1.0);
	vec2 p=(rest-0.5)*2.0;
	vec2 base=screen_point(center,right,up);
	vec2 point=base+ex*(l00*p.x)+ey*(l10*p.x+l11*p.y)+soft_shift;
	if((is_face==1 || slot==25) && binding2.z>0.5){
		vec2 socket=texelFetch(binding_table,ivec2(96+v,binding_row),0).xy;
		float tilt=clamp(elevation-binding3.y,0.0,binding3.w);
		socket.y+=(1.0-socket.y)*sin(radians(tilt))*binding3.z*smoothstep(0.27,0.55,socket.y);
		vec4 collar=collar_frame(binding_row,view,right,up);
		float neck_length=texelFetch(binding_table,ivec2(105,binding_row),0).r;
		point+=collar.xy+collar.zw*neck_length-base-surface_point(socket,ex,ey,l00,l10,l11);
	}
	if(slot==3 && texelFetch(binding_table,ivec2(18,binding_row),0).z>0.5){
		vec4 collar=collar_frame(binding_row,view,right,up);
		float neck_length=texelFetch(binding_table,ivec2(105,binding_row),0).r;
		vec2 axis=collar.zw;
		vec2 across=length(axis)>0.001?normalize(vec2(-axis.y,axis.x)):vec2(1,0);
		// Neck belongs to the body. Its top is hidden under the jaw, its bottom under the collar.
		// No head_scale enters its dimensions. The 8px atlas margin stays outside the join.
		point=collar.xy+axis*mix(neck_length+0.035,-0.025,local_uv.y)+across*(local_uv.x-.5)*2.0*radii.x;
	}
	if(is_face==0 && slot<23 && binding3.w>0.5 && binding3.w<2.5){
		vec2 start=screen_point(anchor_world(slot),right,up);
		vec2 delta=start-base-surface_point(binding2.zw,ex,ey,l00,l10,l11);
		if(binding3.w>1.5){point+=delta*binding3.z;}
		else{
			int end_slot=slot==5?11:(slot==13?19:(slot==6?7:(slot==14?15:(slot==8?12:(slot==16?20:(slot==9?10:18))))));
			vec2 finish=screen_point(anchor_world(end_slot),right,up);
			vec2 delta_end=finish-base-surface_point(binding3.xy,ex,ey,l00,l10,l11);
			point+=(delta*(1.0-smoothstep(0.0,0.7,rest.y))+delta_end*smoothstep(0.3,1.0,rest.y))*binding3.z;
		}
	}
	if(is_face==0 && slot<23 && binding3.w>2.5){
		vec3 hl=anchor_world(8);vec3 hr=anchor_world(16);
		vec3 dl=normalize(anchor_world(12)-hl);vec3 dr=normalize(anchor_world(20)-hr);
		
		float side_projection=clamp(dot(hl-hr,right)/max(length(hl-hr),0.001),-1.0,1.0);
		vec3 leg_dir=mix(dr,dl,0.5+0.5*p.x*side_projection);
		float lower=smoothstep(0.35,1.0,rest.y);
		// Blend the lower seam from the pelvis-local down axis toward the thigh.
		// World UP is incorrect when the pelvis tilts; rear vertices need the same join.
		float join_weight=clamp(binding3.z/0.06,0.0,1.0)*0.85;
		float forward_bend=smoothstep(0.025,0.12,1.0-dot(by,vec3(0,1,0)));
		float actor_scale=state3.w>0.5?texelFetch(actor_state,ivec2(7,actor_row),0).w:1.0;
		vec3 upright=(leg_dir+vec3(0,1,0))*max(dot(wx,bz)*p.x,0.0)*lower*binding3.z*actor_scale;
		vec3 folded=(leg_dir+by)*lower*radii.y*join_weight;
		vec3 correction=mix(upright,folded,forward_bend);
		point+=screen_point(correction,right,up);
		point-=ex*p.x*pow(abs(p.x),2.0)*lower*l00*0.14;
	}
	// Keep the collar fixed; blend the hem into the waist as the torso bends.

	if(slot==2){
		vec2 source_hem=base+surface_point(vec2(rest.x,0.95),ex,ey,l00,l10,l11);
		vec3 waist_up;
		vec2 target_hem=waist_point(binding_row,vec2(rest.x,0.50),right,up,waist_up);
		float bend=smoothstep(0.005,0.12,1.0-dot(by,waist_up));
		point+=(target_hem-source_hem)*smoothstep(0.40,0.95,rest.y)*bend;
	}
	if(prop_hidden)point=vec2(0.0);
	VERTEX=point*state2.y;
	int vr=int(binding2.x)+v;
	if(slot>=23){
		vr=int(prop2.x)+v;
		if(slot==27 && prop2.y>1.5 && texelFetch(actor_state,ivec2(5,actor_row),0).y>0.5)vr+=9;
	}
	if(is_face==1){
		vec4 face_state=texelFetch(actor_state,ivec2(4,actor_row),0);
		if(face_state.y>0.5)vr=int(face_state.x)+v;
	}
	vec4 rect=texelFetch(view_table,ivec2(0,vr),0);
	vec4 info=texelFetch(view_table,ivec2(1,vr),0);
	if(info.y>0.5) local_uv.x=1.0-local_uv.x;
	UV=rect.xy+local_uv*rect.zw;
	image_layer=int(info.x);
}
void fragment() {
	vec4 paint;
	if(is_face==1) paint=texture(face_pages,vec3(UV,float(image_layer)));
	else paint=texture(body_pages,vec3(UV,float(image_layer)));
	COLOR*=paint;
	COLOR.rgb=mix(COLOR.rgb,vec3(1.0,0.1,0.3),clamp(soft_debug,0.0,1.0)*0.55);
}



