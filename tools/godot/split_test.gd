extends Node
## Test driver for the splitscreen mod (only used in the isolated test copy, never shipped).
## SPLIT_TEST_MODE=session : starts a 2-player match directly (P1 mouse, P2 virtual controller 0)
##                          and plays it with synthetic input that goes through the real router.
## SPLIT_TEST_MODE=menu    : just lets the main menu run (for screenshots of the new entry).

var mode := ""
var shots_dir := ""
var shot_interval := 2.0
var max_time := 240.0
var t := 0.0
var next_shot := 1.0
var shot_index := 0
var last_state := ""
var bot_cooldown := {}
var busy := {}
var session_started_at := -1.0
var errors := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mode = OS.get_environment("SPLIT_TEST_MODE")
	shots_dir = OS.get_environment("SPLIT_TEST_SHOTS")
	if OS.get_environment("SPLIT_TEST_INTERVAL") != "": shot_interval = float(OS.get_environment("SPLIT_TEST_INTERVAL"))
	if OS.get_environment("SPLIT_TEST_MAXTIME") != "": max_time = float(OS.get_environment("SPLIT_TEST_MAXTIME"))
	print("SPLITTEST mode=", mode, " shots=", shots_dir)
	if mode == "menu":
		await get_tree().create_timer(2.0).timeout
		var menu = get_tree().current_scene.get_node("standalone managers/menu manager")
		var main_screen : Control = menu.parent_main
		for n in ["button_multiplayer", "button_splitscreen", "button_options", "button_credits", "button_exit", "true button_multiplayer", "true button_splitscreen", "true button_options", "true button_exit"]:
			var c : Control = main_screen.get_node_or_null(n)
			print("SPLITTEST menu node %s: %s" % [n, ("pos=%s size=%s scale=%s" % [c.position, c.size, c.scale]) if c else "MISSING"])
		var bc = main_screen.get_node("true button_splitscreen").get_child(0)
		print("SPLITTEST menu button class ui=", bc.ui.name, " in buttons array=", bc in menu.buttons)
		print("SPLITTEST focus neighbors: mp.bottom=", main_screen.get_node("true button_multiplayer").focus_neighbor_bottom, " options.top=", main_screen.get_node("true button_options").focus_neighbor_top)
		menu.StartSplitscreen()
		await get_tree().create_timer(5.5).timeout
		var lobby = get_tree().current_scene
		print("SPLITTEST after StartSplitscreen scene=", lobby.name, " slots=", lobby.get("slots").size() if lobby.get("slots") != null else -1)
		lobby._join(SplitMod.DEVICE_KBM)
		lobby._join(0)
		lobby._move(-1)
		lobby._change(1)
		print("SPLITTEST lobby players=", SplitMod.players, " rounds=", SplitMod.setting_rounds, " row texts=", lobby.rows.map(func(l): return l.text))
		lobby._back_to_menu()
		await get_tree().create_timer(2.0).timeout
		print("SPLITTEST back to scene=", get_tree().current_scene.name)
		get_tree().quit()
		return
	if mode == "session" or mode == "lobby":
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		SplitMod.setting_rounds = int(OS.get_environment("SPLIT_TEST_ROUNDS")) if OS.get_environment("SPLIT_TEST_ROUNDS") != "" else 1
		SplitMod.setting_skip_intro = OS.get_environment("SPLIT_TEST_SKIP_INTRO") != "0"
		if mode == "session":
			SplitMod.start_session()
		else:
			get_tree().change_scene_to_file(SplitMod.LOBBY_SCENE)

func _process(delta: float) -> void:
	t += delta
	if shots_dir != "" and t >= next_shot:
		next_shot = t + shot_interval
		_screenshot()
	if t >= max_time:
		print("SPLITTEST max time reached, errors=", errors)
		get_tree().quit()
		return
	var session = get_tree().current_scene
	if mode == "session" and SplitMod.active and session != null and session.get("started"):
		if session_started_at < 0: session_started_at = t
		_log_state(session)
		for v in session.views:
			_bot(session, v)
	elif mode == "session" and session_started_at > 0 and !SplitMod.active:
		print("SPLITTEST session ended at t=", t, " scene=", session.name if session else "null")
		session_started_at = -2.0
		max_time = t + 8.0

func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null: return
	var path := shots_dir.path_join("shot_%04d.png" % shot_index)
	shot_index += 1
	img.save_png(path)

func _intermediary(v):
	var root = v.vp.get_child(0)
	return root.get_node("standalone managers/interactions/interaction intermediary")

