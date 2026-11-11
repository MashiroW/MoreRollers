extends Control
## Splitscreen lobby: local players join with their device, the match is customized on the game's own
## customization screen, and the match starts. Works with keyboard & mouse and any number of controllers; CPU players
## can take the seats left free (1 to 4 local players, 2 to 4 seats in all).

const FONT_MAIN := "res://fonts/fake receipt.otf"
const TEX_VIGNETTE := "res://misc/menu vignette1.png"
const SND_HOVER := "res://audio/button_hover.ogg"
const SND_PRESS := "res://audio/button press3.ogg"
const SND_LEAVE := "res://audio/show cursor.ogg"
const SND_START := "res://audio/button_start main.ogg"
const MUSIC := "res://multiplayer/audio/music/mp_music desolate loop3.ogg"
const TEX_DISCORD := "res://multiplayer/misc/mp_discord icon1.png"
const STICK_THRESHOLD := 0.6
## The online lobby draws its "find players" Discord link at this scale (the scale of the Control
## holding its menu), which squeezes the receipt font. The link here reuses it, with the same sizes.
const DISCORD_SCALE := Vector2(0.299635, 0.438273)
const DISCORD_ICON_SCALE := Vector2(0.14409, 0.0996983)

## DISCORD is not one of the centered rows: it is the green link in the corner, reached by moving
## down from BACK like the rows.
enum Row { CUSTOMIZE, BOTS, START, BACK, DISCORD }

var font : Font
var slots : Array = []
var rows : Array = []
var selected := Row.START
var message_label : Label
var summary_label : Label
var discord : Control
var discord_rect : Rect2
var fader : ColorRect
var leaving := false
var stick_latch := {}
var speaker_hover : AudioStreamPlayer
var speaker_press : AudioStreamPlayer
var speaker_leave : AudioStreamPlayer
var speaker_start : AudioStreamPlayer
var speaker_music : AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = load(FONT_MAIN)
	# Scenes leaving for this lobby turn GUI input off while they are freed.
	get_viewport().gui_disable_input = false
	AudioServer.set_bus_volume_db(3, linear_to_db(GlobalVariables.original_volume_linear_interaction))
	AudioServer.set_bus_volume_db(1, linear_to_db(GlobalVariables.original_volume_linear_music))
	_restore_cursor()
	_build()
	_drop_disconnected_players()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh()
	if SplitMod.lobby_message != "":
		_show_message(SplitMod.lobby_message)
		SplitMod.lobby_message = ""
	speaker_music.play()
	var tween := create_tween()
	tween.tween_property(fader, "color:a", 0.0, 0.8)


func _restore_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var image_path : String = ProjectSettings.get_setting("display/mouse_cursor/custom_image", "")
	if image_path != "":
		Input.set_custom_mouse_cursor(load(image_path), Input.CURSOR_ARROW, ProjectSettings.get_setting("display/mouse_cursor/custom_image_hotspot", Vector2.ZERO))


# ---------------------------------------------------------------- ui

