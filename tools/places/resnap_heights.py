#!/usr/bin/env python3
"""Moves every marker in data/world/places.json up or down onto the road
surface of a regenerated map, without moving it across the map.

gen_places.py picks spots from the road network, so after the roads
themselves change (widths, layout) it picks different stretches. When only
the heights have changed, run this instead:

    godot --headless --path . --script res://tools/places/dump_roads.gd   # writes /tmp/roads.json
    python3 tools/places/resnap_heights.py [/tmp/roads.json]

Each point takes the height of the nearest road centre line. Points further
than REACH from any road keep their height and are listed.
"""
import json
import sys
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[2]
ROADS = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/roads.json")
OUT = ROOT / "data/world/places.json"
REACH = 15.0  # metres

roads = json.loads(ROADS.read_text())["roads"]
# Segments as (a, b) in x/z with heights, densified so a point query finds its segment.
a = np.concatenate([np.asarray(r["pts"], float)[:-1] for r in roads if len(r["pts"]) > 1])
b = np.concatenate([np.asarray(r["pts"], float)[1:] for r in roads if len(r["pts"]) > 1])
mid = (a + b) / 2
half = np.linalg.norm((b - a)[:, [0, 2]], axis=1).max() / 2
tree = cKDTree(mid[:, [0, 2]])


def road_height(x, z):
    idx = tree.query_ball_point([x, z], REACH + half)
    if not idx:
        return None, None
    A, B = a[idx], b[idx]
    d = (B - A)[:, [0, 2]]
    L2 = np.maximum((d * d).sum(axis=1), 1e-9)
    t = np.clip(((x - A[:, 0]) * d[:, 0] + (z - A[:, 2]) * d[:, 1]) / L2, 0.0, 1.0)
    px, pz = A[:, 0] + t * d[:, 0], A[:, 2] + t * d[:, 1]
    dist = np.hypot(px - x, pz - z)
    k = int(np.argmin(dist))
    if dist[k] > REACH:
        return None, float(dist[k])
    return float(A[k, 1] + t[k] * (B[k, 1] - A[k, 1])), float(dist[k])


def resnap(p, where, report):
    h, dist = road_height(p[0], p[2])
    if h is None:
        report.append((where, p, dist))
        return p
    return [p[0], round(h, 2), p[2]]


def main():
    data = json.loads(OUT.read_text())
    report, moved = [], []
    for key, val in data.items():
        items = val if isinstance(val, list) else [val] if isinstance(val, dict) else []
        for item in items:
            name = item.get("id") or item.get("car") or key
            if "p" in item:
                new = resnap(item["p"], name, report)
                moved.append(new[1] - item["p"][1])
                item["p"] = new
            if "points" in item:
                pts = [resnap(p, name, report) for p in item["points"]]
                moved += [n[1] - o[1] for n, o in zip(pts, item["points"])]
                item["points"] = pts
    OUT.write_text(json.dumps(data, indent=1) + "\n")
    moved = np.abs(np.asarray(moved))
    print("wrote", OUT.relative_to(ROOT), "%d points, height change median %.2f m, max %.2f m"
          % (len(moved), np.median(moved), moved.max()))
    for where, p, dist in report:
        print("  kept height (no road within %.0f m):" % REACH, where, p, "" if dist is None else "nearest %.0f m" % dist)


main()
