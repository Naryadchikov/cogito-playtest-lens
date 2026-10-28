# Bot worklog

Branch bot/work, from playtest-lens at dc8c771. Godot 4.7.2 stable (standard build, Linux x86_64).

## Package A: schema nits

- `where` on `marker` lines is test scaffolding: `addons/playtest_lens/tests/test_telemetry_volume.gd` calls `logger.log_event("marker", {"where": "outside"})` (also "inside", "after") to label phases. The logger itself emits `marker` with no fields (F9 in `_input`). Left as is.
- `logger.gd`: new `_log_perf`. No perf line while the session is under 2 s old, so the first perf line is at about t=2.0. First try skipped only fps <= 1, but this box read 25 to 36 fps at t=1.0 (partial first window), so the rule is now age only.
- `test_logger.gd`: waits 1.3 s more before ending the session (so a warm perf line exists) and has `_check_perf` (no perf before t=2.0, fps above 1, at least one perf line, `frame_ms` present).
- Commands: `godot --headless --path . res://addons/playtest_lens/tests/test_logger.tscn` and the five other test scenes. All exit 0.

## Package B: top-down map export

- Path taken: real rendering, not the SVG fallback. Software GL (llvmpipe) under Xvfb works.
- Command (one per scene, from the repo root):
  `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --script tools/map_export.gd -- res://addons/cogito/DemoScenes/COGITO_3_Lobby.tscn res://maps/lobby`
  `... -- res://addons/cogito/DemoScenes/COGITO_4_Laboratory.tscn res://maps/laboratory`
  Both exit 0 and print the player start's pixel. An optional third argument sets `y_cutoff` (default 2.4).
- The tool works on an in-memory copy: scripts are cut, nothing ticks, the Player, lights, cameras, canvas items, sounds and particles are freed, and every GeometryInstance3D whose world AABB starts at or above `y_cutoff` is hidden (ceilings, roofs). Surfaces are drawn unlit and coloured by world height (dark blue floor, cream wall tops), so rooms read as outlines. No scene file is written (`git status` clean for `addons/cogito`).
- Bounds are the union of the visible meshes plus 1 unit padding, rounded to whole units. Long side is 2048 px, the other side keeps the aspect.
- JSON has the seven required keys plus a `convention` string (extra key, one string).
- Check: lobby start (3.03, -17.93) lands at px (1002, 337) of 1334 x 2048 on a floor pixel inside a small room; laboratory start (5.14, -5.43) lands at px (1643, 868) of 2048 x 2016 on a floor pixel in a room. Verified by drawing a ring on a copy and viewing it.
- Tests after: all six headless tests exit 0.

## Package C: headless Windows export

- Added `export_presets.cfg` (preset "Windows Desktop": x86_64, embed PCK off, console wrapper 2, product name "Playtest Build", `application/modify_resources=false` so no icon or resource edit, no code signing). The `.gitignore` line `export_presets.cfg` is removed (otherwise the preset cannot be committed) and `build/` is added. Also `maps/.gdignore` so Godot does not import the map PNGs into the game and the PCK, and the `tools/map_export.gd.uid` file Godot generated.
- Console wrapper must be 2 (debug and release). Value 1 only wrapped debug exports and the first release export had no `.console.exe`.
- Export templates 4.7.2.stable were installed from the official godot-builds release after checking the SHA-512 from SHA512-SUMS.txt (editor zip and export templates tpz both OK). Standard build, not Mono.
- Command: `godot --headless --path . --export-release "Windows Desktop" build/PlaytestBuild.exe` (exit 0, about 6 s).
- Output: PlaytestBuild.exe 109268480 B, PlaytestBuild.console.exe 188928 B, PlaytestBuild.pck 44763968 B (final build, after the perf change). The exe was not run (Windows only, no Wine).
- PCK listing: `godot --headless --main-pack build/PlaytestBuild.pck --script /tmp/listpck.gd` walked res:// (2065 files). Scripts are exported as compiled `.gdc` plus `.gd.remap` (default script export mode), so `logger.gd` appears as `addons/playtest_lens/logger.gd.remap` and `logger.gdc`; same for `adapter.gd`. Both demo scenes are present as `.tscn`. `project.binary` contains `autoload/PlaytestLensLogger`, `autoload/PlaytestLensCogito` and `playtest_lens/player_path`.
- No home path baked in: `strings` on the PCK and `grep -a` on the three files find no `/home/`, `/workspace`, `/Users/`, `C:\Users`.
- Log path on Windows: `%APPDATA%\Godot\app_userdata\Cogito\playtest_lens\<UTC wall time with colons as dashes>.jsonl`, for example `2026-10-28T15-44-06Z.jsonl`. `config/name` is "Cogito" and there is no custom user dir, and the preset's product name does not change it.
- Zip: `/workspace/ptl-bot/out/PlaytestBuild-windows.zip` (62297284 B, sha256 c2f53f066b0a79c426d265c4179ea9280a7b63b826a11f0cb98be24ff5897fd6), not committed.

## Package D: log validator

