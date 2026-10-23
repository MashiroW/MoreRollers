extends Node
## Test driver for the splitscreen mod (only used in the isolated test copy, never shipped).
## Players are P1 on keyboard & mouse and P2 on controller 0 (virtual: events are injected, so no pad is needed).
## SPLIT_TEST_MODE=session         plays a match with synthetic input that goes through the real router
## SPLIT_TEST_MODE=menu            menu entry, lobby, customization screen and back
## SPLIT_TEST_MODE=disconnect_real SPLIT_TEST_DISCONNECT=1|2: Disconnect through the real pause-menu buttons
## SPLIT_TEST_MODE=conclusion      the host ends the match; SPLIT_TEST_DISCONNECT=1|2 also disconnects during results
## SPLIT_TEST_MODE=custom_visual   lobby + customization screen driven with the controller, then a match
## SPLIT_TEST_MODE=online_lobby    the normal multiplayer lobby, which must be unchanged
## SPLIT_TEST_MODE=disconnect / experiment / quit: narrower checks used while tracking the teardown crash
## SPLIT_TEST_SHOTS=<folder> saves screenshots there (SPLIT_TEST_VIEWS=1 also saves each player's view).

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
		print("SPLITTEST lobby players=", SplitMod.players, " rows=", lobby.rows.map(func(l): return l.text), " summary=", lobby.summary_label.text)
		# The original customization screen: fewer rounds and skip intro, saved through its own handler.
		lobby.selected = lobby.Row.CUSTOMIZE
		lobby._activate()
		await get_tree().create_timer(3.0).timeout
		var mp_lobby = get_tree().current_scene
		var mc = mp_lobby.get_node("standalone managers/match customization")
		var ui = mp_lobby.get_node("standalone managers/lobby ui")
		print("SPLITTEST customization scene=", mp_lobby.name, " customization visible=", ui.ui_parent_match_customization.visible, " home visible=", ui.ui_parent_lobby_home.visible, " rounds label=", mc.label_number_of_rounds.text)
		mc.Pipe("number of rounds minus", null)
		mc.Pipe("skip intro", null)
		print("SPLITTEST edited: rounds=", mc.active_customization_dictionary.number_of_rounds, " skip=", mc.active_customization_dictionary.skipping_intro)
		mc.Pipe("save changes and return", null)
		await get_tree().create_timer(3.0).timeout
		lobby = get_tree().current_scene
		print("SPLITTEST back in scene=", lobby.name, " players=", SplitMod.players.size(), " summary=", lobby.summary_label.text, " match_settings rounds=", SplitMod.match_settings().number_of_rounds, " skip=", SplitMod.match_settings().skipping_intro, " gui_input_disabled=", get_viewport().gui_disable_input)
		lobby._back_to_menu()
		await get_tree().create_timer(2.0).timeout
		print("SPLITTEST back to scene=", get_tree().current_scene.name)
		get_tree().quit()
		return
	if mode == "disconnect":
		# SPLIT_TEST_DISCONNECT=1 or 2: that player opens their pause menu with their device and confirms Disconnect.
		var who := int(OS.get_environment("SPLIT_TEST_DISCONNECT")) - 1
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		_set_match(1, true)
		SplitMod.start_session()
		var session = null
		while session == null or !session.get("started"):
			await get_tree().process_frame
			session = get_tree().current_scene
		var v = session.views[who]
		var inter = _intermediary(v)
		while inter.intermed_properties == null or !inter.game_state.MAIN_item_grabbing_in_progress:
			await get_tree().process_frame
		await get_tree().create_timer(2.0).timeout
		print("SPLITTEST P%d opens pause menu" % (who + 1))
		var open : InputEvent
		if v.ctx.device == SplitMod.DEVICE_KBM:
			open = InputEventKey.new(); open.keycode = KEY_ESCAPE; open.physical_keycode = KEY_ESCAPE; open.pressed = true
		else:
			open = InputEventJoypadButton.new(); open.device = v.ctx.device; open.button_index = JOY_BUTTON_START; open.pressed = true
		Input.parse_input_event(open)
		await get_tree().create_timer(1.0).timeout
		print("SPLITTEST pause menu visible=", inter.ingame_lobby_ui.ui_parent.visible, " other player's pause menu visible=", _intermediary(session.views[1 - who]).ingame_lobby_ui.ui_parent.visible)
		inter.InteractionPipe("disconnect button", null)
		await get_tree().create_timer(0.5).timeout
		print("SPLITTEST P%d confirms disconnect" % (who + 1))
		inter.InteractionPipe("disconnect confirmation yes", null)
		var waited := 0.0
		while waited < 10.0 and get_tree().current_scene != null and get_tree().current_scene.name != "split_lobby":
			await get_tree().process_frame
			waited += get_process_delta_time()
		await get_tree().create_timer(3.0).timeout
		print("SPLITTEST after disconnect: scene=", get_tree().current_scene.name if get_tree().current_scene else "null", " active=", SplitMod.active, " players=", SplitMod.players.size(), " scale_mode=", get_window().content_scale_mode)
		_screenshot()
		get_tree().quit()
		return
	if mode == "online_lobby":
		# The normal multiplayer lobby (not opened for splitscreen) must behave as in the unmodded game.
		await get_tree().create_timer(1.5).timeout
		get_tree().change_scene_to_file(SplitMod.MP_LOBBY_SCENE)
		await get_tree().create_timer(4.0).timeout
		var ui = get_tree().current_scene.get_node("standalone managers/lobby ui")
		print("SPLITTEST online lobby: scene=%s home=%s customization=%s customizing=%s" % [get_tree().current_scene.name, ui.ui_parent_lobby_home.visible, ui.ui_parent_match_customization.visible, SplitMod.customizing])
		ui.lobby.Pipe("customize match settings")
		await get_tree().create_timer(0.5).timeout
		print("SPLITTEST online lobby after customize: home=%s customization=%s" % [ui.ui_parent_lobby_home.visible, ui.ui_parent_match_customization.visible])
		get_tree().current_scene.get_node("standalone managers/match customization").Pipe("cancel changes", null)
		await get_tree().create_timer(1.5).timeout
		print("SPLITTEST online lobby after cancel: scene=%s home=%s customization=%s" % [get_tree().current_scene.name, ui.ui_parent_lobby_home.visible, ui.ui_parent_match_customization.visible])
		get_tree().quit()
		return
	if mode == "custom_visual":
		# Screenshots of the splitscreen lobby and of the customization screen driven with a controller,
		# then a match started with the saved settings.
		await get_tree().create_timer(1.5).timeout
		GlobalVariables.stashed_match_customization_dictionary = {}
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		get_tree().change_scene_to_file(SplitMod.LOBBY_SCENE)
		await get_tree().create_timer(2.0).timeout
		_screenshot()
		var lobby = get_tree().current_scene
		lobby.selected = lobby.Row.CUSTOMIZE
		lobby._refresh()
		await get_tree().create_timer(0.5).timeout
		_screenshot()
		lobby._activate()
		await get_tree().create_timer(3.5).timeout
		_screenshot()
		for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_UP]:
			await _press_pad(0, b)
			await get_tree().create_timer(0.4).timeout
			var f = get_viewport().gui_get_focus_owner()
			print("SPLITTEST customization focus after pad %d: %s" % [b, f.get_parent().name + "/" + f.name if f else "-"])
		_screenshot()
		var mc = get_tree().current_scene.get_node("standalone managers/match customization")
		mc.Pipe("number of rounds minus", null)
		mc.Pipe("number of rounds minus", null)
		mc.Pipe("skip intro", null)
		await get_tree().create_timer(0.5).timeout
		_screenshot()
		mc.Pipe("save changes and return", null)
		await get_tree().create_timer(3.0).timeout
		_screenshot()
		SplitMod.join(0)
		SplitMod.start_session()
		await get_tree().create_timer(4.0).timeout
		print("SPLITTEST match uses: rounds end index=", GlobalVariables.debug_round_index_to_end_game_at, " skipping_intro=", GlobalVariables.skipping_intro, " active dict rounds=", GlobalVariables.active_match_customization_dictionary.number_of_rounds)
		SplitMod.end_session("")
		await get_tree().create_timer(3.0).timeout
		print("SPLITTEST after match: scene=", get_tree().current_scene.name, " stashed rounds=", GlobalVariables.stashed_match_customization_dictionary.number_of_rounds)
		_screenshot()
		get_tree().quit()
		return
	if mode == "disconnect_real" or mode == "quit":
		# disconnect_real: SPLIT_TEST_DISCONNECT=1 (Escape + mouse clicks) or 2 (controller Start / D-pad / A).
		# quit: the window is closed in the middle of the match.
		var who := int(OS.get_environment("SPLIT_TEST_DISCONNECT")) - 1
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		_set_match(1, true)
		SplitMod.start_session()
		var session = null
		while session == null or !session.get("started"):
			await get_tree().process_frame
			session = get_tree().current_scene
		while _intermediary(session.views[0]).intermed_properties == null or !_intermediary(session.views[0]).game_state.MAIN_item_grabbing_in_progress:
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		if mode == "quit":
			print("SPLITTEST closing the window mid-match")
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
			return
		var v = session.views[who]
		var inter = _intermediary(v)
		var ui = inter.ingame_lobby_ui
		if v.ctx.device == SplitMod.DEVICE_KBM:
			await _press_key(KEY_ESCAPE)
			await get_tree().create_timer(0.8).timeout
			print("SPLITTEST P1 pause visible=", ui.ui_parent.visible)
			await _click_control(v, ui.button_disconnect.get_child(0))
			await get_tree().create_timer(0.8).timeout
			print("SPLITTEST P1 confirmation visible=", ui.confirmation_text.visible)
			await _click_control(v, ui.button_confirm_yes.get_child(0))
		else:
			await _press_pad(v.ctx.device, JOY_BUTTON_START)
			await get_tree().create_timer(0.8).timeout
			print("SPLITTEST P2 pause visible=", ui.ui_parent.visible, " focus=", _focus_name(v))
			await _press_pad(v.ctx.device, JOY_BUTTON_DPAD_DOWN)
			print("SPLITTEST P2 focus=", _focus_name(v))
			await _press_pad(v.ctx.device, JOY_BUTTON_A)
			await get_tree().create_timer(0.8).timeout
			print("SPLITTEST P2 confirmation visible=", ui.confirmation_text.visible, " focus=", _focus_name(v))
			await _press_pad(v.ctx.device, JOY_BUTTON_DPAD_LEFT)
			print("SPLITTEST P2 focus=", _focus_name(v))
			await _press_pad(v.ctx.device, JOY_BUTTON_A)
		var waited := 0.0
		while waited < 10.0 and get_tree().current_scene != null and get_tree().current_scene.name != "split_lobby":
			await get_tree().process_frame
			waited += get_process_delta_time()
		await get_tree().create_timer(3.0).timeout
		print("SPLITTEST after real disconnect: scene=%s active=%s" % [get_tree().current_scene.name if get_tree().current_scene else "null", SplitMod.active])
		_screenshot()
		get_tree().quit()
		return
	if mode == "experiment":
		# P2 presses the pause menu's Continue button with the controller, then the views are freed one by one.
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		_set_match(1, true)
		SplitMod.start_session()
		var session = null
		while session == null or !session.get("started"):
			await get_tree().process_frame
			session = get_tree().current_scene
		while _intermediary(session.views[0]).intermed_properties == null or !_intermediary(session.views[0]).game_state.MAIN_item_grabbing_in_progress:
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		var exp := OS.get_environment("SPLIT_TEST_EXP")
		if exp != "nopress":
			await _press_pad(0, JOY_BUTTON_START)
			await get_tree().create_timer(0.8).timeout
			print("SPLITTEST EXP focus before A=", _focus_name(session.views[1]))
			match exp:
				"press": await _press_pad(0, JOY_BUTTON_A)
				"dpad": await _press_pad(0, JOY_BUTTON_DPAD_DOWN)
				"continue_direct": _intermediary(session.views[1]).InteractionPipe("continue button", null)
				"emit_pressed": session.views[1].vp.gui_get_focus_owner().emit_signal("pressed")
				"hideconf": _intermediary(session.views[1]).ingame_lobby_ui.HideConfirmation()
				"revertfocus": _intermediary(session.views[1]).ingame_lobby_ui.RevertInitialFocus()
				"intake_focus": _intermediary(session.views[1]).intermed_properties.item_manager.btn_briefcase_intake.grab_focus()
				"setcursor": _intermediary(session.views[1]).intermed_properties.cursor.SetCursor(true, false)
			await get_tree().create_timer(1.0).timeout
			print("SPLITTEST EXP pause visible=", _intermediary(session.views[1]).ingame_lobby_ui.ui_parent.visible, " focus=", _focus_name(session.views[1]))
		for i in [1, 0]:
			print("SPLITTEST EXP freeing mp_main of view ", i + 1)
			session.views[i].vp.get_child(0).free()
			print("SPLITTEST EXP freed mp_main of view ", i + 1)
			await get_tree().process_frame
			await get_tree().process_frame
		print("SPLITTEST EXP all mp_main freed, ending session")
		SplitMod.end_session("")
		await get_tree().create_timer(3.0).timeout
		print("SPLITTEST EXP scene=", get_tree().current_scene.name)
		get_tree().quit()
		return
	if mode == "conclusion":
		# The host ends the match right away (same packet as a real final shot); optionally a player
		# disconnects during the results screen (SPLIT_TEST_DISCONNECT=1 or 2).
		var who := int(OS.get_environment("SPLIT_TEST_DISCONNECT")) - 1 if OS.get_environment("SPLIT_TEST_DISCONNECT") != "" else -1
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		_set_match(1, true)
		SplitMod.start_session()
		var session = null
		while session == null or !session.get("started"):
			await get_tree().process_frame
			session = get_tree().current_scene
		var host = _intermediary(session.views[0])
		while host.intermed_properties == null or !host.game_state.MAIN_item_grabbing_in_progress:
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		print("SPLITTEST host sends game conclusion")
		host.roundManager.GameConclusion_Packet()
		var waited := 0.0
		var disconnected := false
		while waited < 70.0 and get_tree().current_scene != null and get_tree().current_scene.name != "split_lobby":
			if who >= 0 and !disconnected and waited > 20.0:
				disconnected = true
				var inter = _intermediary(session.views[who])
				print("SPLITTEST P%d disconnects during results, outro visible=%s" % [who + 1, inter.win_manager != null])
				inter.InteractionPipe("disconnect confirmation yes", null)
			if int(waited) % 5 == 0 and int(waited - get_process_delta_time()) % 5 != 0:
				_screenshot()
				print("SPLITTEST waiting t=%.1f scene=%s" % [waited, get_tree().current_scene.name])
			await get_tree().process_frame
			waited += get_process_delta_time()
		await get_tree().create_timer(3.0).timeout
		print("SPLITTEST after conclusion: waited=%.1f scene=%s active=%s scale_mode=%d" % [waited, get_tree().current_scene.name if get_tree().current_scene else "null", SplitMod.active, get_window().content_scale_mode])
		_screenshot()
		get_tree().quit()
		return
	if mode == "session" or mode == "lobby":
		await get_tree().create_timer(1.5).timeout
		SplitMod.players.clear()
		SplitMod.join(SplitMod.DEVICE_KBM)
		SplitMod.join(0)
		_set_match(int(OS.get_environment("SPLIT_TEST_ROUNDS")) if OS.get_environment("SPLIT_TEST_ROUNDS") != "" else 1, OS.get_environment("SPLIT_TEST_SKIP_INTRO") != "0")
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

