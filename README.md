![MoreRollers](./res/banner.png?raw=true "MoreRollers")

# MoreRollers - Local Splitscreen for Buckshot Roulette
*A mod that adds **local splitscreen multiplayer** to **Buckshot Roulette**: 2 to 4 players on a single PC, each with their own view, playing the game's real multiplayer match.*

---

## 📌 What it does

MoreRollers adds a **LOCAL SPLITSCREEN** entry to the main menu, right under MULTIPLAYER.

The mod does not rewrite the game. It runs the **official multiplayer mode**, one copy per player, linked together as if they were playing online. You get exactly the same table, items, rules and results screen as an online match, plus the original match customization menu.

| | |
|---|---|
| Game version | v2.2.0.6 (Steam, Windows) |
| Players | 2 to 4: one on keyboard & mouse, the others on controllers |
| Game files modified | none |

---

## 📥 Installation

1. Close the game.
2. Double-click **`Install.bat`**.
   The game is found automatically through your Steam libraries. If it isn't, the installer asks for its folder, which you can also pass directly:
   ```
   Install.bat "D:\SteamLibrary\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows"
   ```
3. Start the game from Steam as usual. **LOCAL SPLITSCREEN** is now in the main menu.

What the installer does:
- copies `mod\loader.gd` and `mod\splitscreen.pck` to `<game folder>\splitscreen_mod\`;
- adds a `SplitMod=...` line to `<game folder>\override.cfg`. The file is created if it doesn't exist. If it already holds other settings, they are kept and the original is backed up as `override.cfg.before-splitscreen`.

If Windows refuses to write to the game folder, right-click `Install.bat` and choose "Run as administrator".

### Uninstall

Double-click **`Uninstall.bat`** (same optional argument as the installer). It:
- removes the mod's line from `override.cfg`, and deletes the file if the mod was the only thing in it;
- deletes `splitscreen_mod\` and the `override.cfg.before-splitscreen` backup.

The game folder goes back to exactly how it was.

---

## 🎮 How to play

### Starting a match

1. In the main menu, pick **LOCAL SPLITSCREEN**.
2. Each player joins with their own device. The first one to join is player 1, the host of the match.
3. Optionally, set up the match with **CUSTOMIZE MATCH SETTINGS**.
4. Pick **START**. At least 2 players are needed.

### Lobby controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Join | Enter, Space or left click | A |
| Leave the lobby | Backspace | B |
| Move between rows | Up / Down arrows | D-pad up / down or left stick |
| Confirm | Enter or click | A |
| Start the match | START row | START row or Start button |
| Back to the main menu | Escape or BACK row | BACK row |

There is only one keyboard & mouse player; every other player uses a controller. If a controller is unplugged in the lobby, its player is removed.

### Customizing the match

**CUSTOMIZE MATCH SETTINGS** opens the multiplayer's own customization screen, unchanged, with all of its settings:
- number of rounds, and which round you are editing;
- skip intro;
- starting health;
- for each of the 9 items: max per player, max on the table, enabled or not;
- for each of the 4 shell sequences: number of blanks, lives and items dealt;
- reset to defaults.

"Save changes and return" saves and brings you back to the splitscreen lobby; "Cancel changes" goes back without changing anything. The screen works with the mouse and with a controller, just like in the game.

The lobby then shows a summary of the settings, with the same wording as the online lobby: number of rounds, intro skipped, customized items. These settings are shared with the online multiplayer lobby and last until the game is closed, as in the original game.

### In a match

- **Layout**: with 2 players the views sit side by side, and each player's name and device stay visible above their view. With 3 or 4 players the views are in a 2 × 2 grid, and that info shows for a few seconds at the top of each view.
- **Controls** are the game's own:
  - Keyboard & mouse: click to interact, hold right click to look around, Escape for the pause menu. The cursor stays inside its player's view.
  - Controller: D-pad to choose, A to confirm, left trigger to look around, Start for the pause menu.
- **Pause**: every player has their own pause menu. "Disconnect" ends the match for everyone and goes back to the splitscreen lobby.
- **Sound**: you hear the match from player 1's seat.
- **Unplugged controller**: that player's view says so, and they pick up where they left off as soon as it is plugged back in.
- **End of the match**: after the results screen, everyone goes back to the splitscreen lobby, ready for a rematch.

---

## 🔧 Under the Hood

### Overview

```
 Game window
 ┌──────────────────────────────┬──────────────────────────────┐
 │ Player 1 view  (960 × 540)   │ Player 2 view  (960 × 540)   │
 │ SubViewport + own 3D world   │ SubViewport + own 3D world   │
 │   └ mp_main  → HOST          │   └ mp_main  → CLIENT        │
 └──────────────┬───────────────┴──────────────┬───────────────┘
                └──── in-memory packet bus ────┘   (replaces Steam P2P)

 keyboard + mouse ──► keyboard player's view     controller n ──► its player's view
