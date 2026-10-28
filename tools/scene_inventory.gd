extends SceneTree
# Usage: godot --headless --path . --script tools/scene_inventory.gd -- <res://scene.tscn> <res://maps/name>
# Writes <prefix>_objects.json and <prefix>_annotated.svg. Reads <prefix>.json and <prefix>.png for the map.

const Lib := preload("res://tools/inventory_lib.gd")
const CLUSTER_PX := 40.0
const MARKER_R := 11.0
const LABEL_FONT := 20
const CHAR_W := 13.0
const LABEL_H := 24.0
const ROW_H := 24.0
const COL_W := 360.0
const FONT := "DejaVu Sans, Arial, Helvetica, sans-serif"
const KIND_COLOR := {
	"player_start": "#00e000",
	"door": "#2f7bff",
	"switch": "#ff9a00",
	"button": "#ff6a00",
	"keypad": "#e02020",
	"container": "#8a3ffc",
	"pickup": "#1faa00",
	"key": "#e6b800",
	"token": "#d4a017",
	"readable": "#00a6a6",
	"puzzle": "#e0209a",
	"interactable": "#6b8e23",
	"seat": "#707070",
	"vehicle": "#505050",
	"carryable": "#a0a0a0",
	"npc": "#a00000",
	"trigger": "#00c8e0",
	"connector": "#00a0ff",
	"volume": "#ffffff",
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: --script tools/scene_inventory.gd -- <res://scene.tscn> <res://maps/name>")
		quit(2)
		return
	# Autoloads and the tree are ready after one frame.
	await process_frame
	_run(args[0], args[1])


func _run(scene_path: String, prefix: String) -> void:
	var level := Lib.load_level(scene_path)
	if level == null:
		printerr("cannot load %s" % scene_path)
		quit(2)
		return
	var map := Lib.load_map(prefix)
	if map.is_empty():
		printerr("cannot read %s.json" % prefix)
		quit(2)
		return
	var objects := Lib.collect(level)
	level.free()
	var json_ok := Lib.write_text(prefix + "_objects.json", JSON.stringify(objects, "\t", true) + "\n")
	var svg_ok := Lib.write_text(prefix + "_annotated.svg", _svg(objects, map, prefix.get_file()))
	var counts := {}
	for o in objects:
		counts[o.kind] = counts.get(o.kind, 0) + 1
	print("objects=%d kinds=%s" % [objects.size(), JSON.stringify(counts, "", true)])
	print("wrote %s_objects.json ok=%s, %s_annotated.svg ok=%s" % [prefix, json_ok, prefix, svg_ok])
	quit(0 if json_ok and svg_ok else 1)


# Annotated SVG: map image, numbered markers, short labels where they fit, legend column.
func _svg(objects: Array, map: Dictionary, name: String) -> String:
	var map_w := int(map.px_width)
	var map_h := int(map.px_height)
	var pts: Array[Vector2] = []
	for o in objects:
		pts.append(Lib.to_px(map, o.x, o.z))
	var placed: Array[Rect2] = []
	var label_of := {}
	# The player start is labeled first so it always keeps its text.
	var order: Array[int] = []
	for i in objects.size():
		if objects[i].kind == "player_start":
			order.append(i)
	for i in objects.size():
		if objects[i].kind != "player_start":
			order.append(i)
	for i in order:
		var text: String = "START" if objects[i].kind == "player_start" else _short(_label_name(objects[i]))
		var box := Rect2(pts[i] + Vector2(MARKER_R + 4.0, -LABEL_H * 0.5), Vector2(text.length() * CHAR_W + 6.0, LABEL_H))
		var ok := box.end.x <= map_w and box.position.y >= 0.0 and box.end.y <= map_h
		if objects[i].kind != "player_start" and _near_other(pts, i):
			ok = false
		if ok:
			for j in pts.size():
				if j != i and box.grow(MARKER_R).has_point(pts[j]):
					ok = false
					break
		if ok:
			for r in placed:
				if r.intersects(box):
					ok = false
					break
		if ok:
			placed.append(box)
			label_of[i] = text
	var legend_rows: Array[String] = []
	for i in objects.size():
		if not label_of.has(i):
			legend_rows.append("%d  %s (%s)" % [i + 1, _short(_label_name(objects[i]), 26), objects[i].kind])
	var kind_rows: Array[String] = []
	var kinds := {}
	for o in objects:
		kinds[o.kind] = kinds.get(o.kind, 0) + 1
	var kind_names := kinds.keys()
	kind_names.sort()
	for k in kind_names:
		kind_rows.append(k)
	var total_rows := kind_rows.size() + 2 + legend_rows.size() + 1
	var cols := maxi(1, ceili(total_rows * ROW_H / float(map_h)))
	var svg_w := map_w + int(cols * COL_W) + 20
	var s := PackedStringArray()
	s.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"%s\">" % [svg_w, map_h, svg_w, map_h, FONT])
	s.append("<rect width=\"%d\" height=\"%d\" fill=\"#ffffff\"/>" % [svg_w, map_h])
	s.append("<image href=\"%s.png\" xlink:href=\"%s.png\" x=\"0\" y=\"0\" width=\"%d\" height=\"%d\"/>" % [name, name, map_w, map_h])
	for i in objects.size():
		var o: Dictionary = objects[i]
		var p := pts[i]
		var color: String = KIND_COLOR.get(o.kind, "#ff00ff")
		var r := MARKER_R + (5.0 if o.kind == "player_start" else 0.0)
		s.append("<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" fill=\"%s\" stroke=\"#000000\" stroke-width=\"2\"/>" % [p.x, p.y, r, color])
		if o.kind != "player_start":
			var ink := "#000000" if o.kind in ["volume", "key", "token", "trigger", "carryable"] else "#ffffff"
			s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"12\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"%s\">%d</text>" % [p.x, p.y + 4.2, ink, i + 1])
	for i in label_of:
		var p := pts[i]
		var tx := p.x + MARKER_R + 7.0 + (5.0 if objects[i].kind == "player_start" else 0.0)
		var ty := p.y + 7.0
		var txt := Lib.xml_escape(label_of[i])
		s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"%d\" font-weight=\"bold\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"5\" stroke-linejoin=\"round\">%s</text>" % [tx, ty, LABEL_FONT, txt])
		s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"%d\" font-weight=\"bold\" fill=\"#000000\">%s</text>" % [tx, ty, LABEL_FONT, txt])
	# Legend panel on the right.
	s.append("<rect x=\"%d\" y=\"0\" width=\"%d\" height=\"%d\" fill=\"#f4f4f4\"/>" % [map_w, svg_w - map_w, map_h])
	var rows: Array = []
	rows.append(["h", "Legend: %s (%d objects)" % [name, objects.size()], ""])
	for k in kind_rows:
		rows.append(["k", "%s  %d" % [k, kinds[k]], KIND_COLOR.get(k, "#ff00ff")])
	rows.append(["h", "Numbers with no label", ""])
	for line in legend_rows:
		rows.append(["t", line, ""])
	for n in rows.size():
		var col := n / int(maxf(1.0, floorf(map_h / ROW_H) - 1.0))
		var row := n % int(maxf(1.0, floorf(map_h / ROW_H) - 1.0))
		var x := map_w + 14.0 + col * COL_W
		var y := 30.0 + row * ROW_H
		var kind: String = rows[n][0]
		var text := Lib.xml_escape(rows[n][1])
		if kind == "k":
			s.append("<circle cx=\"%.1f\" cy=\"%.1f\" r=\"8\" fill=\"%s\" stroke=\"#000000\" stroke-width=\"1.5\"/>" % [x + 8.0, y - 6.0, rows[n][2]])
			s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"18\" fill=\"#000000\">%s</text>" % [x + 24.0, y, text])
		else:
			var weight := "bold" if kind == "h" else "normal"
			s.append("<text x=\"%.1f\" y=\"%.1f\" font-size=\"%d\" font-weight=\"%s\" fill=\"#000000\">%s</text>" % [x, y, 18, weight, text])
	s.append("</svg>")
	return "\n".join(s) + "\n"


func _near_other(pts: Array[Vector2], i: int) -> bool:
	for j in pts.size():
		if j != i and pts[i].distance_to(pts[j]) < CLUSTER_PX:
			return true
	return false


func _short(name: String, limit := 22) -> String:
	return name if name.length() <= limit else name.substr(0, limit - 1) + "~"


# Display name: a node that kept its engine class name (for example AnimatableBody3D) is shown with its parent's name.
func _label_name(o: Dictionary) -> String:
	if ClassDB.class_exists(o.name) or o.name.begins_with("@"):
		return "%s.%s" % [String(o.parent_path).get_file(), o.name]
	return o.name
