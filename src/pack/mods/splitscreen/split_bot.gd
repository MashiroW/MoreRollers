extends Node
## A CPU player. It sits in a seat of its own like any other client: a hidden copy of the match whose
## local player it drives through the same calls the mouse and controller prompts make, so the host
## checks and plays its moves exactly like a human's.
##
## Its play is the single-player Dealer's, adapted to a table of 2 to 4: magnifying glass first,
## cigarettes when hurt, beer to clear doubt, handsaw on a live shell, inverter on a blank, the jammer
## in place of the handcuffs, adrenaline to steal what it needs. It is sharper than the Dealer: it counts
## the shells that went out, reasons on the odds instead of flipping a coin, finishes off the weakest
## opponent and never wastes a saw on a 1-health target. It only knows what a player in its seat would:
## the shells shown at loading, the shells that went out, and what its own magnifying glass and burner
## phone told it. Other players' magnifying glasses and phones stay secret to it.

const ID_HANDSAW := 1
const ID_MAGNIFIER := 2
const ID_JAMMER := 3
const ID_CIGARETTES := 4
const ID_BEER := 5
const ID_PHONE := 6
const ID_ADRENALINE := 8
const ID_INVERTER := 9
const ID_REMOTE := 10
## Seconds between two moves, like the Dealer taking a moment before each action.
const THINK_TIME := Vector2(0.9, 1.7)
## A request the host turned down leaves the copy's controls locked; after this long they are given back.
const REFUSED_AFTER := 6.0

var ctx
var vp : SubViewport
## Player 1's view, whose copy is the host that checks every request.
var host_vp : SubViewport
var busy := false
var next_move := 0.0
var planned_target := -1
## Optional extra destination for the decision log (the test driver writes it to a file).
var log_sink : Callable
var _turn_since := -1.0
var _stall_reported := false

# What the bot knows about the shells in the shotgun.
var lives := 0
var blanks := 0
## Known shell types, index 0 = the chamber. "" = unknown.
var known : Array = []
## Number of times the chamber shell was inverted since it got there (only the parity matters).
var chamber_flips := 0


func setup(context, viewport: SubViewport, host_viewport: SubViewport) -> void:
	ctx = context
	vp = viewport
	host_vp = host_viewport
	name = "bot_%d" % (context.index + 1)


# ---------------------------------------------------------------- what the bot sees

## Every packet its copy receives from the host goes through here first (see SplitMod.observe_packet).
func observe(packet: Dictionary) -> void:
	var p = _props()
	match packet.get("packet alias", ""):
		"load shotgun routine":
			var visible : Array = packet.sequence_dictionary.get("sequence_visible", [])
			lives = visible.count("live")
			blanks = visible.count("blank")
			known.clear()
			known.resize(lives + blanks)
			known.fill("")
			chamber_flips = 0
		"shoot user":
			_shell_out(packet.shooter_shell)
		"interact with item":
			var mine : bool = p != null and int(packet.socket_number) == p.socket_number
			match int(packet.item_id):
				ID_MAGNIFIER:
					if mine and !known.is_empty(): known[0] = packet.current_shell_in_chamber
				ID_PHONE:
					if mine and str(packet.phone_verbal_shell) != "":
						var i := int(packet.phone_verbal_index) - 1
						if i >= 0 and i < known.size(): known[i] = packet.phone_verbal_shell
				ID_BEER:
					# The racked shell drops on the table for everyone to see.
					_shell_out(packet.current_shell_in_chamber)
				ID_INVERTER:
					chamber_flips += 1
					if !known.is_empty() and known[0] != "":
						known[0] = _other(known[0])

func _shell_out(shell: String) -> void:
	var original := shell if chamber_flips % 2 == 0 else _other(shell)
	if original == "live": lives = maxi(lives - 1, 0)
	else: blanks = maxi(blanks - 1, 0)
	if !known.is_empty(): known.pop_front()
	chamber_flips = 0

