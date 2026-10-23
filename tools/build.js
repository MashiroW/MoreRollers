// Builds the splitscreen mod from the installed game:
//   mod/loader.gd        autoload, with md5s of the replaced originals
//   mod/splitscreen.pck  patched game scripts + src/pack/**
// The original scripts are read straight from the game's embedded pack (into build/original),
// so no game file is ever stored in the repo.
// usage: node tools/build.js ["path/to/Buckshot Roulette.exe"]
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const { readPck } = require('./pck');

const root = path.resolve(__dirname, '..');
const gameExe = process.argv[2] || 'C:/Program Files (x86)/Steam/steamapps/common/Buckshot Roulette/Buckshot Roulette_windows/Buckshot Roulette.exe';
const GAME_VERSION = 'v2.2.0.6';
const orig = path.join(root, 'build', 'original');
const stage = path.join(root, 'build', 'stage');
const dist = path.join(root, 'mod');

const read = (res) => fs.readFileSync(path.join(orig, res.replace('res://', '')), 'utf8');
const md5 = (buf) => crypto.createHash('md5').update(buf).digest('hex');

function replaceExact(text, find, repl, expected, label) {
  const n = text.split(find).length - 1;
  if (n !== expected) throw new Error(`${label}: expected ${expected} match(es) of ${JSON.stringify(find)}, found ${n}`);
  return text.split(find).join(repl);
}

// Process-global calls that must answer for the local player of each match copy.
const GENERIC = [
  ['GlobalSteam.STEAM_ID', 'SplitMod.sid(self)'],
  ['get_node("/root/mp_main/', 'SplitMod.mp_root(self).get_node("'],
  ['Input.set_mouse_mode(', 'SplitMod.set_mouse_mode(self, '],
  ['Input.set_custom_mouse_cursor(', 'SplitMod.set_custom_mouse_cursor(self, '],
  ['AudioServer.set_bus_volume_db(', 'SplitMod.set_bus_volume_db(self, '],
  ['AudioServer.get_bus_effect(', 'SplitMod.get_bus_effect(self, '],
  ['Steam.getFriendPersonaName(', 'SplitMod.persona_name('],
  ['Steam.getPlayerAvatar(', 'SplitMod.get_player_avatar('],
  ['GlobalVariables.cursor_state_after_toggle', 'SplitMod.gv(self).cursor_state_after_toggle'],
];

const GUARD = '\tif SplitMod.blocks_steam_lobby(): return\n';

// File-specific edits, applied to the original text before the generic ones.
const SPECIFIC = {
  'res://multiplayer/scripts/MP_PacketManager.gd': [
    ['\tif GlobalSteam.LOBBY_ID > 0:\n\t\tread_p2p_packet()\n',
     '\tif GlobalSteam.LOBBY_ID > 0:\n\t\tread_p2p_packet()\n\telif SplitMod.active:\n\t\tsplit_read_p2p_packet()\n', 1],
    ['func send_p2p_packet(target: int, packet_data: Dictionary) -> void:\n\tif GlobalVariables.mp_debugging: return\n',
     'func send_p2p_packet(target: int, packet_data: Dictionary) -> void:\n\tif GlobalVariables.mp_debugging: return\n\tif SplitMod.active:\n\t\tSplitMod.send_packet(self, target, packet_data)\n\t\treturn\n', 1],
    ['\t\t"host arrived in main scene":\n\t\t\tlobbyController.StartGameRoutine_LoadScene()',
     '\t\t"host arrived in main scene":\n\t\t\tif lobbyController != null: lobbyController.StartGameRoutine_LoadScene()', 1],
    ['func _on_p2p_session_request(remote_id: int) -> void:\n',
     'func _on_p2p_session_request(remote_id: int) -> void:\n' + GUARD, 1],
    [null, `
# splitscreen: same checks as read_p2p_packet, reading from the local packet bus instead of Steam
func split_read_p2p_packet() -> void:
	var entry = SplitMod.pop_packet(self)
	if entry == null: return
	var packet_sender: int = entry[0]
	var readable_data: Dictionary = bytes_to_var(entry[1])
	if GlobalSteam.STEAM_ID != GlobalSteam.HOST_ID:
		if packet_sender != GlobalSteam.HOST_ID:
			print("packet refused: received packet from non-host user.")
			return
	if packet_sender in GlobalSteam.USER_ID_LIST_TO_IGNORE:
		print("packet refused: received packet from an ID that is set to be ignored.")
		return
	if GlobalVariables.printing_packets:
		print("received packet: ", readable_data)
	temp_id = packet_sender
	PipeData(readable_data)
`, 0],
  ],
  'res://multiplayer/scripts/MP_LobbyManager.gd': [
    ['func _on_lobby_created(connect: int, this_lobby_id: int) -> void:\n', 'func _on_lobby_created(connect: int, this_lobby_id: int) -> void:\n' + GUARD, 1],
    ['func _on_Lobby_Join_Requested(this_lobby_id: int, friend_id: int) -> void:\n', 'func _on_Lobby_Join_Requested(this_lobby_id: int, friend_id: int) -> void:\n' + GUARD, 1],
    ['func join_lobby(this_lobby_id: int) -> void:\n', 'func join_lobby(this_lobby_id: int) -> void:\n' + GUARD, 1],
    ['func leave_lobby() -> void:\n', 'func leave_lobby() -> void:\n' + GUARD, 1],
    ['func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:\n',
     'func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:\n' + GUARD, 1],
    ['func get_lobby_members() -> void:\n', 'func get_lobby_members() -> void:\n' + GUARD, 1],
  ],
  'res://multiplayer/scripts/global scripts/MP_IngameLobbyUI.gd': [
    ['\tif GlobalSteam.STEAM_ID == GlobalSteam.HOST_ID:\n\t\tfor segment in segment_array:\n\t\t\tsegment.ui_kick.visible = false\n',
     '\tif GlobalSteam.STEAM_ID == GlobalSteam.HOST_ID and !SplitMod.active:\n\t\tfor segment in segment_array:\n\t\t\tsegment.ui_kick.visible = false\n', 1],
  ],
  'res://multiplayer/scripts/global scripts/MP_UserInstanceHandler.gd': [
    ['func GetRoot():\n', 'func GetRoot():\n\tif SplitMod.active:\n\t\tscene_root = SplitMod.mp_root(self)\n\t\treturn\n', 1],
  ],
  'res://multiplayer/scripts/global scripts/MP_InteractionIntermediary.gd': [
    ['\tget_tree().change_scene_to_file("res://multiplayer/scenes/mp_lobby.tscn")', '\tSplitMod.change_scene(self, "res://multiplayer/scenes/mp_lobby.tscn")', 1],
  ],
  // Opened from the splitscreen lobby, the multiplayer lobby goes straight to its customization screen.
  'res://multiplayer/scripts/global scripts/MP_LobbyUI.gd': [
    ['\tcursor.SetCursor(false, false)\n\tUpdatePlayerList()\n',
     '\tcursor.SetCursor(false, false)\n\tUpdatePlayerList()\n\tif SplitMod.customizing:\n\t\tSetWidth()\n\t\tmatch_customization.ClearMatchCustomizationUI()\n\t\tSplitCustomizeIntro()\n\t\treturn\n', 1],
    ['func ExitMatchCustomization():\n',
     'func ExitMatchCustomization():\n\tif SplitMod.customizing:\n\t\tSplitReturnFromCustomization()\n\t\treturn\n', 1],
    [null, fs.readFileSync(path.join(root, 'src', 'lobby_ui_additions.gd'), 'utf8'), 0],
  ],
  'res://scripts/MenuManager.gd': [
    ['\tbuttons[22].connect("is_pressed", StartMultiplayer)\n', '\tbuttons[22].connect("is_pressed", StartMultiplayer)\n\t_splitscreen_add_button()\n', 1],
    [null, fs.readFileSync(path.join(root, 'src', 'menu_additions.gd'), 'utf8'), 0],
  ],
};

