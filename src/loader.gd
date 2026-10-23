extends Node
## Buckshot Roulette - Local Splitscreen mod, core autoload ("SplitMod").
##
## Loaded through override.cfg before the main menu. It mounts splitscreen.pck, which holds
## patched copies of the multiplayer scripts plus the splitscreen lobby/session scenes.
##
## A splitscreen match runs one copy of the real multiplayer scene (mp_main) per local player,
## each inside its own SubViewport with its own 3D world. Player 1's copy is the host. The Steam
## P2P layer is replaced by an in-memory packet bus, so the match logic is exactly the online one.
## The patched scripts ask this node for anything that used to be process-global (local Steam ID,
## mouse cursor, audio buses, scene changes) and get the answer for their own player.

const MOD_VERSION := "1.0.0"
const GAME_VERSION := "__GAME_VERSION__"
const PACK_FILE := "splitscreen.pck"
const LOBBY_SCENE := "res://mods/splitscreen/split_lobby.tscn"
const SESSION_SCENE := "res://mods/splitscreen/split_session.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const MP_LOBBY_SCENE := "res://multiplayer/scenes/mp_lobby.tscn"
const MATCH_CUSTOMIZATION_SCRIPT := "res://multiplayer/scripts/global scripts/MP_MatchCustomization.gd"
const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const DEVICE_KBM := -1
const FIRST_LOCAL_ID := 1001
## md5 of every original game file the pack replaces, filled in by the build. If the game
## gets updated and any of them changes, the pack is not mounted and the game runs unmodded.
const ORIGINAL_MD5 := {
__ORIGINAL_MD5__
}

class Ctx:
	var index := 0
	var user_id := 0
	var name := ""
	var device := DEVICE_KBM
	var primary := false
	var owns_mouse := false
	var inbox : Array = []
	var cursor_state_after_toggle := false
	var lowpass_dummy : AudioEffect
	var view_rect := Rect2()

var enabled := false
var active := false
var ending := false
## Joined players, in seat order: {"device": int, "id": int, "name": String}
var players : Array = []
## True while the multiplayer lobby scene is open on its match customization screen for splitscreen.
var customizing := false
var lobby_message := ""
var contexts : Array = []
var _saved := {}


func _init() -> void:
	var dir := (get_script() as Script).resource_path.get_base_dir()
	for path in ORIGINAL_MD5:
		if FileAccess.get_md5(path) != ORIGINAL_MD5[path]:
			print("[splitscreen] game files differ from the version this mod was made for (", GAME_VERSION, "), mod disabled. changed file: ", path)
			return
	if !ProjectSettings.load_resource_pack(dir.path_join(PACK_FILE), true):
		print("[splitscreen] could not load ", dir.path_join(PACK_FILE), ", mod disabled")
		return
	enabled = true
	print("[splitscreen] mod ", MOD_VERSION, " loaded")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ---------------------------------------------------------------- lobby state

func is_joined(device: int) -> bool:
	return players.any(func(p): return p.device == device)

func join(device: int) -> bool:
	if players.size() >= MAX_PLAYERS or is_joined(device):
		return false
	players.append({"device": device, "id": 0, "name": ""})
	_renumber_players()
	return true

func leave(device: int) -> void:
	players = players.filter(func(p): return p.device != device)
	_renumber_players()

func _renumber_players() -> void:
	for i in players.size():
		players[i].id = FIRST_LOCAL_ID + i
		players[i].name = "PLAYER %d" % (i + 1)

func device_label(device: int) -> String:
	if device == DEVICE_KBM:
		return "KEYBOARD & MOUSE"
	return "CONTROLLER %d" % (device + 1)

## Opens the multiplayer lobby scene straight on its match customization screen (see the MP_LobbyUI patch).
## Saving or cancelling there comes back to the splitscreen lobby.
func open_customization() -> void:
	customizing = true
	GlobalVariables.message_to_forward = ""
	get_tree().change_scene_to_file(MP_LOBBY_SCENE)

## Steam lobby callbacks are ignored during a splitscreen match and on the customization screen.
func blocks_steam_lobby() -> bool:
	return active or customizing

## The settings a splitscreen match uses: the ones saved on the customization screen (shared with the
## online lobby, like in the game), else the game's defaults.
func match_settings() -> Dictionary:
	var stashed : Dictionary = GlobalVariables.stashed_match_customization_dictionary
	return (stashed if !stashed.is_empty() else _default_match_customization()).duplicate(true)