func _other(shell: String) -> String:
	return "blank" if shell == "live" else "live"

func _shells_left() -> int:
	return lives + blanks

## The chamber shell if the bot knows it, else "".
func _chamber() -> String:
	if known.is_empty(): return ""
	if known[0] != "": return known[0]
	var p := _chamber_live_odds()
	if p >= 1.0: return "live"
	if p <= 0.0: return "blank"
	return ""

## Chance that the chamber shell is live, from the shells left that it doesn't know the place of.
func _chamber_live_odds() -> float:
	if !known.is_empty() and known[0] != "":
		return 1.0 if known[0] == "live" else 0.0
	var l := lives
	var b := blanks
	for i in range(1, known.size()):
		if known[i] == "live": l -= 1
		elif known[i] == "blank": b -= 1
	var odds := 0.5 if l + b <= 0 else clampf(float(l) / float(l + b), 0.0, 1.0)
	return odds if chamber_flips % 2 == 0 else 1.0 - odds


# ---------------------------------------------------------------- the copy it plays in

func _inter():
	if vp == null or vp.get_child_count() == 0: return null
	return vp.get_child(0).get_node_or_null("standalone managers/interactions/interaction intermediary")

func _props():
	var inter = _inter()
	return inter.intermed_properties if inter != null else null

## This seat as the host's copy sees it. Each copy plays the animations at its own pace (first person
## here, third person there), so a request sent the moment this copy is done could reach a host that is
## not done yet and be refused, which would leave the seat stuck: requests wait for the host.
func _host_seat(p):
	if host_vp == null or host_vp.get_child_count() == 0: return null
	var inter = host_vp.get_child(0).get_node_or_null("standalone managers/interactions/interaction intermediary")
	return inter.game_state.GetSocketProperties(p.socket_number) if inter != null else null

func _host_ready(p, action: String) -> bool:
	var h = _host_seat(p)
	if h == null: return false
	match action:
		"grab": return h.is_grabbing_items and !h.is_holding_item_to_place
		"place": return h.is_grabbing_items and h.is_holding_item_to_place
		"turn": return h.has_turn and !h.is_holding_shotgun and !h.is_interacting_with_item and !h.is_on_secondary_interaction
		"shoot": return h.is_holding_shotgun and h.has_turn
		"steal": return h.is_stealing_item and h.has_turn
		"jam": return h.is_viewing_jammer and h.has_turn
	return true

func _opponents(p) -> Array:
	var list := []
	for other in _inter().instance_handler.instance_property_array:
		if other != p and other.health_current > 0:
			list.append(other)
	return list

## [branch, item_id] for every item of its own it may use right now.
func _usable_items(p) -> Array:
	var list := []
	for item in p.user_inventory_instance_array:
		if item == null or !is_instance_valid(item) or item.get_child_count() < 2: continue
		var branch = item.get_child(1)
		if branch.interactionAllowed and !branch.interactionInvalid:
			list.append([branch, branch.item_id])
	return list

func _items_of(socket: int) -> int:
	var count := 0
	for slot in _inter().game_state.MAIN_inventory_by_socket[socket]:
		if slot != {}: count += 1
	return count

## How dangerous a player looks: health first, then the items in front of them.
func _threat(other) -> float:
	return other.health_current * 10.0 + _items_of(other.socket_number)


# ---------------------------------------------------------------- main loop

func _process(_delta: float) -> void:
	if busy or !SplitMod.active or SplitMod.ending:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < next_move:
		return
	var p = _props()
	var inter = _inter()
	if p == null or inter == null or inter.game_state == null:
		return
	busy = true
	var acted : bool = await _step(p, inter)
	busy = false
	if acted:
		next_move = Time.get_ticks_msec() / 1000.0 + randf_range(THINK_TIME.x, THINK_TIME.y)
	_watch(p, inter, acted)

