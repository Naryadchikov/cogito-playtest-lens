# Playtest Lens logger for Godot

A playtest recording shows what the tester saw and said, but not where they stood, what they pressed or when they paused.

This add-on writes those facts to a log, one JSON line at a time, on a clock that lines up with the screen recording. The [Playtest Lens](https://github.com/Naryadchikov/playtest-lens) analyzer reads the log next to the video.

It only listens and writes. It never changes gameplay, timing, input or saves.

Needs Godot 4.7. Position, view direction and telemetry volumes need a 3D player (any `Node3D`, such as a `CharacterBody3D`).

## What it logs

One JSON object per line. Every line has `t`, seconds since the session started, and `event`. While the player is inside a telemetry volume, every line also carries that volume's `zone` and `puzzle`. The full schema: [docs/LOG_SCHEMA.md](https://github.com/Naryadchikov/playtest-lens/blob/main/docs/LOG_SCHEMA.md).

| Event | Written when |
|---|---|
| `session_start` | The game starts. First line. |
| `scene` | The current scene changes. |
| `sync_flash` | The white flash is drawn (see below). |
| `position` | Every 0.5 s while the player node is found. `yaw` and `pitch` come from the current `Camera3D`. |
| `input` | An Input Map action goes down or up, the built-in `ui_` actions too. |
| `pause`, `resume` | The scene tree pauses or resumes. |
| `perf` | Once a second, from 2 s after the start. |
| `marker` | The tester presses F9. |
| `zone_enter`, `zone_exit` | The player enters or leaves a telemetry volume. |
| `session_end` | The game quits. Missing after a crash. |

One example line of each:

```json
{"event":"session_start","game_name":"My Game","game_version":"1.0","godot_version":"4.7.2-stable (official)","log_path":"user://playtest_lens/2026-10-31T21-55-25Z.jsonl","os":"Windows","renderer":"forward_plus","schema":1,"session_id":"2026-10-31T21-55-25Z-21473","t":0.000421,"wall_time":"2026-10-31T21:55:25Z"}
{"event":"scene","scene":"res://levels/lobby.tscn","t":0.002053}
{"beep_hz":1000,"duration_s":0.25,"event":"sync_flash","reason":"level_load","scene":"res://levels/lobby.tscn","t":0.008004}
{"event":"position","pitch":-18.0,"t":0.502261,"x":1.25,"y":2.5,"yaw":90.0,"z":3.75}
{"action":"jump","event":"input","pressed":true,"t":0.654668}
{"event":"pause","t":0.902212}
{"event":"resume","t":1.206378}
{"event":"perf","fps":145.0,"frame_ms":6.72,"t":2.005674}
{"event":"marker","t":2.219756}
{"event":"zone_enter","puzzle":"FuseBox","t":2.67432,"zone":"Generator Room"}
{"event":"zone_exit","puzzle":"FuseBox","t":3.523026,"zone":"Generator Room"}
{"event":"session_end","reason":"quit","t":4.240889}
```

Your game can add its own lines: see [Send your own game events](#send-your-own-game-events).

## Install in five steps

1. Copy the `addons/playtest_lens/` folder into your project's `addons/` folder. The `tests/` folder inside it is optional.
2. Open the project in Godot 4.7. In Project, Project Settings, Plugins, enable Playtest Lens. This adds the `PlaytestLensLogger` autoload.
3. In Project Settings, General, find Playtest Lens and set Player Path to your player node (see the next section).
4. Optional: place telemetry volumes over the rooms and puzzles you want named in the log.
5. Run the game, play for a minute, and quit. Open Project, Open User Data Folder, then the `playtest_lens` folder: the newest `.jsonl` file is your log.

## The player path

The setting `playtest_lens/player_path` names the node whose position is logged:

- relative to the current scene's root, such as `Player` or `World/Player`, so it follows the player from level to level;
- or absolute, starting with `/`, such as `/root/Main/Player`.

The node must be a `Node3D`. The logger looks it up again every time, so a player spawned after the level loads is found.

The default is empty. With no player path, the log has no `position` lines, no zone lines and no flash at level load. Inputs, scenes, pauses, perf lines and markers are still logged.

## Telemetry volumes

A telemetry volume is a designer zone: a named box over a room or a puzzle.

1. Add a `PlaytestLensTelemetryVolume` node (it is an `Area3D`) and give it a `CollisionShape3D` child sized to the room.
2. Set Zone, such as `Generator Room`.
3. Optional: set Puzzle, such as `FuseBox`, when the zone holds a puzzle. Leave it empty otherwise.

When the player walks in, the log writes `zone_enter`, and every later line carries the zone and the puzzle until `zone_exit`. When volumes overlap, the one entered last names the lines. A player who starts inside a volume is caught at level load.

The volume stays out of the game's way: it sits on no physics layer, nothing collides with it, and it overrides no gravity, damping or audio. It sees the player body on any layer, and the logger counts only the player.

## The sync flash and beep

When a scene with the player loads, the screen turns white for 0.25 s and a 1000 Hz beep plays on the Master bus. The `sync_flash` line is written when that white frame is drawn, on the log's own clock.

The analyzer finds the first white frame in the video and matches it with the first `sync_flash` line, so every log time maps to a video time. The beep marks the same moment in the audio. Record the whole screen, with the game's sound.

To flash at another moment, such as when the player presses New Game, call `sync_flash` with a reason of your own:

```gdscript
var logger := get_node_or_null("/root/PlaytestLensLogger")
if logger != null:
	logger.sync_flash("new_game")
```

A request while a flash is still showing is ignored and not logged.

## The F9 marker

Pressing F9 writes a `marker` line, so a tester or a developer can flag a moment worth a look. The logger only listens: if your game uses F9 too, the game still gets the key.

## Where the logs are

One file per session, named by its start time in UTC, such as `2026-10-31T21-55-25Z.jsonl`. Each line is written to disk at once, so a crash keeps everything up to the crash.

- Windows: `%APPDATA%\Godot\app_userdata\<project name>\playtest_lens`
- Mac: `~/Library/Application Support/Godot/app_userdata/<project name>/playtest_lens`

`<project name>` is Application, Config, Name in Project Settings. If your project turns on a custom user directory (`application/config/use_custom_user_dir`), the folder is `%APPDATA%\<custom dir>\playtest_lens` on Windows and `~/Library/Application Support/<custom dir>/playtest_lens` on Mac. In the editor, Project, Open User Data Folder opens the right place.

## Privacy

The log names no person and no machine. The file path is written as `user://`, not as a full path with the account name, and `session_id` is the start time and the process number. What it records is play: inputs, positions, scenes, zones and the events your code sends.

Keep your own events the same way: no player names, emails, account IDs or file paths.

## Send your own game events

`log_event(event_name, fields)` writes one line. The logger adds `t`, `event` and the current zone; the fields are yours (strings, numbers and booleans). Call it through `get_node_or_null`, so your game still runs when the plugin is disabled:

```gdscript
# Report a game event to Playtest Lens, if it is installed.
func report(event_name: String, fields := {}) -> void:
	var logger := get_node_or_null("/root/PlaytestLensLogger")
	if logger != null:
		logger.log_event(event_name, fields)
```

A door, a pickup, a quest step and a death, from your own scripts:

```gdscript
# In a door script: the door's path from the level root names the place.
report("door", {"path": String(get_tree().current_scene.get_path_to(self)), "open": true})

# When the player picks up an item.
report("pickup", {"item": "Fuse"})

# When a quest step changes: activated, updated, completed or failed.
report("quest", {"quest": "restore_power", "step": "completed"})

# When the player dies.
report("death", {})
```

These names and fields match what the analyzer already reads. Every line goes into the check's log slice; the report's event list shows doors, locks, pickups and quest steps (not keypads or deaths yet):

| Event | Fields |
|---|---|
| `door` | `path`, `open` |
| `lock` | `path`, `locked` |
| `keypad` | `path` (the right code was entered) |
| `pickup` | `item` |
| `quest` | `quest`, `step` |
| `death` | none, or `x`, `y`, `z` |

The analyzer counts deaths and retries from `death`. Every other line, yours included, reaches it as part of the log around each moment it checks.

For a full adapter, see [`addons/playtest_lens_cogito/adapter.gd`](https://github.com/Naryadchikov/cogito-playtest-lens/blob/playtest-lens/addons/playtest_lens_cogito/adapter.gd) in the COGITO fork this add-on was built in: it connects to the COGITO template's door, keypad, inventory and quest signals and writes each one through this same `log_event` call, without editing COGITO's scripts.

## License

MIT. See [LICENSE](LICENSE).
