#!/usr/bin/env python3
"""Tiny self-test for validate_log.py. Run: python3 tools/test_validate_log.py"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validate_log

START = {"t": 0.0, "event": "session_start", "schema": 1, "session_id": "s", "wall_time": "2026-10-28T10:00:00Z",
         "godot_version": "4.7.2.stable", "game_name": "Game", "game_version": "", "os": "Linux",
         "renderer": "forward_plus", "log_path": "user://playtest_lens/x.jsonl"}


def good():
    return [
        dict(START),
        {"t": 0.5, "event": "position", "x": 1.0, "y": 0.0, "z": 2.0, "yaw": 90.0, "pitch": 0.0},
        {"t": 0.6, "event": "pause"},
        {"t": 0.9, "event": "resume"},
        {"t": 1.0, "event": "perf", "fps": 60.0, "frame_ms": 16.6},
        {"t": 1.1, "event": "zone_enter", "zone": "Puzzle", "puzzle": "Fuse"},
        {"t": 1.2, "event": "marker", "zone": "Puzzle", "puzzle": "Fuse"},
        {"t": 1.3, "event": "zone_exit", "zone": "Puzzle", "puzzle": "Fuse"},
        {"t": 1.4, "event": "input", "action": "jump", "pressed": True},
        {"t": 1.5, "event": "future_event", "anything": 1},
        {"t": 2.0, "event": "session_end", "reason": "quit"},
    ]


def run(rows):
    lines = [r if isinstance(r, str) else json.dumps(r) for r in rows]
    problems, _notes, counts, _length, _gap = validate_log.validate(lines)
    return problems, counts


def expect_problem(label, rows, line_no):
    problems, _ = run(rows)
    assert problems and problems[0][0] == line_no, "%s: got %r" % (label, problems)
    print("caught: %s -> %s" % (label, problems[0]))


def main():
    problems, counts = run(good())
    assert not problems, problems
    assert counts["future_event"] == 1
    rows = good()
    rows[1]["t"] = "later"
    expect_problem("t is text", rows, 2)
    rows = good()
    rows[4]["t"] = 0.1
    expect_problem("t goes down", rows, 5)
    rows = good()
    rows[0]["schema"] = 2
    expect_problem("schema 2", rows, 1)
    rows = good()
    rows[1] = "{not json"
    expect_problem("broken JSON", rows, 2)
    rows = good()
    del rows[1]["z"]
    expect_problem("position without z", rows, 2)
    rows = good()
    del rows[6]["zone"]
    expect_problem("zone dropped inside a volume", rows, 7)
    rows = good()
    rows[8]["zone"] = "Puzzle"
    expect_problem("zone left on after exit", rows, 9)
    rows = good()
    rows[3]["event"] = "pause"
    expect_problem("pause twice", rows, 4)
    rows = good()
    rows[0]["log_path"] = "/home/someone/x.jsonl"
    expect_problem("home path", rows, 1)
    rows = good()
    rows[8]["action"] = "me@host"
    expect_problem("at sign", rows, 9)
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
