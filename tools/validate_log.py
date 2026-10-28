#!/usr/bin/env python3
"""Check a Playtest Lens session log (schema 1) and print a short report.

Usage: python3 tools/validate_log.py <session.jsonl>
Exit code 0 when no problem is found, 1 otherwise.
"""

import json
import sys

NUM = "number"
STR = "string"
BOOL = "bool"

# event -> (required fields, optional fields), each as {name: type}
EVENTS = {
    "session_start": (
        {"schema": NUM, "session_id": STR, "wall_time": STR, "godot_version": STR,
         "game_name": STR, "game_version": STR, "os": STR, "renderer": STR, "log_path": STR},
        {},
    ),
    "session_end": ({"reason": STR}, {}),
    "sync_flash": ({"reason": STR}, {"scene": STR}),
    "scene": ({"scene": STR}, {}),
    "position": ({"x": NUM, "y": NUM, "z": NUM}, {"yaw": NUM, "pitch": NUM}),
    "input": ({"action": STR, "pressed": BOOL}, {}),
    "pause": ({}, {}),
    "resume": ({}, {}),
    "perf": ({"fps": NUM, "frame_ms": NUM}, {}),
    "marker": ({}, {}),
    "zone_enter": ({"zone": STR, "puzzle": STR}, {}),
    "zone_exit": ({"zone": STR, "puzzle": STR}, {}),
    "death": ({}, {}),
}
# Stamped on every line while the player is inside a telemetry volume.
STAMP = ("zone", "puzzle")
BAD_TEXT = ("/Users/", "/home/", "C:\\Users\\", "C:/Users/", "@")


def kind_of(value):
    if isinstance(value, bool):
        return BOOL
    if isinstance(value, (int, float)):
        return NUM
    if isinstance(value, str):
        return STR
    return type(value).__name__


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def validate(lines):
    """Return (problems, notes, counts, length, longest_gap). Problems are (line_no, text)."""
    problems = []
    notes = []
    counts = {}
    last_t = None
    longest = (0.0, 0)
    length = 0.0
    paused = False
    zones = []
    first = True

    def bad(no, text):
        problems.append((no, text))

    for no, raw in enumerate(lines, 1):
        try:
            line = json.loads(raw)
        except ValueError:
            bad(no, "not valid JSON")
            first = False
            continue
        if not isinstance(line, dict):
            bad(no, "line is not a JSON object")
            first = False
            continue
        t = line.get("t")
        name = line.get("event")
        if kind_of(t) != NUM:
            bad(no, "t is missing or not a number")
        if not isinstance(name, str):
            bad(no, "event is missing or not a string")
            first = False
            continue
        counts[name] = counts.get(name, 0) + 1
        if kind_of(t) == NUM:
            if last_t is not None:
                if t < last_t:
                    bad(no, "t went down: %s after %s" % (t, last_t))
                elif t - last_t > longest[0]:
                    longest = (t - last_t, no)
            last_t = t
            length = max(length, t)
        if first:
            if name != "session_start":
                bad(no, "first line is %s, not session_start" % name)
            elif line.get("schema") != 1 or isinstance(line.get("schema"), bool):
                bad(no, "session_start schema is %r, not 1" % (line.get("schema"),))
            first = False
        elif name == "session_start":
            bad(no, "session_start again after the first line")
        spec = EVENTS.get(name)
        if spec is not None:
            required, optional = spec
            for key, kind in required.items():
                if key not in line:
                    bad(no, "%s lacks %s" % (name, key))
                elif kind_of(line[key]) != kind:
                    bad(no, "%s.%s is %s, expected %s" % (name, key, kind_of(line[key]), kind))
            for key, kind in optional.items():
                if key in line and kind_of(line[key]) != kind:
                    bad(no, "%s.%s is %s, expected %s" % (name, key, kind_of(line[key]), kind))
            for key in line:
                if key in ("t", "event") or key in required or key in optional or key in STAMP:
                    continue
                notes.append((no, "%s has an extra field %s" % (name, key)))
        if name == "pause":
            if paused:
                bad(no, "pause while already paused")
            paused = True
        elif name == "resume":
            if not paused:
                bad(no, "resume without a pause")
            paused = False
        if name == "zone_enter":
            zones.append(line.get("zone"))
        # Lines inside a volume carry its zone. Enter and exit name their own volume.
        if name == "zone_exit":
            if line.get("zone") in zones:
                idx = len(zones) - 1 - zones[::-1].index(line.get("zone"))
                del zones[idx]
            else:
                bad(no, "zone_exit for %r with no matching zone_enter" % (line.get("zone"),))
        elif name != "zone_enter":
            if zones:
                if "zone" not in line:
                    bad(no, "%s inside zone %s has no zone" % (name, zones[-1]))
                elif line["zone"] != zones[-1]:
                    bad(no, "%s has zone %r, expected %r" % (name, line["zone"], zones[-1]))
            else:
                for key in STAMP:
                    if key in line:
                        bad(no, "%s outside any zone carries %s" % (name, key))
        for text in strings_in(line):
            hit = next((frag for frag in BAD_TEXT if frag in text), None)
            if hit is not None:
                bad(no, "string contains %r (a person or a machine could be named)" % hit)
                break
    if not lines:
        bad(1, "the file is empty")
    if zones:
        notes.append((len(lines), "log ends inside zone %s" % zones[-1]))
    return problems, notes, counts, length, longest


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip())
        return 1
    try:
        with open(argv[1], "r", encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except (OSError, UnicodeDecodeError) as err:
        print("cannot read %s: %s" % (argv[1], err))
        return 1
    if lines and lines[-1] == "":
        lines.pop()
    problems, notes, counts, length, longest = validate(lines)
    print("lines: %d" % len(lines))
    print("events: " + ", ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)))
    unknown = sorted(k for k in counts if k not in EVENTS)
    if unknown:
        print("unknown events (counted, not failures): " + ", ".join("%s=%d" % (k, counts[k]) for k in unknown))
    print("session length: %.3f s" % length)
    print("longest gap between lines: %.3f s (before line %d)" % longest)
    for no, text in notes[:5]:
        print("note: line %d: %s" % (no, text))
    if len(notes) > 5:
        print("note: %d more notes" % (len(notes) - 5))
    if problems:
        print("FAIL: %d problem(s). First: line %d: %s" % (len(problems), problems[0][0], problems[0][1]))
        for no, text in problems[1:5]:
            print("  line %d: %s" % (no, text))
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
