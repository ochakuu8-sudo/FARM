extends "res://mini/projected2d/pose_source.gd"
const Views=preload("res://mini/projected2d/b_cutout/four_views.gd")
const Surface=preload("res://mini/projected2d/b_cutout/head_surface.gd")
const Retarget=preload("res://mini/projected2d/b_cutout/retarget.gd")
const Assets=preload("res://mini/projected2d/assets.gd")
const Spec=preload("res://mini/projected2d/b_cutout/spec.gd")
const Presets=preload("res://mini/projected2d/b_cutout/presets.gd")
const Bundle=preload("res://mini/projected2d/b_cutout/state_bundle.gd")
const Face=preload("res://mini/projected2d/b_cutout/face_parts.gd")
var expression:="neutral"
var face_parts:Dictionary={}
var overlays:Dictionary={}
func expression_list()->Array:
	return config.face.registered.presets.keys() if config.get("face",{}).has("registered") else (Face.PRESETS.keys() if config.has("face") else ["neutral"])
func set_expression(id:String)->Dictionary:
	var result:=Face.validate({"expression":id},config)
	if result.ok:expression=id;face_parts={}
	return result
func set_face_parts(eyes:String,mouth:String)->Dictionary:
	var parts:={"eyes":eyes,"mouth":mouth}
	var result:=Face.validate({"expression":"custom","face_parts":parts},config)
	if result.ok:expression="custom";face_parts=parts
	return result
func set_face_slots(parts:Dictionary)->Dictionary:
	var result:=Face.validate({"expression":"custom","face_parts":parts},config)
	if result.ok:expression="custom";face_parts=parts.duplicate(true)
	return result
func set_overlays(value:Dictionary)->Dictionary:
	var result:=Face.validate({"overlays":value},config)
	if result.ok:overlays=value.duplicate(true)
	return result
func face_state()->Dictionary:
	return {"expression":expression,"face_parts":face_parts.duplicate(true),"overlays":overlays.duplicate(true)}
func set_face_slot_source(slot_id:String,donor_template:String,transparent_transfer:bool=true)->Dictionary:
	if not config.get("face",{}).has("registered"):return {"ok":false,"error":"Receiver has no registered face"}
	var donor:=Spec.new(donor_template)
	if not donor.error.is_empty():return {"ok":false,"error":donor.error}
	if not donor.data.get("face",{}).has("registered"):return {"ok":false,"error":"Donor has no registered face"}
	var candidate:=config.duplicate(true);var found:=false
	for i in range(candidate.face.registered.slots.size()):
		if candidate.face.registered.slots[i].id!=slot_id:continue
		for source in donor.data.face.registered.slots:
			if source.id!=slot_id:continue
			if source.get("placement","rect")!=candidate.face.registered.slots[i].get("placement","rect"):return {"ok":false,"error":"Incompatible face registration: anchors and legacy rectangles cannot be exchanged"}
			if transparent_transfer and not source.has("transfer_variants"):return {"ok":false,"error":"No transparent transfer art: "+slot_id}
			var imported:Dictionary=source.duplicate(true)
			if transparent_transfer:imported.variants=imported.transfer_variants.duplicate(true);imported.paint="over"
			imported.atlas_path=source.get("atlas_path",donor.data.face.atlas_path)
			imported.atlas_row_count=source.get("atlas_row_count",donor.data.face.row_count)
			imported.source_template=donor_template
			candidate.face.registered.slots[i]=imported;found=true;break
	if not found:return {"ok":false,"error":"Missing compatible slot: "+slot_id}
	var validator:=Spec.new()
	if not validator.validate(candidate):return {"ok":false,"error":validator.error}
	var state_check:=Face.validate(face_state(),candidate)
	if not state_check.ok:return state_check
	config=candidate
	return {"ok":true,"reload_atlases":true}
func reset_face_sources()->void:
	if not base_config.get("face",{}).has("registered"):return
	config.face.registered.slots=base_config.face.registered.slots.duplicate(true)
	if not Face.validate(face_state(),config).ok:expression="neutral";face_parts={}
