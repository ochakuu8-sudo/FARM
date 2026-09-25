extends RefCounted
## One-time material substitution. No rig, vertex or animation changes.
const MANIFEST="res://character_assets/production/shoulder_repair/manifest.json"
static var entries:Dictionary={}
static func directory(source:int,paths:Dictionary)->String:
	if entries.is_empty() and FileAccess.file_exists(MANIFEST):
		var data=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if data is Dictionary:entries=data
	var key:String=str(paths.get("0","")).get_base_dir().get_file() if not paths.is_empty() else "source_"+str(source)
	return str(entries.get(key,""))
