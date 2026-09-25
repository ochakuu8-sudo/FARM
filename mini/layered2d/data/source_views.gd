extends RefCounted
## Authored source order is independent of the eight runtime directions.
## Append rear-quarter as single-5; existing single-4 remains the back.
const REAR = "back_three_quarter_left"
const STANDARD = ["front", "front_three_quarter_left", "left", "back", REAR]
const RUNTIME = ["front", "front_three_quarter_left", "left", REAR, "back", REAR, "left", "front_three_quarter_left", "back", "front"]

static func names(config: Dictionary) -> Array:
	return config.get("source_directions", [])

static func source(config: Dictionary, runtime_view: int) -> int:
	var views := names(config)
	var key: String = RUNTIME[runtime_view]
	return views.find(key)

static func has_rear(config: Dictionary) -> bool:
	return names(config).has(REAR)

static func mirrored(config: Dictionary, runtime_view: int) -> bool:
	return runtime_view in [5, 6, 7]

static func validate(config: Dictionary) -> String:
	var views := names(config)
	if views.size() != 5: return "FIVE_SOURCE_DIRECTIONS_REQUIRED"
	for key in STANDARD:
		if views.count(key) != 1: return "SOURCE_DIRECTION_MISSING: " + key
	if config.get("head_landmarks",[]).size()!=5:return "FIVE_HEAD_LANDMARKS_REQUIRED"
	return ""