func _label(text: String, size: int, pos: Vector2, width: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = Vector2(width, size + 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.auto_translate = false
	add_child(l)
	return l

func _speaker(path: String, volume_db: float, bus := &"Master") -> AudioStreamPlayer:
	var s := AudioStreamPlayer.new()
	s.stream = load(path)
	s.volume_db = volume_db
	s.bus = bus
	add_child(s)
	return s

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vignette := TextureRect.new()
	vignette.texture = load(TEX_VIGNETTE)
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_label("LOCAL SPLITSCREEN", 40, Vector2(0, 34), 960)
	var sub := _label("MULTIPLAYER  -  UP TO 4 PLAYERS ON ONE SCREEN, CPU PLAYERS IN THE FREE SEATS", 15, Vector2(0, 80), 960)
	sub.modulate.a = 0.55

	for i in SplitMod.MAX_PLAYERS:
		var panel := Panel.new()
		panel.position = Vector2(60 + i * 215, 120)
		panel.size = Vector2(195, 150)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		var title := _label("PLAYER %d" % (i + 1), 24, panel.position + Vector2(0, 18), panel.size.x)
		var device := _label("", 14, panel.position + Vector2(0, 62), panel.size.x)
		var status := _label("", 13, panel.position + Vector2(8, 96), panel.size.x - 16)
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.size.y = 44
		slots.append({"panel": panel, "title": title, "device": device, "status": status})

	var y := 290.0
	for r in [Row.CUSTOMIZE, Row.BOTS, Row.START, Row.BACK]:
		var l := _label("", 22, Vector2(0, y), 960)
		rows.append(l)
		y += 32.0

	summary_label = _label("", 13, Vector2(120, 422), 720)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.size.y = 40
	summary_label.modulate.a = 0.6
	message_label = _label("", 16, Vector2(0, 452), 960)
	message_label.modulate = Color(1, 0.45, 0.45, 0)
	_build_discord()
	var hint := _label("JOIN: ENTER / CLICK / (A)     LEAVE: BACKSPACE / (B)     SELECT: ARROWS / D-PAD     CPU PLAYERS: LEFT / RIGHT", 12, Vector2(0, 508), 960)
	hint.modulate.a = 0.5

	fader = ColorRect.new()
	fader.color = Color.BLACK
	fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fader)

	speaker_hover = _speaker(SND_HOVER, 3.0)
	speaker_press = _speaker(SND_PRESS, 0.0)
	speaker_leave = _speaker(SND_LEAVE, 1.5)
	speaker_start = _speaker(SND_START, 3.0)
	speaker_start.pitch_scale = 0.3
	speaker_music = _speaker(MUSIC, -4.0, &"music_secondary")
	speaker_music.finished.connect(speaker_music.play)

## The mod's Discord link, built like the online lobby's "find players" one: green text with a green
## outline, the game's Discord icon on its right, half transparent while hovered or selected.
func _build_discord() -> void:
	discord = Control.new()
	discord.mouse_filter = Control.MOUSE_FILTER_IGNORE
	discord.scale = DISCORD_SCALE
	add_child(discord)
	var l := Label.new()
	l.text = "MOREROLLERS DISCORD"
	l.auto_translate = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 39)
	l.add_theme_color_override("font_color", Color(0, 1, 0))
	l.add_theme_color_override("font_outline_color", Color(0, 1, 0))
	l.add_theme_constant_override("outline_size", 2)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discord.add_child(l)
	l.size = Vector2(l.get_minimum_size().x, 58)
	var icon := TextureRect.new()
	icon.texture = load(TEX_DISCORD)
	icon.self_modulate = Color(0, 1, 0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(520, 520)
	icon.scale = DISCORD_ICON_SCALE
	icon.position = Vector2(l.size.x + 17.5, 2.083)
	discord.add_child(icon)
	var screen_size := Vector2(icon.position.x + icon.size.x * DISCORD_ICON_SCALE.x, l.size.y) * DISCORD_SCALE
	discord.position = Vector2(922 - screen_size.x, 474)
	discord_rect = Rect2(discord.position, screen_size)

func _panel_style(joined: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.55)
	s.border_color = Color(1, 1, 1, 0.85 if joined else 0.18)
	s.set_border_width_all(2)
	return s

func _refresh() -> void:
	var bots := SplitMod.bots_in_match()
	for i in slots.size():
		var slot : Dictionary = slots[i]
		var joined := i < SplitMod.players.size()
		var bot := !joined and i < SplitMod.players.size() + bots
		slot.panel.add_theme_stylebox_override("panel", _panel_style(joined or bot))
		slot.title.modulate.a = 1.0 if joined or bot else 0.35
		slot.title.text = SplitMod.bot_name(i - SplitMod.players.size() + 1, bots) if bot else "PLAYER %d" % (i + 1)
		if bot:
			slot.device.text = SplitMod.device_label(SplitMod.DEVICE_BOT)
			slot.device.modulate.a = 1.0
			slot.status.text = "PLAYS LIKE THE DEALER"
			# Every seat taken: joining still works, the last CPU player makes room.
			if i == SplitMod.MAX_PLAYERS - 1:
				slot.status.text = "JOIN TO TAKE\nTHIS SEAT"
			slot.status.modulate.a = 0.5
		elif joined:
			var device : int = SplitMod.players[i].device
			slot.device.text = SplitMod.device_label(device)
			slot.status.text = "HOST" if i == 0 else "READY"
			if device != SplitMod.DEVICE_KBM:
				slot.status.text += "\n" + Input.get_joy_name(device).to_upper().left(24)
			slot.device.modulate.a = 1.0
			slot.status.modulate.a = 0.6
		else:
			slot.device.text = ""
			slot.status.text = "PRESS ENTER / CLICK\nOR (A) TO JOIN" if i == SplitMod.players.size() + bots else ""
			slot.status.modulate.a = 0.5
	var texts := {
		Row.CUSTOMIZE: tr("MP_UI CUSTOMIZE MATCH"),
		Row.BOTS: "CPU PLAYERS:  %d" % bots,
		Row.START: "START",
		Row.BACK: "BACK",
	}
	for r in rows.size():
		var l : Label = rows[r]
		l.text = ("<  " + texts[r] + "  >") if r == selected else texts[r]
		l.modulate.a = 1.0 if r == selected else 0.55
	if !SplitMod.can_start():
		rows[Row.START].modulate.a *= 0.5
	if SplitMod.players.size() >= SplitMod.MAX_PLAYERS:
		rows[Row.BOTS].modulate.a *= 0.5
	discord.modulate.a = 0.5 if selected == Row.DISCORD else 1.0
	summary_label.text = "     ".join(SplitMod.match_summary())

func _show_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(message_label, "modulate:a", 0.0, 1.0)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if leaving:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		_on_key(event)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(event.position)
	elif event is InputEventMouseMotion:
		var r := _row_at(event.position)
		if r != -1 and r != selected:
			_select(r)
	elif event is InputEventJoypadButton and event.pressed:
		_on_pad_button(event)
	elif event is InputEventJoypadMotion:
		_on_pad_motion(event)
	else:
		return
	get_viewport().set_input_as_handled()

func _on_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if event.echo: return
			if !SplitMod.is_joined(SplitMod.DEVICE_KBM): _join(SplitMod.DEVICE_KBM)
			else: _activate()
		KEY_BACKSPACE:
			if !event.echo: _leave(SplitMod.DEVICE_KBM)
		KEY_ESCAPE:
			if !event.echo: _back_to_menu()
		KEY_UP: _move(-1)
		KEY_DOWN: _move(1)
		KEY_LEFT: _change_bots(-1)
		KEY_RIGHT: _change_bots(1)

func _on_click(pos: Vector2) -> void:
	if discord_rect.has_point(pos):
		_select(Row.DISCORD)
		_activate()
		return
	if !SplitMod.is_joined(SplitMod.DEVICE_KBM):
		_join(SplitMod.DEVICE_KBM)
		return
	var r := _row_at(pos)
	if r == -1:
		return
	_select(r)
	_activate()

func _on_pad_button(event: InputEventJoypadButton) -> void:
	var device := event.device
	match event.button_index:
		JOY_BUTTON_A:
			if !SplitMod.is_joined(device): _join(device)
			else: _activate()
		JOY_BUTTON_B:
			_leave(device)
		JOY_BUTTON_START:
			if SplitMod.is_joined(device): _try_start()
			else: _join(device)
		JOY_BUTTON_DPAD_UP: _move(-1)
		JOY_BUTTON_DPAD_DOWN: _move(1)
		JOY_BUTTON_DPAD_LEFT: _change_bots(-1)
		JOY_BUTTON_DPAD_RIGHT: _change_bots(1)

func _on_pad_motion(event: InputEventJoypadMotion) -> void:
	if event.axis != JOY_AXIS_LEFT_Y and event.axis != JOY_AXIS_LEFT_X:
		return
	var key := "%d:%d" % [event.device, event.axis]
	if absf(event.axis_value) < STICK_THRESHOLD * 0.5:
		stick_latch[key] = false
		return
	if absf(event.axis_value) < STICK_THRESHOLD or stick_latch.get(key, false):
		return
	stick_latch[key] = true
	if event.axis == JOY_AXIS_LEFT_X: _change_bots(1 if event.axis_value > 0 else -1)
	else: _move(1 if event.axis_value > 0 else -1)

func _row_at(pos: Vector2) -> int:
	for r in rows.size():
		var l : Label = rows[r]
		if Rect2(l.position + Vector2(300, 0), Vector2(360, l.size.y)).has_point(pos):
			return r
	if discord_rect.has_point(pos):
		return Row.DISCORD
	return -1


# ---------------------------------------------------------------- actions

func _select(r: int) -> void:
	selected = r
	speaker_hover.pitch_scale = randf_range(0.95, 1.0)
	speaker_hover.play()
	_refresh()

func _move(dir: int) -> void:
	_select(wrapi(selected + dir, 0, Row.size()))

func _activate() -> void:
	match selected:
		Row.CUSTOMIZE: _open_customization()
		Row.BOTS: _change_bots(1, true)
		Row.START: _try_start()
		Row.BACK: _back_to_menu()
		Row.DISCORD:
			speaker_press.play()
			OS.shell_open(SplitMod.DISCORD_LINK)

func _join(device: int) -> void:
	if SplitMod.join(device):
		speaker_press.play()
		_refresh()
	elif SplitMod.players.size() >= SplitMod.MAX_PLAYERS:
		_show_message("THE TABLE IS FULL (4 PLAYERS)")

func _leave(device: int) -> void:
	if !SplitMod.is_joined(device):
		return
	SplitMod.leave(device)
	speaker_leave.play()
	_refresh()

## Left / right on the CPU PLAYERS row (or anywhere: it is the only setting changed that way).
## Confirming the row cycles through the values.
func _change_bots(dir: int, wrap := false) -> void:
	var free := SplitMod.MAX_PLAYERS - SplitMod.players.size()
	var current := SplitMod.bots_in_match()
	var value := current + dir
	if wrap: value = wrapi(value, 0, free + 1)
	value = clampi(value, 0, free)
	if value == current:
		return
	SplitMod.bot_count = value
	if selected != Row.BOTS:
		selected = Row.BOTS
	speaker_hover.pitch_scale = randf_range(0.95, 1.0)
	speaker_hover.play()
	_refresh()

func _try_start() -> void:
	if !SplitMod.can_start():
		_show_message("JOIN TO PLAY" if SplitMod.players.is_empty() else "ADD A CPU PLAYER OR LET SOMEONE JOIN")
		speaker_leave.play()
		return
	leaving = true
	speaker_music.stop()
	speaker_start.play()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var tween := create_tween()
	tween.tween_property(fader, "color:a", 1.0, 0.6)
	await get_tree().create_timer(1.6, false).timeout
	SplitMod.start_session()

func _open_customization() -> void:
	leaving = true
	speaker_music.stop()
	speaker_press.play()
	var tween := create_tween()
	tween.tween_property(fader, "color:a", 1.0, 0.5)
	await get_tree().create_timer(0.7, false).timeout
	SplitMod.open_customization()

func _back_to_menu() -> void:
	leaving = true
	speaker_music.stop()
	speaker_leave.play()
	var tween := create_tween()
	tween.tween_property(fader, "color:a", 1.0, 0.5)
	await get_tree().create_timer(0.7, false).timeout
	get_tree().change_scene_to_file(SplitMod.MENU_SCENE)


# ---------------------------------------------------------------- controllers coming and going

func _drop_disconnected_players() -> void:
	var connected := Input.get_connected_joypads()
	for p in SplitMod.players.duplicate():
		if p.device != SplitMod.DEVICE_KBM and !(p.device in connected):
			SplitMod.leave(p.device)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if !connected and SplitMod.is_joined(device):
		SplitMod.leave(device)
		_show_message("CONTROLLER %d DISCONNECTED" % (device + 1))
	_refresh()
