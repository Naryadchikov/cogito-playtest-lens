# Bot worklog

Branch bot/work, from playtest-lens at dc8c771. Godot 4.7.2 stable (standard build, Linux x86_64).

## Package A: schema nits

- `where` on `marker` lines is test scaffolding: `addons/playtest_lens/tests/test_telemetry_volume.gd` calls `logger.log_event("marker", {"where": "outside"})` (also "inside", "after") to label phases. The logger itself emits `marker` with no fields (F9 in `_input`). Left as is.
- `logger.gd`: new `_log_perf`. No perf line while `Engine.get_frames_per_second() <= 1` and the session is under 2 s old. The 1 s timer still ticks, so a cold start delays the first perf line to about 2 s.
- `test_logger.gd`: waits 1.3 s more before ending the session (so a warm perf line exists) and has `_check_perf` (no cold perf line, at least one perf line, `frame_ms` present).
- Commands: `godot --headless --path . res://addons/playtest_lens/tests/test_logger.tscn` and the five other test scenes. All exit 0.