## Lines describing match_settings(), worded like the online lobby's customization summary.
func match_summary() -> Array:
	var node : Node = (load(MATCH_CUSTOMIZATION_SCRIPT) as Script).new()
	var default : Dictionary = node.default_customization_dictionary
	var m := match_settings()
	var lines := [tr("MP_UI NUMBER OF ROUNDS") + " " + str(m.number_of_rounds)]
	if m.skipping_intro: lines.append(tr("MP_UI SKIP INTRO"))
	if node.StartingHealthChanged(default, m): lines.append(tr("MP_UI STARTING HEALTH").replace(":", ""))
	if node.ItemDistributionChanged(default, m): lines.append(tr("MP_UI ITEM DISTRIBUTION").replace(":", ""))
	if node.ShellSequenceChanged(default, m): lines.append(tr("MP_UI SHELL SEQUENCE").replace(":", ""))
	node.free()
	return lines


# ---------------------------------------------------------------- session lifecycle

func start_session() -> void:
	if active or players.size() < MIN_PLAYERS:
		return
	contexts.clear()
	for i in players.size():
		var c := Ctx.new()
		c.index = i
		c.user_id = players[i].id
		c.name = players[i].name
		c.device = players[i].device
		c.primary = i == 0
		c.owns_mouse = players[i].device == DEVICE_KBM
		var lowpass := AudioServer.get_bus_effect(1, 0)
		c.lowpass_dummy = (lowpass.duplicate() as AudioEffect) if lowpass != null else AudioEffectLowPassFilter.new()
		contexts.append(c)
	_save_globals()
	_apply_globals()
	active = true
	ending = false
	print("[splitscreen] starting match with players: ", players)
	get_tree().change_scene_to_file(SESSION_SCENE)

## Called by the patched scripts (or the session) to leave the match and go back to the splitscreen lobby.
## The session tears the match copies down in stages first (see split_session.gd shutdown()).
func end_session(message: String = "", quitting := false) -> void:
	if !active or ending:
		return
	ending = true
	lobby_message = message
	print("[splitscreen] ending match: ", message)
	var session := get_tree().current_scene
	if session != null and session.has_method("shutdown"):
		session.shutdown(quitting)
	else:
		session_closed()
		if quitting: get_tree().quit()
		else: get_tree().change_scene_to_file(LOBBY_SCENE)

## Called once every match copy is gone: puts back everything the match changed.
func session_closed() -> void:
	if !active:
		return
	_restore_globals()
	contexts.clear()
	active = false
	ending = false
	get_tree().auto_accept_quit = true

func _save_globals() -> void:
	var buses := []
	for i in AudioServer.bus_count:
		buses.append(AudioServer.get_bus_volume_db(i))
	var lowpass = AudioServer.get_bus_effect(1, 0)
	_saved = {
		"host_id": GlobalSteam.HOST_ID,
		"lobby_members": GlobalSteam.LOBBY_MEMBERS.duplicate(true),
		"ignore": GlobalSteam.USER_ID_LIST_TO_IGNORE.duplicate(),
		"match": GlobalVariables.active_match_customization_dictionary.duplicate(true),
		"skipping_intro": GlobalVariables.skipping_intro,
		"round_end": GlobalVariables.debug_round_index_to_end_game_at,
		"short_intro": GlobalVariables.running_short_intro_in_lobby_scene,
		"disband": GlobalVariables.disband_lobby_after_exiting_main_scene,
		"cursor_state": GlobalVariables.cursor_state_after_toggle,
		"buses": buses,
		"lowpass": lowpass.cutoff_hz if lowpass != null and "cutoff_hz" in lowpass else -1.0,
	}

func _apply_globals() -> void:
	GlobalSteam.HOST_ID = contexts[0].user_id
	var members := []
	for c in contexts:
		members.append({"steam_id": c.user_id, "steam_name": c.name})
	GlobalSteam.LOBBY_MEMBERS = members
	GlobalSteam.USER_ID_LIST_TO_IGNORE.clear()
	# What the online host's lobby sets when a customized match starts.
	var m := match_settings()
	GlobalVariables.active_match_customization_dictionary = m
	GlobalVariables.skipping_intro = m.skipping_intro
	GlobalVariables.debug_round_index_to_end_game_at = m.number_of_rounds - 1
	GlobalVariables.message_to_forward = ""
	GlobalVariables.disband_lobby_after_exiting_main_scene = false

func _restore_globals() -> void:
	GlobalSteam.HOST_ID = _saved.host_id
	GlobalSteam.LOBBY_MEMBERS = _saved.lobby_members
	GlobalSteam.USER_ID_LIST_TO_IGNORE.clear()
	GlobalSteam.USER_ID_LIST_TO_IGNORE.append_array(_saved.ignore)
	GlobalVariables.active_match_customization_dictionary = _saved.match
	GlobalVariables.skipping_intro = _saved.skipping_intro
	GlobalVariables.debug_round_index_to_end_game_at = _saved.round_end
	GlobalVariables.running_short_intro_in_lobby_scene = _saved.short_intro
	GlobalVariables.disband_lobby_after_exiting_main_scene = _saved.disband
	GlobalVariables.cursor_state_after_toggle = _saved.cursor_state
	GlobalVariables.message_to_forward = ""
	for i in mini(_saved.buses.size(), AudioServer.bus_count):
		AudioServer.set_bus_volume_db(i, _saved.buses[i])
	var lowpass = AudioServer.get_bus_effect(1, 0)
	if _saved.lowpass >= 0.0 and lowpass != null:
		lowpass.cutoff_hz = _saved.lowpass

