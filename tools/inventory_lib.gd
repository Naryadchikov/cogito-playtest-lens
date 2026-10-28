extends RefCounted
# Shared by tools/scene_inventory.gd and tools/volume_report.gd. Reads a scene, never saves it.

const VOLUME_CLASS := "PlaytestLensTelemetryVolume"
# Script chain entry (global class name, else file name) to kind. First hit while walking from the most derived script wins.
const KIND_BY_SCRIPT := {
	"PlaytestLensTelemetryVolume": "volume",
	"CogitoDoor": "door",
	"CogitoSwitch": "switch",
	"CogitoButton": "button",
	"CogitoKeypad": "keypad",
	"CogitoContainer": "container",
	"CogitoVehicle": "vehicle",
	"CogitoSittable": "seat",
	"CogitoSnapSlot": "puzzle",
	"CogitoPressureplate": "puzzle",
	"cogito_turnwheel.gd": "puzzle",
	"CogitoStaticInteractable": "interactable",
	"cogito_vendor.gd": "interactable",
	"CogitoNPC": "npc",
	"CogitoObject": "object",
	"CogitoCutsceneTrigger": "trigger",
	"scene_transition_zone.gd": "trigger",
	"cogito_spawnzone.gd": "trigger",
	"Ladder": "trigger",
}
const PLAYER_CLASSES := ["CogitoPlayerAdvanced", "CogitoPlayerSimple", "CogitoPlayer"]


