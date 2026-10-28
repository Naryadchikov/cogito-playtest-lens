#!/usr/bin/env python3
"""Runs tools/volume_report.gd on throwaway copies of the Lobby scene under build/ and checks the findings.

Usage (repo root): GODOT=/path/to/godot python3 tools/test_volume_report.py
Only the copies it creates are deleted. No scene under addons/ is touched.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "godot")
SOURCE = os.path.join(ROOT, "addons/cogito/DemoScenes/COGITO_3_Lobby.tscn")
BUILD = os.path.join(ROOT, "build")
SCRIPT_ID = "vr_test_script"
IDENTITY = "1, 0, 0, 0, 1, 0, 0, 0, 1"


def volume_text(index, name, zone, puzzle, center, size, basis=IDENTITY):
    sub = (
        '[sub_resource type="BoxShape3D" id="vr_test_box%d"]\nsize = Vector3(%s, %s, %s)\n\n' % (index, size[0], size[1], size[2])
    )
    node = (
        '[node name="%s" type="Area3D" parent="."]\n'
        "transform = Transform3D(%s, %s, %s, %s)\n"
        'script = ExtResource("%s")\n'
        'zone = "%s"\npuzzle = "%s"\n\n'
        '[node name="Shape" type="CollisionShape3D" parent="%s"]\nshape = SubResource("vr_test_box%d")\n\n'
    ) % (name, basis, center[0], center[1], center[2], SCRIPT_ID, zone, puzzle, name, index)
    return sub, node


def make_copy(path, volumes):
    lines = open(SOURCE, encoding="utf-8").read().split("\n")
    # The copy must not share the uid of the original.
    lines[0] = re.sub(r' uid="[^"]*"', "", lines[0])
    ext = '[ext_resource type="Script" path="res://addons/playtest_lens/telemetry_volume.gd" id="%s"]' % SCRIPT_ID
    first_node = next(i for i, l in enumerate(lines) if l.startswith("[node "))
    first_tail = next(i for i, l in enumerate(lines) if l.startswith("[connection") or l.startswith("[editable"))
    subs = "".join(v[0] for v in volumes)
    nodes = "".join(v[1] for v in volumes)
    out = lines[:3] + [ext] + lines[3:first_node] + subs.split("\n") + lines[first_node:first_tail] + nodes.split("\n") + lines[first_tail:]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


def run_report(name):
    res = "res://build/" + name
    cmd = [GODOT, "--headless", "--path", ROOT, "--script", "tools/volume_report.gd", "--", res + ".tscn", res, "res://maps/lobby"]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    return proc.returncode, proc.stdout + proc.stderr


def warnings_of(text):
    # Only the report's own block: Godot prints its own WARNING lines at exit.
    block = text.split("\nwarnings: ", 1)[-1].split("\nwrote ", 1)[0]
    return [l[len("WARNING: "):] for l in block.split("\n") if l.startswith("WARNING: ")]


def check(label, ok, failures):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        failures.append(label)


def main():
    os.makedirs(BUILD, exist_ok=True)
    failures = []
    made = []
    try:
        # Scenario 1: one fine volume, one too thin, one overlapping the first. The start (3.03, 0.91, -17.93) is in the first.
        a = volume_text(1, "VolFine", "Entrance", "Hall", (3.0, 1.5, -18.0), (8, 3, 6))
        b = volume_text(2, "VolThin", "Backroom", "", (-10.0, 1.5, 0.0), (1.0, 3, 6))
        c = volume_text(3, "VolOverlap", "Entrance", "Hall", (6.0, 1.5, -18.0), (6, 3, 6))
        make_copy(os.path.join(BUILD, "vr_test_one.tscn"), [a, b, c])
        made.append("vr_test_one.tscn")
        rc, text = run_report("vr_test_one")
        w = warnings_of(text)
        check("scenario 1: exit code 0", rc == 0, failures)
        check("scenario 1: exactly two warnings", len(w) == 2, failures)
        check("scenario 1: thin volume 2 reported once", sum("volume 2" in x and "thin in x" in x for x in w) == 1, failures)
        check("scenario 1: overlap of 1 and 3 is 4.00 x 3.00 x 6.00", sum("volumes 1 and 3 overlap by 4.00 x 3.00 x 6.00" in x for x in w) == 1, failures)
        check("scenario 1: player start is in volume 1", "volume: 1 (Entrance / Hall)" in text, failures)
        check("scenario 1: svg written", "_volumes.svg ok=true" in text, failures)
        made.append("vr_test_one_volumes.svg")
        print(text)

        # Scenario 2: empty zone, case and spacing typo, low box, rotated box.
        d = volume_text(1, "VolEmpty", "", "X", (-10.0, 1.5, 0.0), (4, 3, 4))
        e = volume_text(2, "VolTypoA", "Fuse Box", "Puzzle A", (3.0, 1.5, -18.0), (4, 3, 4))
        f = volume_text(3, "VolTypoB", "fuse  box", "puzzle a", (-10.0, 1.5, 12.0), (4, 3, 4))
        g = volume_text(4, "VolLow", "Low", "", (12.0, 0.75, -18.0), (4, 1.5, 4))
        rot = "0.866, 0, -0.5, 0, 1, 0, 0.5, 0, 0.866"
        h = volume_text(5, "VolRot", "Turned", "", (3.0, 1.5, 8.0), (4, 3, 4), rot)
        make_copy(os.path.join(BUILD, "vr_test_two.tscn"), [d, e, f, g, h])
        made.append("vr_test_two.tscn")
        rc, text = run_report("vr_test_two")
        w = warnings_of(text)
        check("scenario 2: exit code 0", rc == 0, failures)
        check("scenario 2: empty zone", any("volume 1" in x and "empty zone" in x for x in w), failures)
        check("scenario 2: case or spacing typo", any("volumes 2 and 3 differ only by case or spacing" in x for x in w), failures)
        check("scenario 2: low volume 4", any("volume 4" in x and "low: height 1.50" in x for x in w), failures)
        check("scenario 2: rotated bounds stated", "(rotated, axis-aligned bounds)" in text, failures)
        made.append("vr_test_two_volumes.svg")
    finally:
        for name in made:
            path = os.path.join(BUILD, name)
            if os.path.exists(path):
                os.remove(path)
    if failures:
        print("FAILED: %d" % len(failures))
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
