extends Control
## Splitscreen match. Every local player gets a SubViewport (own 3D world, the game's native
## 960x540) holding a full copy of the multiplayer scene; player 1's copy is the host. Input is
## routed per device: keyboard & mouse to its player, each controller to its player.

const MP_MAIN := "res://multiplayer/scenes/mp_main.tscn"
const USER_INSTANCE := "res://multiplayer/instances/user_instance_main_1.tscn"
const FONT_MAIN := "res://fonts/fake receipt.otf"
const VIEW_SIZE := Vector2i(960, 540)
const GAP := 4.0
## Materials the match edits at runtime; each copy gets its own so one player's screen never shows up in another's.
const ISOLATED_MATERIALS := [
	"res://multiplayer/materials/mp_mat_jammer screen local.tres",
	"res://multiplayer/materials/mp_burner phone screen cracked.tres",
	"res://multiplayer/materials/mp_burner phone screen normal.tres",
]

var views : Array = []
var font : Font
var loading_label : Label
var started := false
var _prev_scale_mode := Window.CONTENT_SCALE_MODE_VIEWPORT
var _isolation_caches : Array = []
var _kbm_index := -1
var _quitting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load(FONT_MAIN)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if !SplitMod.active:
		get_tree().change_scene_to_file.call_deferred(SplitMod.LOBBY_SCENE)
		return
	# Closing the window goes through shutdown() too (see _notification).
	get_tree().auto_accept_quit = false
	# Draw at the window's real resolution; each view renders at the game's own 960x540.
	var win := get_window()
	_prev_scale_mode = win.content_scale_mode
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	loading_label = _make_label("LOADING", 28)
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(loading_label)

	for c in SplitMod.contexts:
		if c.device == SplitMod.DEVICE_KBM:
			_kbm_index = c.index
	var scenes := []
	for c in SplitMod.contexts:
		loading_label.text = "LOADING  %d / %d" % [c.index + 1, SplitMod.contexts.size()]
		await get_tree().process_frame
		await get_tree().process_frame
		if !is_inside_tree() or SplitMod.ending:
			return
		# A private copy of the scene file, so each match owns its sub-resources (meshes, materials, animations).
		var packed : PackedScene = ResourceLoader.load(MP_MAIN, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if packed == null:
			SplitMod.end_session("COULD NOT LOAD THE MULTIPLAYER SCENE")
			return
		scenes.append(packed)

	for c in SplitMod.contexts:
		_isolation_caches.append({})
		_add_view(c, scenes[c.index])
	loading_label.queue_free()
	get_tree().node_added.connect(_on_node_added)
	get_viewport().size_changed.connect(_layout)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	started = true
	_layout()
	# Tags that had to go on top of a view (no letterbox room) fade out after a few seconds.
	for v in views:
		if v.tag_overlaps_view:
			var tween := create_tween()
			tween.tween_interval(6.0)
			tween.tween_property(v.tag, "modulate:a", 0.0, 1.5)


func _exit_tree() -> void:
	# The match copies are freed right after this; nothing of theirs runs in between.
	if SplitMod.active:
		SplitMod.session_closed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and SplitMod.active:
		_quitting = true
		SplitMod.end_session("", true)


## Ends the match without crashing Godot 4.1, which has two traps here:
## - a control that still has focus or hover (a pause-menu button that was just pressed) queues a
##   redraw while it leaves the tree, and that queued call then reads the freed control;
## - the match's coroutines call get_tree().create_timer(), which crashes on a node outside the tree,
##   so the copies must be freed inside the tree, never detached first.
func shutdown(quitting: bool) -> void:
	_quitting = _quitting or quitting
	started = false
	for v in views:
		v.vp.gui_disable_input = true
		_release_gui(v.vp)
		for child in v.vp.get_children():
			child.process_mode = Node.PROCESS_MODE_DISABLED
	get_window().content_scale_mode = _prev_scale_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Let the redraws queued above run while every control still exists.
	await _frames(2)
	# Anything that took focus back meanwhile is released again; those redraws are queued before the
	# scene change below, so they also run before the copies are freed.
	for v in views:
		_release_gui(v.vp)
		v.screen.texture = null
	if _quitting:
		get_tree().quit()
	else:
		get_tree().change_scene_to_file(SplitMod.LOBBY_SCENE)

func _release_gui(vp: SubViewport) -> void:
	vp.gui_release_focus()
	vp.notification(NOTIFICATION_VP_MOUSE_EXIT)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate = false
	return l


func _add_view(c, packed: PackedScene) -> void:
	var root_vp := get_tree().root
	var vp := SubViewport.new()
	vp.name = "player_%d_view" % (c.index + 1)
	vp.size = VIEW_SIZE
	vp.own_world_3d = true
	vp.handle_input_locally = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Only player 1's copy is heard; the others play the same sounds in sync.
	vp.audio_listener_enable_2d = c.primary
	vp.audio_listener_enable_3d = c.primary
	# Same rendering settings as the game window.
	vp.msaa_2d = root_vp.msaa_2d
	vp.msaa_3d = root_vp.msaa_3d
	vp.screen_space_aa = root_vp.screen_space_aa
	vp.use_taa = root_vp.use_taa
	vp.use_debanding = root_vp.use_debanding
	vp.use_occlusion_culling = root_vp.use_occlusion_culling
	vp.mesh_lod_threshold = root_vp.mesh_lod_threshold
	vp.scaling_3d_mode = root_vp.scaling_3d_mode
	vp.scaling_3d_scale = root_vp.scaling_3d_scale
	vp.fsr_sharpness = root_vp.fsr_sharpness
	vp.texture_mipmap_bias = root_vp.texture_mipmap_bias
	vp.positional_shadow_atlas_size = root_vp.positional_shadow_atlas_size
	vp.positional_shadow_atlas_16_bits = root_vp.positional_shadow_atlas_16_bits
	for q in 4:
		vp.set_positional_shadow_atlas_quadrant_subdiv(q, root_vp.get_positional_shadow_atlas_quadrant_subdiv(q))
	vp.canvas_item_default_texture_filter = root_vp.canvas_item_default_texture_filter
	vp.canvas_item_default_texture_repeat = root_vp.canvas_item_default_texture_repeat
	vp.snap_2d_transforms_to_pixel = root_vp.snap_2d_transforms_to_pixel
	vp.snap_2d_vertices_to_pixel = root_vp.snap_2d_vertices_to_pixel
	vp.set_meta(&"split_ctx", c.index)
	add_child(vp)

	var screen := TextureRect.new()
	screen.texture = vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	var tag := _make_label("%s  -  %s" % [c.name, SplitMod.device_label(c.device)], 18)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(tag)
	var warning := _make_label("CONTROLLER DISCONNECTED\nRECONNECT IT TO KEEP PLAYING", 22)
	warning.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	warning.visible = c.device != SplitMod.DEVICE_KBM and !(c.device in Input.get_connected_joypads())
	add_child(warning)

	var instance := packed.instantiate()
	_isolate_resources(instance, _isolation_caches[c.index])
	vp.add_child(instance)
	views.append({"ctx": c, "vp": vp, "screen": screen, "tag": tag, "tag_overlaps_view": false, "warning": warning})


# ---------------------------------------------------------------- layout

func _layout() -> void:
	if !started:
		return
	var area := get_viewport_rect().size
	var n := views.size()
	var cols := 2
	var rows := 1 if n <= 2 else 2
	var cell := Vector2(area.x / cols, area.y / rows)
	for i in n:
		var v : Dictionary = views[i]
		var cell_pos := Vector2((i % cols) * cell.x, (i / cols) * cell.y)
		var avail := cell - Vector2(GAP, GAP)
		var s := minf(avail.x / VIEW_SIZE.x, avail.y / VIEW_SIZE.y)
		var size := Vector2(VIEW_SIZE) * s
		var pos := cell_pos + (cell - size) / 2.0
		if n == 3 and i == 2:
			pos.x = (area.x - size.x) / 2.0
		var r := Rect2(pos.round(), size.round())
		v.screen.position = r.position
		v.screen.size = r.size
		v.ctx.view_rect = r
		var tag : Label = v.tag
		var tag_size := maxi(12, int(18 * s))
		tag.add_theme_font_size_override("font_size", tag_size)
		tag.size = Vector2(r.size.x, tag_size + 10)
		var above := r.position.y - cell_pos.y
		v.tag_overlaps_view = above < tag.size.y + 4
		if !v.tag_overlaps_view:
			tag.position = Vector2(r.position.x + 6, r.position.y - tag.size.y - 2)
			tag.modulate.a = 0.6
		else:
			tag.position = r.position + Vector2(10, 6)
		var warning : Label = v.warning
		warning.add_theme_font_size_override("font_size", maxi(14, int(24 * s)))
		warning.position = r.position
		warning.size = r.size


# ---------------------------------------------------------------- resource isolation

func _isolate_resources(root: Node, cache: Dictionary) -> void:
	var stack : Array[Node] = [root]
	while !stack.is_empty():
		var n : Node = stack.pop_back()
		if n is GeometryInstance3D:
			var g := n as GeometryInstance3D
			g.material_override = _isolated(g.material_override, cache)
			if n is MeshInstance3D:
				var m := n as MeshInstance3D
				for s in m.get_surface_override_material_count():
					var mat := m.get_surface_override_material(s)
					if mat != null:
						m.set_surface_override_material(s, _isolated(mat, cache))
		elif n is WorldEnvironment:
			var w := n as WorldEnvironment
			w.environment = _isolated(w.environment, cache)
		elif n is Camera3D:
			var cam := n as Camera3D
			cam.environment = _isolated(cam.environment, cache)
		var script : Script = n.get_script()
		if script != null:
			for prop in script.get_script_property_list():
				if prop.type == TYPE_OBJECT:
					var value = n.get(prop.name)
					if value is Resource:
						var iso = _isolated(value, cache)
						if iso != value:
							n.set(prop.name, iso)
		stack.append_array(n.get_children())

func _isolated(res, cache: Dictionary):
	if res == null:
		return null
	if !(res is Environment) and !(res.resource_path in ISOLATED_MATERIALS):
		return res
	if !cache.has(res):
		cache[res] = res.duplicate()
	return cache[res]

func _on_node_added(node: Node) -> void:
	if node.scene_file_path != USER_INSTANCE:
		return
	var c = SplitMod.ctx_of(node)
	if c != null:
		_isolate_resources(node, _isolation_caches[c.index])


# ---------------------------------------------------------------- input routing

func _input(event: InputEvent) -> void:
	if !started:
		get_viewport().set_input_as_handled()
		return
	var target := -1
	if event is InputEventMouse:
		target = _kbm_index
	elif event is InputEventKey:
		target = _kbm_index if _kbm_index != -1 else 0
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for v in views:
			if v.ctx.device == event.device:
				target = v.ctx.index
	get_viewport().set_input_as_handled()
	if target == -1:
		return
	var v : Dictionary = views[target]
	var ev := event
	if event is InputEventMouse:
		ev = _mouse_to_view(event, v.ctx.view_rect)
	v.vp.push_input(ev, true)

## Converts a window-space mouse event to the player's 960x540 view, keeping the cursor inside that view.
func _mouse_to_view(event: InputEventMouse, r: Rect2) -> InputEventMouse:
	var ev := event.duplicate() as InputEventMouse
	if !r.has_area():
		return ev
	var local : Vector2
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		local = Vector2(VIEW_SIZE) / 2.0
	else:
		var inside := Vector2(clampf(event.position.x, r.position.x, r.end.x - 1), clampf(event.position.y, r.position.y, r.end.y - 1))
		if inside != event.position and event is InputEventMouseMotion and get_window().has_focus():
			Input.warp_mouse(inside)
		local = (inside - r.position) * (Vector2(VIEW_SIZE) / r.size)
	ev.position = local
	ev.global_position = local
	if ev is InputEventMouseMotion:
		# Same motion scale as the unmodded game, where the 960x540 view fills the whole window.
		var win_size := get_viewport_rect().size
		var factor := 1.0 / minf(win_size.x / VIEW_SIZE.x, win_size.y / VIEW_SIZE.y)
		ev.relative = event.relative * factor
		ev.velocity = event.velocity * factor
	return ev


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	for v in views:
		if v.ctx.device == device:
			v.warning.visible = !connected