var presets:=Presets.new()
var base_config:Dictionary={}
var preset_id:=""
var preset_report:Dictionary={}
var template_path:=""
var reference_pose:Dictionary={}
var spec
var config:Dictionary={}
var retarget:=Retarget.new()
var view_resolver:=Views.new()
var head_views:=Views.new()
var head_surface
var interpolate_views:=true
var head_pitch_enabled:=true
var source_count:=20
func _init(path:String="res://mini/projected2d/b_cutout/template.json",initial_preset:String="")->void:
	super._init()
	template_path=path
	spec=Spec.new(path);config=spec.data
	assert(spec.error.is_empty(),spec.error)
	base_config=config.duplicate(true)
	presets=Presets.new(base_config)
	head_surface=Surface.new(config.head_landmarks)
	pouch=false;head_views.cap_enabled=true
	for key in config.neutral_stand:library.poses.stand[key]=config.neutral_stand[key].duplicate()
	if not initial_preset.is_empty():
		var applied:=apply_preset(initial_preset);assert(applied.ok,str(applied))
func render_scale()->float:
	return float(config.display_scale)
func save_bundle()->Dictionary:
	return Bundle.save(self)
func restore_bundle(data:Dictionary)->Dictionary:
	return Bundle.restore(self,data)
func apply_preset(id:String,clamp_limits:bool=false)->Dictionary:
	if not id.is_empty() and not presets.definitions.has(id):
		return {"ok":false,"errors":["Unknown preset: "+id],"warnings":[]}
	return apply_preset_patch(presets.definitions.get(id,{}),id,clamp_limits)
func apply_preset_patch(patch:Dictionary,id:String="custom",clamp_limits:bool=false)->Dictionary:
	var result:=presets.compose(base_config,patch,clamp_limits)
	if not result.ok:return result
	if config.get("face",{}).has("registered"):result.config.face=config.face.duplicate(true)
	config=result.config;head_surface=Surface.new(config.head_landmarks)
	preset_id=id;preset_report=result.duplicate(true);preset_report.erase("config")
	return preset_report
func prepare_pose(pose:Dictionary)->Dictionary:
	reference_pose=pose.duplicate(true)
	profile=library.profiles.explorer.duplicate(true)
	profile.merge(config.profile,true)
	return retarget.pose_for(pose,library.profiles.explorer,profile)
func pose_target_for(goal:String,world_position:Vector3,source_pose:Dictionary={})->Dictionary:
	if not world_position.is_finite():return {"ok":false,"error":"Position must be finite"}
	evaluate()
	var p:Dictionary=reference_pose if source_pose.is_empty() else source_pose
	if not library.validate_pose(p):return {"ok":false,"error":library.error}
	return retarget.authoring_target(goal,world_to_solver(world_position),p,library.profiles.explorer,profile)
func group_for(id:String)->String:
	for pair in [["upper_","upper_arm"],["fore_","forearm"],["hand_","hand"],["thigh_","thigh"],["shin_","shin"],["boot_","boot"],["elbow_","elbow"],["knee_","knee"]]:
		if id.begins_with(pair[0]):return pair[1]
	return id
func evaluate()->Array:
	var input:Array=super.evaluate();var out:Array=[]
	for original in input:
		if original.id in ["hair","pouch"]:continue
		var part:Dictionary=original.duplicate()
		if part.id in ["pelvis","abdomen"]:
			# A clothed hip volume, independent of upper-body twist.
			var world:=Basis(Vector3.UP,deg_to_rad(world_yaw))
			var hip_basis:=Basis(Vector3.UP,deg_to_rad(solver.control.twist*.15))*Basis(Vector3.RIGHT,deg_to_rad(solver.control.lean*.35))
			part.basis=world*hip_basis
			part.center=world*solver.joints.pelvis+root
		var group:=group_for(part.id);var s:Dictionary=config.surface[group]
		if s.has("radii"):part.radii=Library.vec(s.radii)
		if s.has("scale"):part.radii*=Library.vec(s.scale)
		if s.has("offset"):
			var offset_basis:Basis=part.basis if part.id in ["pelvis","abdomen"] else Basis(Vector3.UP,deg_to_rad(world_yaw))
			part.center+=offset_basis*Library.vec(s.offset)
		part.atlas_row_offset=int(s.row)-Assets.TYPES.find(part.kind)
		part.view_resolver=head_views if part.id=="head" else view_resolver
		part.nearest_view=not interpolate_views;part.warp=0.0
		if part.id=="head":
			part.view_surface=head_surface
			var face:=Face.render_data(config,expression,face_parts,overlays)
			if not face.is_empty():
				if face.has("registered"):face.runtime_id=get_instance_id()
				part.face=face
			if head_pitch_enabled:part.pitch_warp=config.head_pitch_warp
		part.center=(part.center-root)*float(config.display_scale)+root
		part.radii*=float(config.display_scale)
		out.append(part)
	return out
