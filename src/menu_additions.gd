
# splitscreen mod: "LOCAL SPLITSCREEN" entry under MULTIPLAYER, cloned from the multiplayer button
func _splitscreen_add_button():
	var label_mp : Label = parent_main.get_node("button_multiplayer")
	var button_mp : Button = parent_main.get_node("true button_multiplayer")
	var step = parent_main.get_node("button_options").position.y - label_mp.position.y
	for node_name in ["button_options", "true button_options", "button_credits", "true button_credits", "button_exit", "true button_exit"]:
		parent_main.get_node(node_name).position.y += step

	var label : Label = label_mp.duplicate(0)
	label.name = "button_splitscreen"
	label.text = "LOCAL SPLITSCREEN"
	label.position.y = label_mp.position.y + step
	parent_main.add_child(label)
	parent_main.move_child(label, label_mp.get_index() + 1)

	var font : Font = label_mp.get_theme_font("font")
	var font_size = label_mp.get_theme_font_size("font_size")
	var width_mp = font.get_string_size(tr(label_mp.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width_new = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var hit_width = button_mp.size.x * button_mp.scale.x * width_new / max(width_mp, 1.0)
	var label_center_x = label_mp.position.x + label_mp.pivot_offset.x + (label_mp.size.x / 2 - label_mp.pivot_offset.x) * label_mp.scale.x

	var button : Button = button_mp.duplicate(Node.DUPLICATE_SCRIPTS)
	button.name = "true button_splitscreen"
	button.scale.x = hit_width / button.size.x
	button.position = Vector2(label_center_x - hit_width / 2, button_mp.position.y + step)
	button.focus_neighbor_top = NodePath("../true button_multiplayer")
	button.focus_neighbor_bottom = NodePath("../true button_options")
	var button_class : ButtonClass = button.get_child(0)
	button_class.name = "button class_splitscreen"
	button_class.alias = "start splitscreen"
	button_class.ui = label
	parent_main.add_child(button)
	parent_main.move_child(button, button_mp.get_index() + 1)
	button_mp.focus_neighbor_bottom = NodePath("../true button_splitscreen")
	parent_main.get_node("true button_options").focus_neighbor_top = NodePath("../true button_splitscreen")

	buttons.append(button_class)
	button_class.connect("is_pressed", StartSplitscreen)

func StartSplitscreen():
	Buttons(false)
	ResetButtons()
	for screen in screens: screen.visible = false
	title.visible = false
	controller.previousFocus = null
	speaker_music.stop()
	animator_intro.play("snap")
	for w in waterfalls: w.pause()
	speaker_start.play()
	cursor.SetCursor(false, false)
	await get_tree().create_timer(4, false).timeout
	print("changing scene to: splitscreen lobby")
	get_tree().change_scene_to_file(SplitMod.LOBBY_SCENE)
