extends SceneTree
# Usage: godot --headless --path . --script tools/volume_report.gd -- <res://scene.tscn> <res://maps/name> [<res://maps/map_name>]
# Prints the volume report and writes <prefix>_volumes.svg. The optional third argument names the map files when they differ from the prefix.

const Lib := preload("res://tools/inventory_lib.gd")
const MIN_SIDE := 1.6
const MIN_HEIGHT := 1.8
const FONT := "DejaVu Sans, Arial, Helvetica, sans-serif"
const COLORS := ["#ff3b30", "#34c759", "#ffcc00", "#af52de", "#00c7be", "#ff9500", "#ffffff", "#5ac8fa"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: --script tools/volume_report.gd -- <res://scene.tscn> <res://maps/name> [<res://maps/map_name>]")
		quit(2)
		return
	# Autoloads and the tree are ready after one frame.
	await process_frame
	_run(args[0], args[1], args[2] if args.size() > 2 else args[1])


func _run(scene_path: String, prefix: String, map_prefix: String) -> void:
	var level := Lib.load_level(scene_path)
	if level == null:
		printerr("cannot load %s" % scene_path)
		quit(2)
		return
	var map := Lib.load_map(map_prefix)
	if map.is_empty():
		printerr("cannot read %s.json" % map_prefix)
		quit(2)
		return
	var volumes := []
	for node in Lib.find_volumes(level):
		var box := Lib.volume_box(node)
		box["zone"] = String(node.get("zone"))
		box["puzzle"] = String(node.get("puzzle"))
		box["name"] = String(node.name)
		volumes.append(box)
	var things := []
	var start = null
	for o in Lib.collect(level):
		if o.kind == "player_start":
			start = Vector3(o.x, o.y, o.z)
		elif o.kind != "volume":
			things.append(o)
	level.free()
	var warnings: Array[String] = []
	print("VOLUME REPORT %s" % scene_path)
	print("Inside means the object's origin lies within the box on all three axes. Boxes with a rotated transform are reported as axis-aligned bounds.")
	print("volumes: %d, interactables considered: %d" % [volumes.size(), things.size()])
	var inside_any := {}
	for i in volumes.size():
		var v: Dictionary = volumes[i]
		print("")
		print("[%d] node=%s zone=\"%s\" puzzle=\"%s\"" % [i + 1, v.name, v.zone, v.puzzle])
		if not v.has_box:
			print("    no BoxShape3D child, no box")
			warnings.append("volume %d (%s) has no BoxShape3D child" % [i + 1, v.name])
			continue
		print("    box min (%.2f, %.2f, %.2f) max (%.2f, %.2f, %.2f)%s" % [v.min.x, v.min.y, v.min.z, v.max.x, v.max.y, v.max.z, "  (rotated, axis-aligned bounds)" if v.rotated else ""])
		var names := []
		for o in things:
			if _inside(v, Vector3(o.x, o.y, o.z)):
				names.append("%s (%s)" % [o.name, o.kind])
				inside_any["%s|%s" % [o.parent_path, o.name]] = true
		print("    interactables inside: %d" % names.size())
		for n in names.slice(0, 40):
			print("      %s" % n)
		if names.size() > 40:
			print("      ... and %d more" % (names.size() - 40))
		if String(v.zone).strip_edges() == "":
			warnings.append("volume %d (%s) has an empty zone" % [i + 1, v.name])
		var size: Vector3 = v.max - v.min
		if size.x < MIN_SIDE:
			warnings.append("volume %d (%s) is thin in x: %.2f m, below %.1f m" % [i + 1, v.name, size.x, MIN_SIDE])
		if size.z < MIN_SIDE:
			warnings.append("volume %d (%s) is thin in z: %.2f m, below %.1f m" % [i + 1, v.name, size.z, MIN_SIDE])
		if size.y < MIN_HEIGHT:
			warnings.append("volume %d (%s) is low: height %.2f m, below %.1f m (the player's capsule would not fit)" % [i + 1, v.name, size.y, MIN_HEIGHT])
	for i in volumes.size():
		for j in range(i + 1, volumes.size()):
			var a: Dictionary = volumes[i]
			var b: Dictionary = volumes[j]
			if _norm(a) == _norm(b) and (a.zone != b.zone or a.puzzle != b.puzzle):
				warnings.append("volumes %d and %d differ only by case or spacing (likely a typo): \"%s\" / \"%s\" vs \"%s\" / \"%s\"" % [i + 1, j + 1, a.zone, a.puzzle, b.zone, b.puzzle])
			if a.has_box and b.has_box:
				var lo: Vector3 = a.min.max(b.min)
				var hi: Vector3 = a.max.min(b.max)
				var ov := hi - lo
				if ov.x > 0.0 and ov.y > 0.0 and ov.z > 0.0:
					warnings.append("volumes %d and %d overlap by %.2f x %.2f x %.2f m (%.2f m3)" % [i + 1, j + 1, ov.x, ov.y, ov.z, ov.x * ov.y * ov.z])
	print("")
	if start == null:
		print("player start: not found in the scene")
	else:
		var holders := []
		for i in volumes.size():
			if volumes[i].has_box and _inside(volumes[i], start):
				holders.append("%d (%s / %s)" % [i + 1, volumes[i].zone, volumes[i].puzzle])
		print("player start (%.2f, %.2f, %.2f) volume: %s" % [start.x, start.y, start.z, ", ".join(holders) if not holders.is_empty() else "none"])
	var outside := []
	for o in things:
		if not inside_any.has("%s|%s" % [o.parent_path, o.name]):
			outside.append(o)
	print("interactables in no volume: %d of %d" % [outside.size(), things.size()])
	for o in outside.slice(0, 60):
		print("  %s (%s) at (%.2f, %.2f, %.2f)" % [o.name, o.kind, o.x, o.y, o.z])
	if outside.size() > 60:
		print("  ... and %d more" % (outside.size() - 60))
	print("")
	print("warnings: %d" % warnings.size())
	for w in warnings:
		print("WARNING: %s" % w)
	var svg_ok := Lib.write_text(prefix + "_volumes.svg", _svg(volumes, start, map, map_prefix, prefix))
	print("wrote %s_volumes.svg ok=%s" % [prefix, svg_ok])
	quit(0)


func _inside(v: Dictionary, p: Vector3) -> bool:
	return p.x >= v.min.x and p.x <= v.max.x and p.y >= v.min.y and p.y <= v.max.y and p.z >= v.min.z and p.z <= v.max.z


# Zone and puzzle with case and all whitespace removed, for the typo check.
func _norm(v: Dictionary) -> String:
	var z := String(v.zone).to_lower().replace(" ", "").replace("\t", "")
	var p := String(v.puzzle).to_lower().replace(" ", "").replace("\t", "")
	return z + "|" + p


# Image path relative to the SVG: same folder, or a sibling folder under res://.
func _image_href(map_prefix: String, prefix: String) -> String:
	var file := map_prefix.get_file() + ".png"
	if map_prefix.get_base_dir() == prefix.get_base_dir():
		return file
	return "../%s/%s" % [map_prefix.get_base_dir().get_file(), file]


func _svg(volumes: Array, start, map: Dictionary, map_prefix: String, prefix: String) -> String:
	var map_w := int(map.px_width)
	var map_h := int(map.px_height)
	var href := _image_href(map_prefix, prefix)
	var s := PackedStringArray()
	s.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"%s\">" % [map_w, map_h, map_w, map_h, FONT])
	s.append("<image href=\"%s\" xlink:href=\"%s\" x=\"0\" y=\"0\" width=\"%d\" height=\"%d\"/>" % [href, href, map_w, map_h])
	for i in volumes.size():
		var v: Dictionary = volumes[i]
		if not v.has_box:
			continue
		var a := Lib.to_px(map, v.min.x, v.min.z)
		var b := Lib.to_px(map, v.max.x, v.max.z)
		var color: String = COLORS[i % COLORS.size()]
		s.append("<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" fill=\"%s\" fill-opacity=\"0.18\" stroke=\"%s\" stroke-width=\"4\"/>" % [a.x, a.y, b.x - a.x, b.y - a.y, color, color])
		var label := Lib.xml_escape("%d %s" % [i + 1, v.zone] + (" / " + v.puzzle if v.puzzle != "" else ""))
		s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"22\" font-weight=\"bold\" fill=\"none\" stroke=\"#000000\" stroke-width=\"5\" stroke-linejoin=\"round\">%s</text>" % [a.x + 8.0, a.y + 26.0, label])
		s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"22\" font-weight=\"bold\" fill=\"%s\">%s</text>" % [a.x + 8.0, a.y + 26.0, color, label])
	if start != null:
		var p := Lib.to_px(map, start.x, start.z)
		s.append("<circle cx=\"%.1f\" cy=\"%.1f\" r=\"14\" fill=\"#00e000\" stroke=\"#000000\" stroke-width=\"2\"/>" % [p.x, p.y])
		s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"20\" font-weight=\"bold\" fill=\"#00e000\" stroke=\"#000000\" stroke-width=\"0.8\">START</text>" % [p.x + 20.0, p.y + 7.0])
	if volumes.is_empty():
		s.append("<text x=\"20\" y=\"36\" font-size=\"26\" font-weight=\"bold\" fill=\"#ffffff\">no telemetry volumes in this scene</text>")
	s.append("</svg>")
	return "\n".join(s) + "\n"
