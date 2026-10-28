extends SceneTree
# Usage: godot --path . --script tools/map_export.gd -- <res://scene.tscn> <out_prefix> [y_cutoff]

const MAX_SIDE := 2048
const DEFAULT_CUTOFF := 2.4
const PAD := 1.0
const CAMERA_HEIGHT := 200.0
# Node classes removed from the in-memory copy so only level geometry is drawn (no HUD, lights, cameras, sounds).
const HEIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float cutoff = 2.4;
varying float h;
void vertex() { h = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	float k = clamp(h / cutoff, 0.0, 1.0);
	ALBEDO = mix(vec3(0.10, 0.16, 0.30), vec3(0.97, 0.93, 0.78), pow(k, 0.7));
}
"""
const DROP_CLASSES := ["CanvasItem", "CanvasLayer", "Viewport", "Light3D", "WorldEnvironment", "FogVolume", "ReflectionProbe", "VoxelGI", "LightmapGI", "GPUParticles3D", "CPUParticles3D", "Decal", "Camera3D", "Label3D", "Sprite3D", "AudioStreamPlayer3D", "OmniLight3D", "SpotLight3D", "DirectionalLight3D"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: --script tools/map_export.gd -- <res://scene.tscn> <out_prefix> [y_cutoff]")
		quit(2)
		return
	var cutoff := DEFAULT_CUTOFF
	if args.size() > 2:
		cutoff = float(args[2])
	# Autoloads and the tree are ready after one frame.
	await process_frame
	await _run(args[0], args[1], cutoff)


func _run(scene_path: String, prefix: String, cutoff: float) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("cannot load %s" % scene_path)
		quit(2)
		return
	var level := packed.instantiate()
	# Scripts are cut from the in-memory copy and nothing ticks, so the level cannot run game code or touch the disk.
	_strip_scripts(level)
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var view := SubViewport.new()
	view.size = Vector2i(MAX_SIDE, MAX_SIDE)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.own_world_3d = true
	root.add_child(view)
	view.add_child(level)
	var start := _take_player_start(level)
	_drop_non_geometry(level)
	_hide_above(level, cutoff)
	var box := _visible_bounds(level)
	if box.size == Vector3.ZERO:
		printerr("no geometry below the cutoff")
		quit(2)
		return
	var min_x := floorf(box.position.x - PAD)
	var max_x := ceilf(box.end.x + PAD)
	var min_z := floorf(box.position.z - PAD)
	var max_z := ceilf(box.end.z + PAD)
	var w := max_x - min_x
	var h := max_z - min_z
	var scale_px := float(MAX_SIDE) / maxf(w, h)
	var px_w := int(roundf(w * scale_px))
	var px_h := int(roundf(h * scale_px))
	view.size = Vector2i(px_w, px_h)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = h
	cam.near = 0.1
	cam.far = CAMERA_HEIGHT * 2.0
	# Right is +x, picture up is -z, so z grows downward. Looks straight down.
	cam.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3((min_x + max_x) * 0.5, CAMERA_HEIGHT, (min_z + max_z) * 0.5))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	cam.environment = env
	view.add_child(cam)
	cam.current = true
	_apply_height_look(level, cutoff)
	for _i in 6:
		await process_frame
	var image := view.get_texture().get_image()
	var png_path := prefix + ".png"
	DirAccess.make_dir_recursive_absolute(png_path.get_base_dir())
	var err := image.save_png(png_path)
	if err != OK:
		printerr("could not save %s: %s" % [png_path, error_string(err)])
		quit(1)
		return
	var info := {
		"scene": scene_path,
		"world_min_x": min_x,
		"world_max_x": max_x,
		"world_min_z": min_z,
		"world_max_z": max_z,
		"px_width": px_w,
		"px_height": px_h,
		"y_cutoff": cutoff,
		"convention": "px = (x - world_min_x) / (world_max_x - world_min_x) * px_width; py = (z - world_min_z) / (world_max_z - world_min_z) * px_height; z grows downward in the picture; y is height and is not drawn",
	}
	var f := FileAccess.open(prefix + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t") + "\n")
	f.close()
	if start.is_finite():
		var sx: float = (start.x - min_x) / w * px_w
		var sy: float = (start.z - min_z) / h * px_h
		print("player_start x=%s z=%s -> px=%.1f py=%.1f (of %d x %d)" % [start.x, start.z, sx, sy, px_w, px_h])
	print("wrote %s.png and %s.json (%d x %d px)" % [prefix, prefix, px_w, px_h])
	quit(0)


func _strip_scripts(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_strip_scripts(child)


# Removes the player from the in-memory copy and returns where it started (NAN if none).
func _take_player_start(level: Node) -> Vector3:
	var player := level.get_node_or_null("Player") as Node3D
	if player == null:
		return Vector3(NAN, NAN, NAN)
	var at := player.global_position
	player.get_parent().remove_child(player)
	player.free()
	return at


func _drop_non_geometry(level: Node) -> void:
	var doomed: Array[Node] = []
	_collect(level, doomed)
	for node in doomed:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
			node.free()


func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		var drop := false
		for cls in DROP_CLASSES:
			if child.is_class(cls):
				drop = true
				break
		if drop:
			out.append(child)
		else:
			_collect(child, out)


# Every surface is drawn unlit and coloured by its world height: floors dark, wall tops and tall things light.
func _apply_height_look(level: Node, cutoff: float) -> void:
	var shader := Shader.new()
	shader.code = HEIGHT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("cutoff", cutoff)
	for node in level.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).material_override = mat


func _world_box(item: GeometryInstance3D) -> AABB:
	return item.global_transform * item.get_aabb()


# Hide whole-object geometry that starts at or above the cutoff (ceilings, roofs).
func _hide_above(level: Node, cutoff: float) -> void:
	for node in level.find_children("*", "GeometryInstance3D", true, false):
		var item := node as GeometryInstance3D
		var box := _world_box(item)
		if box.position.y >= cutoff:
			item.visible = false


func _visible_bounds(level: Node) -> AABB:
	var have := false
	var total := AABB()
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if not item.visible or item.mesh == null or not item.is_visible_in_tree():
			continue
		var box := _world_box(item)
		if have:
			total = total.merge(box)
		else:
			total = box
			have = true
	return total