## Match settings for automated runs, stored where the customization screen saves them.
func _set_match(rounds: int, skip_intro: bool) -> void:
	var m : Dictionary = SplitMod._default_match_customization()
	m.number_of_rounds = rounds
	m.skipping_intro = skip_intro
	GlobalVariables.stashed_match_customization_dictionary = m

func _focus_name(v) -> String:
	var f = v.vp.gui_get_focus_owner()
	return f.name if f else "-"

func _press_pad(device: int, button: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device; e.button_index = button; e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().create_timer(0.1).timeout

func _press_key(keycode: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode; e.physical_keycode = keycode; e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().create_timer(0.1).timeout

## Moves the mouse over a Control inside a player's view and left-clicks it, through the real router.
func _click_control(v, control: Control) -> void:
	var r : Rect2 = v.ctx.view_rect
	var wp : Vector2 = r.position + control.get_global_rect().get_center() * r.size / Vector2(960, 540)
	print("SPLITTEST click %s at window %s" % [control.name, wp])
	for k in 3:
		var mm := InputEventMouseMotion.new()
		mm.position = wp + Vector2(k, 0); mm.global_position = mm.position; mm.relative = Vector2(1, 0); mm.velocity = Vector2(30, 0)
		Input.parse_input_event(mm)
		await get_tree().process_frame
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT; b.pressed = pressed; b.position = wp + Vector2(2, 0); b.global_position = b.position
		Input.parse_input_event(b)
		await get_tree().create_timer(0.1).timeout

func _screenshot() -> void:
	if shots_dir == "":
		return
	var img := get_viewport().get_texture().get_image()
	if img == null: return
	var path := shots_dir.path_join("shot_%04d.png" % shot_index)
	img.save_png(path)
	# SPLIT_TEST_VIEWS=1 also saves each player's view at its own resolution.
	var session = get_tree().current_scene
	if OS.get_environment("SPLIT_TEST_VIEWS") == "1" and SplitMod.active and session != null and session.get("views") != null:
		for v in session.views:
			var view_img : Image = v.vp.get_texture().get_image()
			if view_img != null: view_img.save_png(shots_dir.path_join("shot_%04d_p%d.png" % [shot_index, v.ctx.index + 1]))
	shot_index += 1

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