## Reports (once) a turn where the bot has the shotgun's turn and does nothing for a long time.
func _watch(p, inter, acted: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var mine : bool = inter.game_state.MAIN_active_current_turn_socket == p.socket_number and p.has_turn
	if !mine or acted:
		_turn_since = now if mine else -1.0
		_stall_reported = false
		return
	if _turn_since < 0.0:
		_turn_since = now
	# Controls locked while the host still gives this seat the turn and nothing is going on: a request
	# was refused. Give the controls back, as the game does at the end of a move.
	var h = _host_seat(p)
	if now - _turn_since > REFUSED_AFTER and !inter.intbranch_shotgun.interactionAllowed and h != null and h.has_turn 			and !h.is_holding_shotgun and !h.is_interacting_with_item and !h.is_on_secondary_interaction and !h.is_stealing_item 			and !p.is_holding_shotgun and !p.is_interacting_with_item and !p.is_on_secondary_interaction:
		_log("a request was turned down, taking the controls back")
		p.permissions.SetMainPermission(true)
		_turn_since = now
		return
	if now - _turn_since > 20.0 and !_stall_reported:
		_stall_reported = true
		_log("has had the turn for 20 s without a move: perm=%s shotgun_allowed=%s holding=%s checking=%s item=%s secondary=%s jammer=%s stealing=%s" % [
			p.major_permission_enabled, inter.intbranch_shotgun.interactionAllowed, p.is_holding_shotgun, p.look_manager.checking,
			p.is_interacting_with_item, p.is_on_secondary_interaction, p.is_on_jammer_selection, p.is_stealing_item])

func _step(p, inter) -> bool:
	var gs = inter.game_state
	# Choosing who to jam.
	if p.is_on_jammer_selection:
		return await _jam(p) if _host_ready(p, "jam") else false
	# Picking the item to steal with adrenaline.
	if p.is_stealing_item and p.has_turn and p.major_permission_enabled:
		return _steal(p, inter) if _host_ready(p, "steal") else false
	# Item distribution: take from the briefcase, put it on the table. Decided from what can be clicked:
	# is_grabbing_items stays true on clients once distribution is over (like online).
	if _distribute(p):
		return true
	# Holding the shotgun, the target screen is up.
	if p.is_holding_shotgun and p.look_manager.checking:
		if !_host_ready(p, "shoot"): return false
		var target := planned_target if planned_target != -1 else _pick_target(p, inter)
		planned_target = -1
		_log("shoots %s (live odds %.2f, %d live / %d blank left)" % ["itself" if target == p.socket_number else "seat %d" % target, _chamber_live_odds(), lives, blanks])
		p.shotgun.Shoot(null, target)
		return true
	# Its turn, hands free.
	if gs.MAIN_active_current_turn_socket == p.socket_number and p.has_turn and p.major_permission_enabled \
			and !p.is_holding_shotgun and !p.is_interacting_with_item and !p.is_on_secondary_interaction \
			and inter.intbranch_shotgun.interactionAllowed:
		return _take_turn(p, inter) if _host_ready(p, "turn") else false
	return false

func _distribute(p) -> bool:
	var im = p.item_manager
	if !p.is_holding_item_to_place:
		if im.intbranch_intake.interactionAllowed and !p.is_holding_shotgun and _host_ready(p, "grab"):
			p.interaction.InteractWith("item briefcase intake", im.intbranch_intake)
			return true
		return false
	var free := []
	for g in im.intbranch_grid_colliders:
		if g.interactionAllowed and p.user_inventory[g.grid_index] == {}:
			free.append(g)
	if free.is_empty() or !_host_ready(p, "place"):
		return false
	p.interaction.InteractWith("item grid", free[randi() % free.size()])
	return true


# ---------------------------------------------------------------- decisions

func _take_turn(p, inter) -> bool:
	var items := _usable_items(p)
	var choice = _pick_item(p, inter, items)
	if choice != null:
		_log("uses item %d (chamber %s, live odds %.2f)" % [choice.item_id, _chamber() if _chamber() != "" else "unknown", _chamber_live_odds()])
		p.interaction.InteractWith("item", choice)
		return true
	planned_target = _pick_target(p, inter)
	p.interaction.InteractWith("shotgun", inter.intbranch_shotgun)
	return true

func _has(items: Array, id: int):
	for entry in items:
		if entry[1] == id: return entry[0]
	return null

## The item it wants to use now, in the Dealer's order of priority, or null to go for the shotgun.
func _pick_item(p, inter, items: Array):
	for id in _wanted_items(p, inter):
		var branch = _has(items, id)
		if branch != null:
			return branch
	# Adrenaline: steal the best thing someone else has, if anything is worth it.
	var adrenaline = _has(items, ID_ADRENALINE)
	if adrenaline != null and _best_steal(p, inter) != null:
		return adrenaline
	return null

## Item ids it would use right now, most wanted first.
func _wanted_items(p, inter) -> Array:
	var gs = inter.game_state
	var wanted := []
	var left := _shells_left()
	var chamber := _chamber()
	var odds := _chamber_live_odds()
	var opponents := _opponents(p)
	if chamber == "" and left > 1:
		wanted.append(ID_MAGNIFIER)
	if p.health_current < p.health_on_round_start:
		wanted.append(ID_CIGARETTES)
	if left > 2 and known.count("") > 1:
		wanted.append(ID_PHONE)
	if left > 1 and opponents.size() > 0 and _jam_target(p) != "":
		wanted.append(ID_JAMMER)
	# Beer clears a doubt; a known blank is better shot at itself (it keeps the turn), a known live at someone.
	if chamber == "" and left > 1 and odds < 0.65:
		wanted.append(ID_BEER)
	if chamber == "blank" or (chamber == "" and odds <= 0.3):
		wanted.append(ID_INVERTER)
	if !gs.MAIN_barrel_sawed_off and (chamber == "live" or (chamber == "" and odds >= 0.5)):
		var target = _target_props(p, inter, _pick_opponent(p, 2))
		if target != null and target.health_current >= 2:
			wanted.append(ID_HANDSAW)
	if opponents.size() >= 2 and _remote_helps(p, inter):
		wanted.append(ID_REMOTE)
	return wanted

## Who to shoot: the chamber shell decides between itself and an opponent.
func _pick_target(p, inter) -> int:
	var odds := _chamber_live_odds()
	var shoot_self := false
	if odds <= 0.0: shoot_self = true
	elif odds >= 1.0: shoot_self = false
	elif odds < 0.5: shoot_self = p.health_current > 1 or odds < 0.2
	elif odds == 0.5: shoot_self = p.health_current > 2 and randf() < 0.5
	var damage := 2 if inter.game_state.MAIN_barrel_sawed_off else 1
	if !shoot_self:
		var target := _pick_opponent(p, damage)
		if target != -1: return target
	return p.socket_number

## The opponent to aim at: one it can finish now if any, else the most dangerous one.
func _pick_opponent(p, damage: int) -> int:
	var opponents := _opponents(p)
	if opponents.is_empty(): return -1
	var killable := opponents.filter(func(o): return o.health_current <= damage)
	var pool := killable if !killable.is_empty() else opponents
	pool.shuffle()
	pool.sort_custom(func(a, b):
		if killable.is_empty(): return _threat(a) > _threat(b)
		return _items_of(a.socket_number) > _items_of(b.socket_number))
	return pool[0].socket_number

func _target_props(p, inter, socket: int):
	return inter.game_state.GetSocketProperties(socket) if socket != -1 else null

## The remote flips the turn order: worth it when the player about to get the shotgun next is more
## dangerous than the one on the other side.
func _remote_helps(p, inter) -> bool:
	var alive := []
	for other in inter.instance_handler.instance_property_array:
		if other.health_current > 0 or other == p: alive.append(other.socket_number)
	alive.sort()
	if alive.size() < 3: return false
	var i := alive.find(p.socket_number)
	var cw = inter.game_state.GetSocketProperties(alive[(i + 1) % alive.size()])
	var ccw = inter.game_state.GetSocketProperties(alive[(i - 1 + alive.size()) % alive.size()])
	var next = cw if inter.game_state.MAIN_active_turn_order == "CW" else ccw
	var other = ccw if next == cw else cw
	return _threat(next) > _threat(other) + 5.0


# ---------------------------------------------------------------- item follow-ups

## Direction ("left", "forward", "right") of the opponent to jam, or "" if nobody can be jammed.
func _jam_target(p) -> String:
	var best = null
	for other in _opponents(p):
		if other.is_jammed: continue
		if best == null or _threat(other) > _threat(best):
			best = other
	return p.GetDirection(p.socket_number, best.socket_number) if best != null else ""

func _jam(p) -> bool:
	var jammer = p.item_interaction.jammer
	var direction := _jam_target(p)
	if direction == "" or direction == "self":
		# Nobody left to jam: pick the first valid key the jammer shows.
		var keys := ["left", "forward", "right"]
		for k in keys.size():
			if jammer.valid_target_array[k]:
				direction = keys[k]
				break
	if direction == "":
		return false
	_log("jams " + direction)
	jammer.GetInput(direction)
	await get_tree().create_timer(0.6, false).timeout
	if !is_inside_tree() or !p.is_on_jammer_selection: return true
	jammer.GetInput("confirm")
	return true

## Order in which stolen items are worth taking: a saw on a coming live shell first, then information.
const STEAL_ORDER := [ID_HANDSAW, ID_MAGNIFIER, ID_CIGARETTES, ID_JAMMER, ID_INVERTER, ID_BEER, ID_PHONE, ID_REMOTE]
## Items that never hurt the thief when nothing better can be taken (an inverter or a beer could).
const HARMLESS_ORDER := [ID_CIGARETTES, ID_MAGNIFIER, ID_PHONE, ID_JAMMER, ID_REMOTE, ID_HANDSAW, ID_BEER, ID_INVERTER]

## Branch of the item it would take from another player, or null.
func _best_steal(p, inter):
	var wanted := STEAL_ORDER.filter(func(id): return id in _wanted_items(p, inter))
	var best = null
	var best_rank := 999
	for socket in 4:
		if socket == p.socket_number: continue
		for slot in inter.game_state.MAIN_inventory_by_socket[socket]:
			if slot == {} or !is_instance_valid(slot.item_instance): continue
			var id := int(slot.item_id)
			if id == ID_ADRENALINE: continue
			var rank := wanted.find(id)
			if rank != -1 and rank < best_rank:
				best_rank = rank
				best = slot.item_instance.get_child(1)
	return best

func _steal(p, inter) -> bool:
	var branch = _best_steal(p, inter)
	if branch == null or !branch.interactionAllowed or branch.interactionInvalid:
		# Nothing it wanted is allowed any more: take the least risky item so the turn goes on.
		branch = null
		var best_rank := 999
		for socket in 4:
			if socket == p.socket_number: continue
			for slot in inter.game_state.MAIN_inventory_by_socket[socket]:
				if slot == {} or !is_instance_valid(slot.item_instance): continue
				var b = slot.item_instance.get_child(1)
				var rank := HARMLESS_ORDER.find(int(b.item_id))
				if rank == -1: rank = HARMLESS_ORDER.size()
				if b.interactionAllowed and !b.interactionInvalid and rank < best_rank:
					best_rank = rank
					branch = b
	if branch == null:
		return false
	_log("steals item %d" % branch.item_id)
	p.interaction.InteractWith("item", branch)
	return true

func _log(text: String) -> void:
	var line := "[splitscreen] %s: %s" % [ctx.name, text]
	print(line)
	if log_sink.is_valid():
		log_sink.call(line)
