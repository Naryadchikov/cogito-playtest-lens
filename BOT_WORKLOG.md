# Bot worklog

Branch bot/work, from playtest-lens at dc8c771. Godot 4.7.2 stable (standard build, Linux x86_64).

## Package A: schema nits

- `where` on `marker` lines is test scaffolding: `addons/playtest_lens/tests/test_telemetry_volume.gd` calls `logger.log_event("marker", {"where": "outside"})` (also "inside", "after") to label phases. The logger itself emits `marker` with no fields (F9 in `_input`). Left as is.
- `logger.gd`: new `_log_perf`. No perf line while `Engine.get_frames_per_second() <= 1` and the session is under 2 s old. The 1 s timer still ticks, so a cold start delays the first perf line to about 2 s.
- `test_logger.gd`: waits 1.3 s more before ending the session (so a warm perf line exists) and has `_check_perf` (no cold perf line, at least one perf line, `frame_ms` present).
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
- Output: PlaytestBuild.exe 109268480 B, PlaytestBuild.console.exe 188928 B, PlaytestBuild.pck 44791836 B. The exe was not run (Windows only, no Wine).
- PCK listing: `godot --headless --main-pack build/PlaytestBuild.pck --script /tmp/listpck.gd` walked res:// (2065 files). Scripts are exported as compiled `.gdc` plus `.gd.remap` (default script export mode), so `logger.gd` appears as `addons/playtest_lens/logger.gd.remap` and `logger.gdc`; same for `adapter.gd`. Both demo scenes are present as `.tscn`. `project.binary` contains `autoload/PlaytestLensLogger`, `autoload/PlaytestLensCogito` and `playtest_lens/player_path`.
- No home path baked in: `strings` on the PCK and `grep -a` on the three files find no `/home/`, `/workspace`, `/Users/`, `C:\Users`.
- Log path on Windows: `%APPDATA%\Godot\app_userdata\Cogito\playtest_lens\<UTC wall time with colons as dashes>.jsonl`, for example `2026-10-28T15-44-06Z.jsonl`. `config/name` is "Cogito" and there is no custom user dir, and the preset's product name does not change it.
- Zip: `/workspace/ptl-bot/out/PlaytestBuild-windows.zip`, not committed.
