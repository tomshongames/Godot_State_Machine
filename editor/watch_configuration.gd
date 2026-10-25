@tool
extends RefCounted

const ENTRY := preload("res://addons/state_machine/runtime/watch_entry.gd")
const MAX_WATCHES := 32

static func valid(entry: Resource) -> bool:
	return entry is ENTRY

static func definition(entry: Resource) -> Dictionary:
	# Keep one definition per authored slot. Filtering malformed entries would
	# shift runtime value indexes onto the wrong editor Watch rows.
	if not valid(entry):
		return {"name":"Invalid Watch", "mode":0, "target":"", "property":"", "enabled":false}
	return {"name":String(entry.display_name).left(256), "mode":int(entry.target_mode), "target":String(entry.target_path), "property":String(entry.property_path).left(256), "enabled":bool(entry.enabled)}

static func definitions(entries: Array[Resource]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries.slice(0, MAX_WATCHES): result.append(definition(entry))
	return result