func _default_match_customization() -> Dictionary:
	var script : Script = load(MATCH_CUSTOMIZATION_SCRIPT)
	var node : Node = script.new()
	var d : Dictionary = node.default_customization_dictionary.duplicate(true)
	node.free()
	return d


# ---------------------------------------------------------------- per-player context

## The context of the splitscreen player whose match copy `node` belongs to, or null outside a session.
func ctx_of(node: Node) -> Ctx:
	if !active or node == null or !node.is_inside_tree():
		return null
	var vp := node.get_viewport()
	while vp != null:
		if vp.has_meta(&"split_ctx"):
			return contexts[vp.get_meta(&"split_ctx")]
		var parent := vp.get_parent()
		if parent == null:
			return null
		vp = parent.get_viewport()
	return null

## Replaces GlobalSteam.STEAM_ID: the local player's ID for this match copy.
func sid(node: Node) -> int:
	var c := ctx_of(node)
	return c.user_id if c != null else GlobalSteam.STEAM_ID

## Replaces GlobalVariables for values that belong to one local player.
func gv(node: Node):
	var c := ctx_of(node)
	return c if c != null else GlobalVariables

## Replaces get_node("/root/mp_main/..."): the mp_main this node belongs to.
func mp_root(node: Node) -> Node:
	var n := node
	while n != null:
		if n.name == &"mp_main" and n.get_parent() is Viewport:
			return n
		n = n.get_parent()
	return get_tree().root.get_node_or_null(^"mp_main")

func persona_name(id) -> String:
	if active:
		for c in contexts:
			if c.user_id == int(id):
				return c.name
		return "N/A"
	return Steam.getFriendPersonaName(id)

func get_player_avatar(size: int, id) -> void:
	if active:
		return
	Steam.getPlayerAvatar(size, id)

func change_scene(node: Node, path: String) -> void:
	if active:
		var message : String = GlobalVariables.message_to_forward
		GlobalVariables.message_to_forward = ""
		end_session(message)
		return
	node.get_tree().change_scene_to_file(path)

## During a session every patched script runs inside a player's view; a call from a node outside of one
## (out of the tree) must not reach the real cursor or audio buses.
func _detached(c: Ctx) -> bool:
	return active and c == null


# ---------------------------------------------------------------- mouse

func set_mouse_mode(node: Node, mode) -> void:
	var c := ctx_of(node)
	if _detached(c):
		return
	if c == null:
		Input.set_mouse_mode(mode)
		return
	if !c.owns_mouse:
		return
	var was_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(mode)
	if was_captured and mode != Input.MOUSE_MODE_CAPTURED and c.view_rect.has_area():
		Input.warp_mouse(c.view_rect.get_center())

func set_custom_mouse_cursor(node: Node, image, shape = Input.CURSOR_ARROW, hotspot = Vector2.ZERO) -> void:
	var c := ctx_of(node)
	if _detached(c) or (c != null and !c.owns_mouse):
		return
	Input.set_custom_mouse_cursor(image, shape, hotspot)


# ---------------------------------------------------------------- audio (only player 1's copy is heard)

func set_bus_volume_db(node: Node, bus: int, db: float) -> void:
	var c := ctx_of(node)
	if _detached(c) or (c != null and !c.primary):
		return
	AudioServer.set_bus_volume_db(bus, db)

func get_bus_effect(node: Node, bus: int, effect: int) -> AudioEffect:
	var c := ctx_of(node)
	if _detached(c):
		return AudioEffectLowPassFilter.new()
	if c != null and !c.primary:
		return c.lowpass_dummy
	return AudioServer.get_bus_effect(bus, effect)


# ---------------------------------------------------------------- packets

## Replaces Steam.sendP2PPacket: target 0 = every other player, otherwise the player with that ID.
func send_packet(node: Node, target: int, data: Dictionary) -> void:
	var from := ctx_of(node)
	if from == null:
		return
	var bytes := var_to_bytes(data)
	for c in contexts:
		if c != from and (target == 0 or c.user_id == target):
			c.inbox.append([from.user_id, bytes])

## Replaces Steam.readP2PPacket: [sender_id, bytes] or null.
func pop_packet(node: Node):
	var c := ctx_of(node)
	if c == null or c.inbox.is_empty():
		return null
	return c.inbox.pop_front()