```

### Starting point: the game's own multiplayer

Buckshot Roulette is made with **Godot 4.1.1**. Its GDScript scripts live in a pack (`.pck`) embedded in `Buckshot Roulette.exe`.

The multiplayer mode (`res://multiplayer/`) assumes **one local player per game instance**:
- every instance creates the seats of all the players around the table, but only controls its own;
- the host's instance validates every action (taking the shotgun, shooting, using an item) and broadcasts the result to everyone;
- instances talk to each other through Steam P2P packets.

The mod recreates that situation inside a single process.

### Loading the mod

1. On startup, Godot reads `override.cfg` next to the executable. The mod declares the `SplitMod` autoload there, pointing to `splitscreen_mod/loader.gd`.
2. `loader.gd` runs before the main menu loads. It computes the MD5 of the 30 game scripts the mod replaces and compares them with v2.2.0.6.
3. If they match, it mounts `splitscreen.pck` with `ProjectSettings.load_resource_pack(..., replace_files = true)`. The pack's scripts take the place of the originals, and the game's scenes use them without being modified.
4. If they don't (the game was updated), it loads nothing: the game runs normally, without the LOCAL SPLITSCREEN entry.

### One copy of the match per player

When a match starts, the session scene creates, for each player:
- a **960 × 540** `SubViewport` (the game's original render resolution) with `own_world_3d`, so rendering, physics, camera and environment are separate;
- a full copy of the multiplayer scene `mp_main`, loaded **without cache** (`CACHE_MODE_IGNORE`) so every copy owns its meshes, materials and animations.

External resources the match edits at runtime (the `Environment` used for the death desaturation and the defibrillator flash, the jammer screen, the phone screen) are duplicated for each copy, so nothing happening on one player's screen leaks onto another's.

Player 1's copy is the **host**, the others are **clients**, exactly like online.

### The network, replaced by an in-memory bus

- `PacketManager.send_p2p_packet()` calls `SplitMod.send_packet()`. The packet is serialized (`var_to_bytes`) and dropped into the queue of each recipient: every other player for target `0`, otherwise the targeted player.
- Each copy reads **one packet per frame**, like the game does with `Steam.readP2PPacket()`, with the same checks: a client only accepts packets from the host.
- Everything else is the original code: waiting for players, seat creation, rounds, item dealing, host-side validation and end-of-match statistics.

### What was global becomes per player

In a single process, the game's singletons are shared by every copy. The match scripts are therefore patched to ask `SplitMod` for the values that must depend on the player:

| Original code | Replaced with | Effect in splitscreen |
|---|---|---|
| `GlobalSteam.STEAM_ID` | `SplitMod.sid(self)` | ID of this copy's local player |
| `get_node("/root/mp_main/...")` | `SplitMod.mp_root(self).get_node(...)` | This copy's `mp_main` scene |
| `Input.set_mouse_mode`, `Input.set_custom_mouse_cursor` | `SplitMod.set_mouse_mode`, `SplitMod.set_custom_mouse_cursor` | Only the keyboard & mouse player's copy drives the cursor |
| `AudioServer.set_bus_volume_db`, `AudioServer.get_bus_effect` | `SplitMod.set_bus_volume_db`, `SplitMod.get_bus_effect` | Only player 1's copy sets volumes and the low-pass filter |
| `Steam.getFriendPersonaName`, `Steam.getPlayerAvatar` | `SplitMod.persona_name`, `SplitMod.get_player_avatar` | Names "PLAYER 1" to "PLAYER 4" |
| `GlobalVariables.cursor_state_after_toggle` | `SplitMod.gv(self).cursor_state_after_toggle` | Cursor state kept per player |
| `change_scene_to_file(mp_lobby)` | `SplitMod.change_scene(...)` | End of match: back to the splitscreen lobby |

`SplitMod` finds which copy a node belongs to by walking up to the `SubViewport` that contains it. During a splitscreen match it also ignores Steam lobby callbacks (invites, member changes), which would otherwise overwrite the player list.

**Outside splitscreen, every call returns exactly the original value**: online multiplayer runs the same scripts with no change in behavior.

These patches are applied by `tools/build.js` as exact replacements whose number of occurrences is checked. If the game's code changes, the build stops and names the file at fault instead of producing a broken mod.

### Input

All input reaches the main window. The session scene intercepts it (`_input`), marks it as handled, then forwards it to the right player's `SubViewport` with `push_input`:
- keyboard and mouse go to the keyboard & mouse player (the keyboard goes to player 1 if there is none);
- each controller goes to the player who joined with it.

For the mouse:
- the position is converted to the 960 × 540 coordinates of the player's view, and the cursor is kept inside that view;
- relative motion, used to look around, is scaled like in the original game so the sensitivity is the same.

Each `SubViewport` keeps its own UI focus, so controllers navigate the game's prompts independently of each other.

### Picture and sound

- During the match, the window switches to native resolution (`content_scale_mode = DISABLED`). Each view renders at 960 × 540 and is scaled up, letterboxed if needed. Render settings (anti-aliasing, shadows, filtering) are copied from the game's window.
- Every copy plays the same events at the same time, so only player 1's `SubViewport` has its 2D and 3D audio listeners active, which keeps every sound from playing twice.

### Menu, lobby and customization

- `MenuManager.gd` adds the LOCAL SPLITSCREEN entry by duplicating the MULTIPLAYER button, so it has the same font, sounds, hover and controller navigation; the buttons below are shifted down one row.
- The splitscreen lobby is built in code with the game's fonts, sounds and music, and handles joining per device.
- **CUSTOMIZE MATCH SETTINGS** opens the real multiplayer lobby scene (`mp_lobby`) with `SplitMod.customizing` set. `MP_LobbyUI.gd` then goes straight to the customization screen, without a Steam lobby. Leaving that screen (`ExitMatchCustomization`) returns to the splitscreen lobby instead of the online lobby's home. The rest is original code: the screen saves its settings to `GlobalVariables.stashed_match_customization_dictionary`, as it does for the host of an online match.
- When a match starts, those settings become the active match dictionary. The number of rounds and the intro are applied the way the online lobby does it.
- At the end of the match, the session restores everything it changed: Steam IDs and members, active customization, volumes and audio filter, display mode, cursor. Then it goes back to the lobby.

### Leaving a match without crashing

Godot 4.1 has two traps when freeing a scene as large as a copy of the match:
- a control that still has focus or hover (for example the pause-menu button that was just pressed) queues a deferred redraw as it leaves the tree. That redraw then runs on the already freed control, which causes an intermittent crash;
- the game's coroutines call `get_tree().create_timer()`: if the node has left the tree, that `get_tree()` is null, and the shipped engine crashes instead of reporting the error.

So the session shuts down in stages:
1. Input is cut, focus and hover are released in every view, and the window and cursor are restored.
2. The engine gets two frames to run queued work while everything still exists.
3. Focus is released once more, then the scene is changed: the copies are freed inside the tree, never detached first.

Closing the window during a match goes through the same path (`auto_accept_quit` is turned off during the session). Going from the main menu to the lobby and returning from the customization screen also release focus and hover before changing scenes.

---

## 🔄 After a game update

If an update changes one of the replaced scripts, the mod turns itself off at launch. The game stays playable, just without the LOCAL SPLITSCREEN entry. To bring it back, rebuild the mod (see [Development](#%EF%B8%8F-development)) and run `Install.bat` again.

## ✅ Project status

Checked in an isolated copy of the game, with 2 players (mouse for player 1, simulated controller for player 2):
- the main menu entry, its controller navigation and the switch to the lobby;
- the lobby: joining and going back to the menu;
- the original customization screen, driven with the mouse and with a controller, with the settings applied to the next match;
- starting a match and keeping the views in sync;
- item dealing, taking the shotgun, shooting, damage and turn order;
- the end of the match: results screen, then back to the lobby;
- "Disconnect" from the pause menu through the real buttons, for player 1 (mouse) and player 2 (controller), including during the results screen;
- closing the window mid-match;
- the online multiplayer lobby, which behaves like the original game (home, customization, cancel);
- installing and uninstalling, with and without an existing `override.cfg`.

A full 2-player match (mouse + real controller) was also played on the installed version.

Not checked yet:
- 3 and 4 players;
- a full online match with the mod installed.

---

## 🛠️ Development

### Building the mod

You need **Node.js 18** or newer.

```
node tools/build.js ["path\to\Buckshot Roulette.exe"]
```

Without an argument, the game is looked up at its default Steam location. The script:
1. reads the original scripts straight from the pack embedded in the exe and puts them in `build\original`;
2. applies the patches, checking the exact number of occurrences of each one;
3. adds the files from `src\pack\`;
4. writes `mod\splitscreen.pck`, and `mod\loader.gd` with the MD5 of the original scripts it replaces.

No extracted game file is stored in the repository: `build\` is ignored by Git.

### Repository layout

| Path | Role |
|---|---|
| `Install.bat`, `Uninstall.bat` | Launchers for the installer and the uninstaller |
| `installer\` | PowerShell scripts: finding the game, copying files, editing `override.cfg` |
| `mod\` | The built mod, i.e. what gets installed into the game |
| `src\loader.gd` | `SplitMod` autoload: version check, pack loading, per-player context, packet bus |
| `src\menu_additions.gd` | LOCAL SPLITSCREEN entry, appended to `MenuManager.gd` |
| `src\lobby_ui_additions.gd` | "Customization only" mode of the multiplayer lobby, appended to `MP_LobbyUI.gd` |
| `src\pack\mods\splitscreen\split_lobby.*` | Lobby: joining, access to customization, settings summary |
| `src\pack\mods\splitscreen\split_session.*` | Match: views, loading the match copies, input routing, staged shutdown |
| `tools\build.js` | Patching the game's scripts and building the mod |
| `tools\pck.js`, `tools\mkpck.js` | Reading and writing Godot 4.1 packs (PCK format v2) |
| `tools\mp_main_scripts.txt` | List of the scripts used by the multiplayer scene |
| `tools\deps.js`, `tools\nodes.js` | Analysis of the game's scenes once converted to text |
| `tools\godot\` | Scripts run by the game's engine: scene conversion, compile check, automated test |
| `res\` | README banner |

### Testing without touching the installed game

1. Copy `Buckshot Roulette.exe` and `steam_api64.dll` to a test folder.
2. Run `Install.bat "<test folder>"`.
3. Add to that folder's `override.cfg`:
   ```
   [application]
   config/use_custom_user_dir=true
   config/custom_user_dir_name="BuckshotSplitTest"
   ```
   Saves and logs then go to `%APPDATA%\BuckshotSplitTest`, apart from the game's own.
4. For the automated test, add under `[autoload]`:
   ```
   SplitTest="*<repository path>/tools/godot/split_test.gd"
   ```

Useful runs from Git Bash (log in `%APPDATA%\BuckshotSplitTest\logs\godot.log`):

| Command | Effect |
|---|---|
| `SPLIT_TEST_MODE=menu "Buckshot Roulette.exe" --headless` | Checks the menu entry and the lobby, without a window |
| `SPLIT_TEST_MODE=session "Buckshot Roulette.exe" --windowed` | Plays a 2-player match with simulated input (mouse and controller) |
| `SPLIT_TEST_MODE=disconnect_real SPLIT_TEST_DISCONNECT=1` (or `2`) | Player 1 (Escape + clicks) or player 2 (Start, D-pad, A) leaves through the real pause-menu buttons |
| `SPLIT_TEST_MODE=conclusion`, with or without `SPLIT_TEST_DISCONNECT=1` / `2` | The host ends the match (results screen), optionally with a disconnect during the results |
| `SPLIT_TEST_MODE=custom_visual` | Lobby and customization screen (controller), then a match with the saved settings |
| `SPLIT_TEST_MODE=online_lobby` with `--headless` | Checks that the online multiplayer lobby is unchanged |
| `SPLIT_TEST_SHOTS=<folder>` (add `SPLIT_TEST_VIEWS=1` for each player's view) | Saves screenshots during any of the runs above |
| `CHECK_LIST=<list.txt> "Buckshot Roulette.exe" --headless --script <absolute path>/tools/godot/compile_check.gd` | Compiles the listed scripts (one `res://` path per line) in the game's engine |

---

## ⚖️ Notice

MoreRollers is a fan-made mod, not affiliated with the developer or the publisher of Buckshot Roulette. You need your own copy of the game on Steam.

`mod\splitscreen.pck` contains modified copies of some of the game's scripts, which remain the property of their authors.