func _log_state(session) -> void:
	var parts := []
	var worlds := []
	for v in session.views:
		var inter = _intermediary(v)
		var p = inter.intermed_properties
		var gs = inter.game_state
		if p == null:
			parts.append("P%d: (no instance yet)" % (v.ctx.index + 1))
			continue
		parts.append("P%d sock=%d hp=%d turn=%d has_turn=%s perm=%s grab=%s holditem=%s shotgun=%s ctrl=%s cursor=%s focus=%s" % [
			v.ctx.index + 1, p.socket_number, p.health_current, gs.MAIN_active_current_turn_socket, p.has_turn,
			p.major_permission_enabled, p.is_grabbing_items, p.is_holding_item_to_place, p.is_holding_shotgun,
			p.cursor.controller_active, p.cursor.cursor_visible, v.vp.gui_get_focus_owner().name if v.vp.gui_get_focus_owner() else "-"])
		var hp := []
		for prop in inter.instance_handler.instance_property_array:
			hp.append("%s:%d:%d" % [prop.user_name, prop.socket_number, prop.health_current])
		hp.sort()
		worlds.append(" ".join(hp) + " round=%d seq=%s" % [gs.MAIN_active_round_index, str(gs.MAIN_active_sequence_dict.get("sequence_visible", []))])
	var state := " | ".join(parts) + "  ||  " + " ## ".join(worlds)
	if state != last_state:
		last_state = state
		print("SPLITTEST t=%.1f %s" % [t, state])
		if worlds.size() == 2 and worlds[0].split(" seq=")[0] != worlds[1].split(" seq=")[0]:
			print("SPLITTEST note: worlds differ right now (packets in flight?)")

# ---------------------------------------------------------------- bots

func _target_pos(node: Node) -> Vector3:
	var parent = node.get_parent()
	var stack : Array = [parent]
	while !stack.is_empty():
		var n = stack.pop_back()
		if n is CollisionShape3D and !n.disabled:
			return n.global_position
		stack.append_array(n.get_children())
	if parent is VisualInstance3D:
		return parent.global_transform * parent.get_aabb().get_center()
	return parent.global_position

func _bot(session, v) -> void:
	var i : int = v.ctx.index
	if busy.get(i, false): return
	if t < bot_cooldown.get(i, 0.0): return
	var inter = _intermediary(v)
	var p = inter.intermed_properties
	if p == null or !p.major_permission_enabled: return
	var gs = inter.game_state
	var action := ""
	var target = null
	# Decide from what is interactable right now (is_grabbing_items stays true on clients, like online).
	var free_grids := []
	for g in p.item_manager.intbranch_grid_colliders:
		if g.interactionAllowed: free_grids.append(g)
	if !p.is_holding_item_to_place and p.item_manager.intbranch_intake.interactionAllowed:
		action = "grab"; target = p.item_manager.intbranch_intake
	elif p.is_holding_item_to_place and !free_grids.is_empty():
		var attempt : int = bot_cooldown.get("place_%d" % i, 0)
		bot_cooldown["place_%d" % i] = attempt + 1
		action = "place"; target = free_grids[attempt % free_grids.size()]
	elif p.is_holding_shotgun and p.look_manager.checking:
		for other in inter.instance_handler.instance_property_array:
			if other != p and other.health_current > 0:
				action = "shoot"; target = other.hover_pan.intbranch; break
	elif gs.MAIN_active_current_turn_socket == p.socket_number and p.has_turn and inter.intbranch_shotgun.interactionAllowed:
		action = "pickup"; target = inter.intbranch_shotgun
	if action == "":
		return
	bot_cooldown[i] = t + 1.2
	if v.ctx.device == SplitMod.DEVICE_KBM:
		_click(session, v, target, action)
	else:
		_pad_press(v, action)

func _click(session, v, branch, action: String) -> void:
	var i : int = v.ctx.index
	busy[i] = true
	var cam : Camera3D = v.vp.get_camera_3d()
	var world := _target_pos(branch)
	if cam == null or cam.is_position_behind(world):
		print("SPLITTEST P%d %s: target behind camera" % [i + 1, action]); busy[i] = false; return
	var p2 := cam.unproject_position(world)
	var r : Rect2 = v.ctx.view_rect
	var wp := r.position + p2 * r.size / Vector2(960, 540)
	print("SPLITTEST P%d mouse %s at view %s window %s" % [i + 1, action, p2, wp])
	for k in 3:
		var mm := InputEventMouseMotion.new()
		mm.position = wp + Vector2(k, 0); mm.global_position = mm.position
		mm.relative = Vector2(1, 0); mm.velocity = Vector2(30, 0)
		Input.parse_input_event(mm)
		await get_tree().process_frame
		await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = wp + Vector2(2, 0); down.global_position = down.position
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := down.duplicate(); up.pressed = false
	Input.parse_input_event(up)
	busy[i] = false

func _pad_press(v, action: String) -> void:
	var i : int = v.ctx.index
	busy[i] = true
	var focus = v.vp.gui_get_focus_owner()
	var fname : String = focus.name if focus else "-"
	var button := JOY_BUTTON_A
	var p = _intermediary(v).intermed_properties
	match action:
		"place":
			if fname.begins_with("c button_local grid index "):
				var idx := int(fname.trim_prefix("c button_local grid index "))
				if p.user_inventory[idx] != {}: button = JOY_BUTTON_DPAD_LEFT
			elif fname == "c button_item briefcase intake":
				button = JOY_BUTTON_DPAD_LEFT
		"shoot":
			if fname == "c button shotgun target you": button = JOY_BUTTON_DPAD_UP
	print("SPLITTEST P%d pad %s for %s (focus=%s)" % [i + 1, "A" if button == JOY_BUTTON_A else "dpad %d" % button, action, fname])
	bot_cooldown[i] = t + (0.4 if button != JOY_BUTTON_A else 1.2)
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = v.ctx.device; e.button_index = button; e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
	busy[i] = false