# Instantiates the scene without adding it to the tree, so no game script runs and nothing can write to disk.
static func load_level(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


# Script chain of an object: global class names (or file names), most derived first.
static func script_chain(node: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var script := node.get_script() as Script
	while script != null:
		var global_name := script.get_global_name()
		out.append(String(global_name) if global_name != &"" else script.resource_path.get_file())
		script = script.get_base_script()
	return out


# Global transform of a Node3D in a level that is not in the tree.
static func world_transform(node: Node3D) -> Transform3D:
	var t := node.transform
	if node.top_level:
		return t
	var parent := node.get_parent()
	while parent != null:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
			if (parent as Node3D).top_level:
				break
		parent = parent.get_parent()
	return t


static func _path_in_scene(level: Node, node: Node) -> String:
	var rel := str(level.get_path_to(node))
	if rel == ".":
		return String(level.name)
	return "%s/%s" % [level.name, rel]


static func _has_class(chain: PackedStringArray, cls: String) -> bool:
	return chain.has(cls)


# Child interaction components of an object, as script chains.
static func _components(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		var chain := script_chain(child)
		if _has_class(chain, "InteractionComponent"):
			out.append({"node": child, "chain": chain})
	return out


# Kind and detail of a CogitoObject from its interaction components.
static func _object_kind(node: Node) -> Dictionary:
	var comps := _components(node)
	if comps.is_empty():
		return {"kind": "", "detail": ""}
	for c in comps:
		if _has_class(c.chain, "PickupComponent"):
			var slot = c.node.get("slot_data")
			var item = null
			if slot != null:
				item = slot.get("inventory_item")
			if item != null:
				var item_chain := script_chain(item)
				var item_name := String(item.get("name"))
				if _has_class(item_chain, "KeyItemPD"):
					return {"kind": "key", "detail": item_name}
				if _has_class(item_chain, "CurrencyItemPD"):
					return {"kind": "token", "detail": item_name}
				return {"kind": "pickup", "detail": item_name}
			return {"kind": "pickup", "detail": ""}
	for c in comps:
		if _has_class(c.chain, "ReadableComponent"):
			return {"kind": "readable", "detail": ""}
	for c in comps:
		if not _has_class(c.chain, "CogitoCarryableComponent"):
			return {"kind": "interactable", "detail": ""}
	return {"kind": "carryable", "detail": ""}


# Kind of a node, or "" when it is not an inventory entry.
static func classify(node: Node) -> Dictionary:
	var chain := script_chain(node)
	for entry in chain:
		if KIND_BY_SCRIPT.has(entry):
			var kind: String = KIND_BY_SCRIPT[entry]
			if kind == "object":
				return _object_kind(node)
			if kind == "trigger" and entry == "scene_transition_zone.gd":
				return {"kind": kind, "detail": "scene_transition_zone to " + String(node.get("target_connector"))}
			if kind == "trigger":
				return {"kind": kind, "detail": entry}
			return {"kind": kind, "detail": ""}
	# Quest updaters count only as zones (Area3D). The Node3D ones sit on objects and would duplicate them.
	if chain.has("CogitoQuestUpdater") and node is Area3D:
		return {"kind": "trigger", "detail": "CogitoQuestUpdater"}
	return {"kind": "", "detail": ""}


static func _is_player(node: Node) -> bool:
	for entry in script_chain(node):
		if PLAYER_CLASSES.has(entry):
			return true
	return false


static func _entry(level: Node, node: Node, kind: String, detail: String) -> Dictionary:
	var chain := script_chain(node)
	var script := node.get_script() as Script
	var at := world_transform(node as Node3D).origin
	return {
		"name": String(node.name),
		"class": chain[0] if chain.size() > 0 else node.get_class(),
		"script": script.resource_path if script != null else null,
		"x": snappedf(at.x, 0.01),
		"y": snappedf(at.y, 0.01),
		"z": snappedf(at.z, 0.01),
		"parent_path": _path_in_scene(level, node.get_parent()) if node.get_parent() != null else "",
		"kind": kind,
		"detail": detail,
	}


# Every inventory entry of a level, sorted by name then parent_path. Adds the player start and scene connectors.
static func collect(level: Node) -> Array:
	var out := []
	_walk(level, level, out)
	out.sort_custom(func(a, b): return a.name < b.name or (a.name == b.name and a.parent_path < b.parent_path))
	return out


static func _walk(level: Node, node: Node, out: Array) -> void:
	if _is_player(node):
		if node is Node3D:
			out.append(_entry(level, node, "player_start", ""))
		# The player's own HUD, camera and interaction nodes are not level content.
		return
	var chain := script_chain(node)
	if node is Node3D:
		var info := classify(node)
		if info.kind != "":
			out.append(_entry(level, node, info.kind, info.detail))
	if chain.has("cogito_scene.gd"):
		var connectors = node.get("connectors")
		if connectors != null:
			for c in connectors:
				if c is Node3D:
					out.append(_entry(level, c, "connector", ""))
	for child in node.get_children():
		_walk(level, child, out)


# Every PlaytestLensTelemetryVolume node of a level.
static func find_volumes(node: Node) -> Array:
	var out := []
	if script_chain(node).has(VOLUME_CLASS) and node is Node3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(find_volumes(child))
	return out


# World-space box of a volume from its BoxShape3D children: {has_box, min, max, rotated}.
# A rotated transform gives the axis-aligned bounds of the rotated box. Non-box shapes are ignored.
static func volume_box(volume: Node3D) -> Dictionary:
	var has_box := false
	var rotated := false
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	for child in volume.get_children():
		if not (child is CollisionShape3D):
			continue
		var box := (child as CollisionShape3D).shape as BoxShape3D
		if box == null:
			continue
		var t := world_transform(child as Node3D)
		for row in [t.basis.x, t.basis.y, t.basis.z]:
			var nonzero := 0
			for k in 3:
				if absf(row[k]) > 0.001:
					nonzero += 1
			if nonzero != 1:
				rotated = true
		var half := box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner := t * Vector3(half.x * sx, half.y * sy, half.z * sz)
					if not has_box:
						lo = corner
						hi = corner
						has_box = true
					else:
						lo = lo.min(corner)
						hi = hi.max(corner)
	return {"has_box": has_box, "min": lo, "max": hi, "rotated": rotated}


# Map description from <prefix>.json. Returns an empty dictionary on failure.
static func load_map(prefix: String) -> Dictionary:
	var file := FileAccess.open(prefix + ".json", FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}


# World (x, z) to map pixel, using the map JSON only.
static func to_px(map: Dictionary, x: float, z: float) -> Vector2:
	var px := (x - float(map.world_min_x)) / (float(map.world_max_x) - float(map.world_min_x)) * float(map.px_width)
	var py := (z - float(map.world_min_z)) / (float(map.world_max_z) - float(map.world_min_z)) * float(map.px_height)
	return Vector2(px, py)


static func xml_escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


# Writes text to a res:// or user:// path. Returns false on failure.
static func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true