// Every script used by the multiplayer match (mp_main.tscn and its sub-scenes) gets the generic edits.
const matchScripts = fs.readFileSync(path.join(root, 'tools', 'mp_main_scripts.txt'), 'utf8').split(/\r?\n/).filter(Boolean);
const files = new Set([...matchScripts, ...Object.keys(SPECIFIC)]);

fs.rmSync(path.join(root, 'build'), { recursive: true, force: true });
fs.mkdirSync(stage, { recursive: true });
fs.mkdirSync(dist, { recursive: true });

if (!fs.existsSync(gameExe)) throw new Error(`game not found: ${gameExe} (pass the path to "Buckshot Roulette.exe")`);
const pck = readPck(gameExe);
for (const res of files) {
  const entry = pck.entries.find((e) => e.name === res);
  if (!entry) throw new Error(`${res} is not in the game pack (game updated?)`);
  const buf = Buffer.alloc(entry.size);
  fs.readSync(pck.fd, buf, 0, entry.size, entry.ofs);
  const out = path.join(orig, res.replace('res://', ''));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, buf);
}
fs.closeSync(pck.fd);

const originals = {};
const report = [];
for (const res of [...files].sort()) {
  const original = read(res);
  let text = original.replace(/\r\n/g, '\n');
  for (const [find, repl, count] of SPECIFIC[res] || []) {
    if (find === null) text = text.replace(/\n*$/, '\n') + repl;
    else text = replaceExact(text, find, repl, count, res);
  }
  if (matchScripts.includes(res)) {
    for (const [find, repl] of GENERIC) text = text.split(find).join(repl);
  }
  if (text === original) continue;
  const out = path.join(stage, res.replace('res://', ''));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, text);
  originals[res] = md5(fs.readFileSync(path.join(orig, res.replace('res://', ''))));
  report.push(res);
}

// Leftovers in the match scripts would mean a patch was missed.
for (const res of report.filter((r) => matchScripts.includes(r))) {
  const text = fs.readFileSync(path.join(stage, res.replace('res://', '')), 'utf8');
  for (const bad of ['GlobalSteam.STEAM_ID', '/root/mp_main', 'Input.set_mouse_mode', 'AudioServer.set_bus_volume_db', 'Steam.getFriendPersonaName']) {
    if (text.includes(bad)) {
      throw new Error(`${res} still contains ${bad}`);
    }
  }
}

// New files (splitscreen lobby/session scenes and scripts).
function copyTree(src, dst) {
  for (const name of fs.readdirSync(src)) {
    const s = path.join(src, name), d = path.join(dst, name);
    if (fs.statSync(s).isDirectory()) { fs.mkdirSync(d, { recursive: true }); copyTree(s, d); }
    else fs.copyFileSync(s, d);
  }
}
copyTree(path.join(root, 'src', 'pack'), stage);

const md5Lines = Object.entries(originals).map(([k, v]) => `\t"${k}": "${v}",`).join('\n');
const loader = fs.readFileSync(path.join(root, 'src', 'loader.gd'), 'utf8')
  .replace('__ORIGINAL_MD5__', md5Lines)
  .replace('__GAME_VERSION__', GAME_VERSION);
fs.writeFileSync(path.join(dist, 'loader.gd'), loader);

execFileSync(process.execPath, [path.join(root, 'tools', 'mkpck.js'), stage, path.join(dist, 'splitscreen.pck')], { stdio: 'inherit' });
console.log(`patched ${report.length} game scripts:\n  ` + report.join('\n  '));