- `tools/validate_log.py` (stdlib only; exit 0 or 1) and `tools/test_validate_log.py` (`python3 tools/test_validate_log.py`, exit 0, 10 corruptions caught).
- Checks: valid JSON object per line, numeric `t` that never decreases, string `event`, first line `session_start` with schema 1, required fields and types per known event, zone stamping (stack of open zones, none outside), pause and resume alternate, no `/Users/`, `/home/`, `C:\Users\` or `@` in any string value. Unknown events are counted. Extra fields on known events are printed as notes, not failures.
- Ran it on 30 logs written by the six headless tests: all PASS, so the logger does not leak a home path. Notes: `sync_flash` carries `beep_hz` and `duration_s`, and the telemetry test's markers carry `where`.
- Three hand-corrupted copies of the telemetry log (time goes back, zone missing inside a volume, home path in `log_path`) each fail with the right line number. The test's telemetry log is copied by the test to `<repo parent>/runs/checks/18-telemetry.jsonl`, outside the repo.

# Work package 2 (branch bot/work2, from origin/playtest-lens at b0a52cf)

Start check: `git fetch origin`, `git checkout -B bot/work2 origin/playtest-lens`, `git log` contains b0a52cf, and BOT_WORKLOG.md, tools/map_export.gd, tools/validate_log.py, maps/ are present. Six headless tests before: all exit 0 (`bash runtests.sh before`, a loop over the six scenes with `godot --headless --path . res://<scene>.tscn`).

## Package E: scene inventory with an annotated map

- Files: `tools/scene_inventory.gd` (SceneTree script), `tools/inventory_lib.gd` (shared helpers, also used by package F), outputs `maps/lobby_objects.json`, `maps/lobby_annotated.svg`, `maps/laboratory_objects.json`, `maps/laboratory_annotated.svg`.
- Commands (repo root, exit 0 each, about 2 s):
  `godot --headless --path . --script tools/scene_inventory.gd -- res://addons/cogito/DemoScenes/COGITO_3_Lobby.tscn res://maps/lobby`
  `godot --headless --path . --script tools/scene_inventory.gd -- res://addons/cogito/DemoScenes/COGITO_4_Laboratory.tscn res://maps/laboratory`
  No display is needed. The scene is instantiated but NOT added to the tree, so no COGITO script runs (no `_ready`, no saves) and global positions are computed by multiplying the parent Node3D transforms. The tool waits one frame first (autoloads), as the brief asks.
- Map mapping uses `maps/<name>.json` only (`Lib.to_px`). The SVG embeds `<image href="<name>.png" xlink:href="<name>.png">` (relative).
- Classification reads the script chain of each node (global class name, else script file name), most derived first. Matched, and why (all read in `addons/cogito/`):
  - `CogitoDoor` (door), `CogitoSwitch` (switch), `CogitoButton` (button), `CogitoKeypad` (keypad): the classes COGITO's interaction ray acts on; each adds itself to group `interactable` in `_ready`.
  - `CogitoContainer` and its subclasses `LootableContainer`, `LootDropContainer` (container); `CogitoSittable` (seat) and `CogitoVehicle` (vehicle); `CogitoStaticInteractable` and `cogito_vendor.gd` (interactable).
  - Puzzle pieces: `CogitoSnapSlot`, `CogitoPressureplate`, `cogito_turnwheel.gd` (puzzle).
  - `CogitoNPC` (npc), because the player can shoot or talk to it.
  - `CogitoObject` (the base of prefab props) is listed only when it has a child `InteractionComponent`; kind by the component: `PickupComponent` with `slot_data.inventory_item` of class `KeyItemPD` (key), `CurrencyItemPD` (token), anything else (pickup); else `ReadableComponent` (readable); else any component other than `CogitoCarryableComponent` (interactable); else (carryable). Objects with no component are inert props and are skipped. `CogitoProjectile` (ammo props) is a CogitoObject and follows the same rule.
  - Place markers (kind trigger): `CogitoCutsceneTrigger`, `scene_transition_zone.gd`, `cogito_spawnzone.gd`, `Ladder`, and `CogitoQuestUpdater` only when it is an Area3D (the Node3D ones sit on objects and would duplicate them). COGITO has no checkpoint class (grep for "checkpoint" in addons/cogito finds nothing), so these zones are the closest thing.
  - connector: the Node3D nodes in `CogitoScene.connectors` (where the player enters from another scene).
  - player_start: the node whose script chain has `CogitoPlayerAdvanced`, `CogitoPlayerSimple` or `CogitoPlayer`. Its subtree (HUD, interaction ray, wieldables) is not walked.
  - volume: `PlaytestLensTelemetryVolume` (none in the scenes today).
  - Not listed: InteractionComponent children, attributes, state-chart nodes, lights, hazard and gravity zones, security cameras.
- JSON entries carry the required `name`, `class`, `script`, `x`, `y`, `z`, `parent_path` plus two extra string keys `kind` and `detail` (item name or trigger type). `parent_path` starts with the scene root name, never a machine path. Sorted by name then parent_path.
- SVG: numbered colored markers (number = index in the sorted JSON array plus 1), a short label next to a marker only when no other marker is within 40 px and the label box does not touch another label or marker; other numbers go to the legend column on the right (number, name, kind). Nodes that kept an engine name (for example AnimatableBody3D) are shown as `<parent>.<name>`.
- Render check: `cairosvg` in a venv under the home directory (`python3 -m venv ~/ptl-venv; ~/ptl-venv/bin/pip install cairosvg`; `svg2png(..., unsafe=True)` so the relative PNG loads), then viewed. Lobby start sits on the dark floor of the entrance corridor, laboratory start sits inside a room; numbered objects sit inside rooms. Renders are in `/workspace/ptl-bot/out2/` and not committed.
- Counts: lobby 130 objects, laboratory 66 objects.
- Path check: `grep -lE "/home|/workspace|/Users|C:\\\\" maps/*_objects.json maps/*_annotated.svg` finds nothing.
- Tests after E: all six headless tests exit 0 (project.godot unchanged, not in the commit).
