
# splitscreen mod: opened from the splitscreen lobby, this scene only shows its match customization
# screen; saving or cancelling goes back to the splitscreen lobby.
func SplitCustomizeIntro():
	await get_tree().create_timer(.1, false).timeout
	animator_intro.play("short intro")
	speaker_music.play()
	EnterMatchCustomization()
	await get_tree().create_timer(.8, false).timeout
	GlobalVariables.cursor_state_after_toggle = true
	cursor.SetCursor(true, true)

var split_leaving = false
func SplitReturnFromCustomization():
	if split_leaving: return
	split_leaving = true
	speaker_music.stop()
	GlobalVariables.cursor_state_after_toggle = false
	cursor.SetCursor(false, false)
	speaker_exit.play()
	animator_intro.play("outro cut out")
	# Nothing may keep focus or hover while the scene is freed (Godot 4.1 can crash on that);
	# the splitscreen lobby turns GUI input back on.
	get_viewport().gui_disable_input = true
	get_viewport().gui_release_focus()
	get_viewport().notification(NOTIFICATION_VP_MOUSE_EXIT)
	await get_tree().create_timer(.60, false).timeout
	viewblocker_main.visible = true
	await get_tree().create_timer(.2, false).timeout
	get_viewport().gui_release_focus()
	SplitMod.customizing = false
	get_tree().change_scene_to_file(SplitMod.LOBBY_SCENE)
