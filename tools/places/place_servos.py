#!/usr/bin/env python3
"""Picks a forecourt for every servo on the map and writes data/world/servos.json.

The map's servo POIs (index.json, from OpenStreetMap amenity=fuel) sit on the
station's node or the middle of its area: often on a shop roof, a lawn or a
footpath. Each servo needs room for a pump bay under a canopy, on flat open
ground you can drive onto from a road. This finds it:

    godot --headless --path . --script res://tools/places/dump_servo_ground.gd   # writes /tmp/servo_ground.json
    godot --headless --path . --script res://tools/places/dump_roads.gd            # writes /tmp/roads.json
    python3 tools/places/place_servos.py [/tmp/servo_ground.json] [--roads=/tmp/roads.json] [--refresh]

The servo's footprint (in its own frame, x across, z along the bay; see
scripts/world/servo.gd) must be paving or ground (no road, footpath, building,
water, bank or wall), clear of trees, poles and parking spots, flat under the
bay and the pump island, and joined to a road by ground a car can drive over
(no step of more than a kerb). Of the spots that fit, nearest the POI wins,
paving over grass, close to the road. Then only servos at least SPACING apart
are kept (real ones clump; the game needs one every so often), and only the
kept ones get a pin.

The price sign stands at the corner of the bay's open end and turns to face
along the nearest road, so traffic either way reads it. Workshops that sell
fuel (config.json "workshops", like the Fitzgerald St servo) get the same
layout where they are, keeping their kinds.
"""
import json
import math
import sys
from collections import deque
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
GROUND = Path(ARGS[0] if ARGS else "/tmp/servo_ground.json")
# --refresh: keep the servos already in servos.json where they are, and only
# redo what's derived from the ground around them (the price sign's facing,
# the workshops that sell fuel).
REFRESH = "--refresh" in sys.argv
ROADS = Path(next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--roads=")), "/tmp/roads.json"))
OUT = ROOT / "data/world/servos.json"

# Must match scripts/world/servo.gd.
FOOT_X = (-3.5, 6.5)     # canopy over the bay, island and the far edge
FOOT_Z = (-6.5, 6.5)
FLAT_X = (-2.5, 4.5)     # the bay and the pump island
FLAT_Z = (-3.5, 3.5)
FLAT = 0.2               # metres, highest to lowest under the bay and island
FLAT_ALL = 0.45          # under the whole canopy
LANE_X = (-2.0, 2.0)     # driving in and out of the bay, at one end at least
LANE_Z = 6.0             # metres past the footprint
WALL_CLEAR = 2           # cells (1 m) between the footprint and a building or wall
LANE_CLEAR = 1.5         # trunks and poles beside the way in
KERB = 0.25              # a car rides up a step this high (tools/kerb_test.gd)
REACH = 38.0             # how far from the POI the servo may move
ROAD_STEPS = 30          # and how far (in 1 m cells) from a road
TREE_CLEAR = 2.5         # trunk to canopy edge, times the tree's scale
POLE_CLEAR = 0.8
PARKING_CLEAR = 3.0
MARKER_CLEAR = 15.0      # job sites, workshops, barn finds and the rest
FUEL_WORKSHOP = 40.0     # a POI this close to a workshop selling fuel is that workshop
SPACING = 1500.0         # metres between servos kept (the workshop on Fitzgerald St counts)

C_ROAD, C_FOOT, C_PAVING, C_GROUND, C_BUILDING, C_WATER, C_OTHER = 1, 2, 3, 4, 5, 6, 7


def frame(yaw):
    """Unit x and z of a node rotated `yaw` about Y (Godot), in world x/z."""
    return np.array([math.cos(yaw), -math.sin(yaw)]), np.array([math.sin(yaw), math.cos(yaw)])


def rect_points(xr, zr, step=0.5):
    xs = np.arange(xr[0], xr[1] + 1e-6, step)
    zs = np.arange(zr[0], zr[1] + 1e-6, step)
    gx, gz = np.meshgrid(xs, zs)
    return np.column_stack([gx.ravel(), gz.ravel()])


FOOT = rect_points(FOOT_X, FOOT_Z)
SIGN = (5.8, 5.8)        # the price sign, x and (times open_end) z
SLAB_X = np.arange(FOOT_X[0], FOOT_X[1] + 1e-6, 1.0)
SLAB_Z = np.arange(FOOT_Z[0], FOOT_Z[1] + 1e-6, 1.0)
FLATP = rect_points(FLAT_X, FLAT_Z)
LANE_A = rect_points(LANE_X, (FOOT_Z[1], FOOT_Z[1] + LANE_Z))
LANE_B = rect_points(LANE_X, (FOOT_Z[0] - LANE_Z, FOOT_Z[0]))


def markers():
    """Every other thing placed on the map, as world x/z."""
    pts = []
    index = json.loads((ROOT / "map/tiles/index.json").read_text())
    for key in ("job_sites", "workshops", "badges"):
        for e in index.get(key, []):
            if "position" in e:
                pts.append((e["position"][0], e["position"][2]))
    if "position" in index.get("home", {}):
        p = index["home"]["position"]
        pts.append((p[0], p[2]))
    places = json.loads((ROOT / "data/world/places.json").read_text())
    for key, items in places.items():
        if not isinstance(items, list):
            continue
        for e in items:
            if isinstance(e, dict) and "p" in e:
                pts.append((e["p"][0], e["p"][2]))
    parts = ROOT / "data/world/found_parts.json"
    if parts.exists():
        data = json.loads(parts.read_text())
        for e in data if isinstance(data, list) else data.get("parts", []):
            p = e.get("p") or e.get("position")
            if p:
                pts.append((p[0], p[2]))
    fuel = [(e["position"][0], e["position"][2]) for e in index.get("workshops", [])
            if "fuel" in e.get("kinds", []) and "position" in e]
    return np.array(pts, float).reshape(-1, 2), fuel


def reachable(cls, h):
    """BFS from road cells over drivable cells: steps from the nearest road, -1 where you can't get."""
    n = cls.shape[0]
    drive = np.isin(cls, (C_ROAD, C_FOOT, C_PAVING, C_GROUND))
    dist = np.full(cls.shape, -1, int)
    q = deque()
    for r, c in zip(*np.nonzero(cls == C_ROAD)):
        dist[r, c] = 0
        q.append((r, c))
    while q:
        r, c = q.popleft()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rr, cc = r + dr, c + dc
            if 0 <= rr < n and 0 <= cc < n and dist[rr, cc] < 0 and drive[rr, cc] \
                    and abs(h[rr, cc] - h[r, c]) <= KERB:
                dist[rr, cc] = dist[r, c] + 1
                q.append((rr, cc))
    return dist


def place(s, others):
    n = s["n"]
    ox, oz = s["origin"]
    cls = np.array(s["cls"], int).reshape(n, n)  # [row = z, col = x]
    h = np.array(s["h"], float).reshape(n, n)
    dist = reachable(cls, h)
    # Room round buildings (and bridges, walls, banks): the canopy keeps
    # WALL_CLEAR off them, so it never looks pushed into a wall.
    solid = np.isin(cls, (C_BUILDING, C_OTHER))
    near_wall = solid.copy()
    for _ in range(WALL_CLEAR):
        grown = near_wall.copy()
        grown[1:, :] |= near_wall[:-1, :]
        grown[:-1, :] |= near_wall[1:, :]
        grown[:, 1:] |= near_wall[:, :-1]
        grown[:, :-1] |= near_wall[:, 1:]
        near_wall = grown
    ax, az = s["at"][0], s["at"][2]
    trees = [(p[1], p[3], p[4]) for p in s["props"] if p[0].startswith("tree")]
    poles = [(p[1], p[3]) for p in s["props"] if not p[0].startswith("tree") and p[0] != "parking"
             and not p[0].startswith("shrub") and not p[0].startswith("bush")]
    parking = [(p[1], p[3]) for p in s["props"] if p[0] == "parking"]
    # Candidate centres: every cell within REACH of the POI.
    cc = np.array([(ox + c, oz + r) for r in range(n) for c in range(n)
                   if math.hypot(ox + c - ax, oz + r - az) <= REACH], float)
    best = None
    for deg in range(0, 180, 15):
        yaw = math.radians(deg)
        ux, uz = frame(yaw)

        def cells(local):
            w = cc[:, None, :] + local[None, :, 0:1] * ux + local[None, :, 1:2] * uz
            col = np.rint(w[..., 0] - ox).astype(int)
            row = np.rint(w[..., 1] - oz).astype(int)
            inside = (col >= 0) & (col < n) & (row >= 0) & (row < n)
            return np.clip(row, 0, n - 1), np.clip(col, 0, n - 1), inside

        r, c, ok = cells(FOOT)
        fc = cls[r, c]
        good = ok.all(1) & np.isin(fc, (C_PAVING, C_GROUND)).all(1) & ~near_wall[r, c].any(1)
        fh = h[r, c]
        good &= (fh.max(1) - fh.min(1)) <= FLAT_ALL
        r2, c2, _ = cells(FLATP)
        bh = h[r2, c2]
        good &= (bh.max(1) - bh.min(1)) <= FLAT
        # Centre reachable from a road, not too far.
        rc, ccol, _ = cells(np.zeros((1, 2)))
        d = dist[rc[:, 0], ccol[:, 0]]
        good &= (d >= 0) & (d <= ROAD_STEPS)
        # A lane in at one end at least.
        lanes, lane_d = [], []
        for lane in (LANE_A, LANE_B):
            lr, lc, lok = cells(lane)
            ld = dist[lr, lc]
            lanes.append(lok.all(1) & (ld >= 0).all(1))
            lane_d.append(ld.min(1))
        if not (good & (lanes[0] | lanes[1])).any():
            continue
        # Clear of trees, poles, parking spots and other markers: distance
        # from each to the footprint rectangle, in the servo's frame.
        def clear_of(points, margin, xr=FOOT_X, zr=FOOT_Z):
            if len(points) == 0:
                return np.ones(len(cc), bool)
            p = np.array([q[:2] for q in points], float)
            m = np.array([q[2] if len(q) > 2 else 1.0 for q in points], float) * margin \
                if len(points[0]) > 2 else np.full(len(points), margin)
            rel = p[None, :, :] - cc[:, None, :]
            lx = rel @ ux
            lz = rel @ uz
            dx = np.maximum(np.maximum(xr[0] - lx, lx - xr[1]), 0)
            dz = np.maximum(np.maximum(zr[0] - lz, lz - zr[1]), 0)
            return (np.hypot(dx, dz) >= m[None, :]).all(1)

        good &= clear_of(trees, TREE_CLEAR) & clear_of(poles, POLE_CLEAR) & clear_of(parking, PARKING_CLEAR)
        good &= clear_of([tuple(o) for o in others], MARKER_CLEAR)
        # Nothing standing in the way in: trunks, poles or parked cars.
        trunks = [t[:2] for t in trees] + poles
        for i, zr in enumerate(((FOOT_Z[1], FOOT_Z[1] + LANE_Z), (FOOT_Z[0] - LANE_Z, FOOT_Z[0]))):
            lanes[i] = lanes[i] & clear_of(trunks, LANE_CLEAR, LANE_X, zr) \
                & clear_of(parking, PARKING_CLEAR, LANE_X, zr)
        good &= lanes[0] | lanes[1]
        if not good.any():
            continue
        grass = (fc == C_GROUND).mean(1)
        score = np.hypot(cc[:, 0] - ax, cc[:, 1] - az) + 0.3 * d + 12.0 * grass
        score[~good] = np.inf
        k = int(np.argmin(score))
        if best is None or score[k] < best[0]:
            y = float(np.median(bh[k]))
            # Which end of the bay opens onto the way in (+1: +z), for the
            # price sign.
            # (the one nearer a road when both are open).
            both = lanes[0][k] and lanes[1][k]
            open_end = 1 if lanes[0][k] and (not both or lane_d[0][k] <= lane_d[1][k]) else -1
            facing = yaw
            # The forecourt's ground, for the slab servo.gd lays on it: heights
            # (above y) on a 1 m grid over the footprint, in the frame of `facing`.
            fx, fz = frame(facing)
            slab = []
            for lz in SLAB_Z:
                for lx in SLAB_X:
                    wx, wz = cc[k] + lx * fx + lz * fz
                    slab.append(round(float(h[int(round(wz - oz)), int(round(wx - ox))]) - y, 2))
            best = (float(score[k]), cc[k].tolist(), y, facing, float(grass[k]), int(d[k]), slab, open_end)
    return best


def grids(s):
    n = s["n"]
    return (np.array(s["cls"], int).reshape(n, n), np.array(s["h"], float).reshape(n, n),
            s["origin"][0], s["origin"][1], n)


def ground_at(s, x, z, y, yaw):
    """The slab heights (above y) for a servo at x/z turned yaw, from the dump."""
    _, h, ox, oz, n = grids(s)
    fx, fz = frame(yaw)
    out = []
    for lz in SLAB_Z:
        for lx in SLAB_X:
            wx, wz = np.array([x, z]) + lx * fx + lz * fz
            r = min(max(int(round(wz - oz)), 0), n - 1)
            c = min(max(int(round(wx - ox)), 0), n - 1)
            out.append(round(float(h[r, c]) - y, 2))
    return out


def road_cells(s):
    cls, _, ox, oz, n = grids(s)
    rows, cols = np.nonzero(cls == C_ROAD)
    return np.column_stack([ox + cols, oz + rows]).astype(float)


_SEGS = None


def road_segments():
    """Every road's centre line as segments (x/z start, x/z end), from
    tools/places/dump_roads.gd's /tmp/roads.json. Not motorways: a servo
    never fronts one."""
    global _SEGS
    if _SEGS is None:
        a, b = [], []
        for r in json.loads(ROADS.read_text())["roads"]:
            if r.get("kind", "").startswith("motorway"):
                continue
            pts = np.asarray(r["pts"], float)[:, [0, 2]]
            if len(pts) > 1:
                a.append(pts[:-1])
                b.append(pts[1:])
        _SEGS = (np.concatenate(a), np.concatenate(b))
    return _SEGS


def sign_yaw(s, e):
    """Which way the price sign turns (about Y, in the servo's frame) so its
    faces look along the road the servo fronts (the nearest one to the sign):
    up and down the street."""
    a, b = road_segments()
    ux, uz = frame(e["yaw"])
    at = np.array(e["position"][0::2]) + SIGN[0] * ux + SIGN[1] * e["open_end"] * uz
    d = b - a
    t = np.clip(((at - a) * d).sum(1) / np.maximum((d * d).sum(1), 1e-9), 0.0, 1.0)
    k = int(np.argmin(np.hypot(*(a + d * t[:, None] - at).T)))
    road = d[k] / max(np.hypot(*d[k]), 1e-9)
    dx, dz = float(road @ ux), float(road @ uz)
    # A node turned t about Y has its +x at (cos t, -sin t) in its parent.
    t = math.atan2(-dz, dx)
    # Either way round reads the same (it has two faces): keep it small.
    if t > math.pi / 2:
        t -= math.pi
    elif t < -math.pi / 2:
        t += math.pi
    return round(t, 4)


def workshop_servos(ground):
    """Workshops that sell fuel, as servos where they stand."""
    index = json.loads((ROOT / "map/tiles/index.json").read_text())
    out = []
    for w in index.get("workshops", []):
        if "fuel" not in w.get("kinds", []) or "position" not in w:
            continue
        x, y, z = w["position"]
        s = min(ground["servos"], key=lambda g: math.hypot(g["at"][0] - x, g["at"][2] - z))
        if math.hypot(s["at"][0] - x, s["at"][2] - z) > 20.0:
            print(f"  workshop {w['id']}: no ground dumped near it")
            continue
        yaw = float(w.get("yaw", 0.0))
        # Open at the end nearer a road.
        roads = road_cells(s)
        ux, uz = frame(yaw)
        ends = [np.hypot(*(roads - (np.array([x, z]) + end * 10.0 * uz)).T).min() for end in (1, -1)]
        e = {"id": w["id"], "name": w.get("name", "Servo"), "suburb": "", "kinds": w["kinds"],
             "position": [x, y, z], "yaw": round(yaw, 4), "open_end": 1 if ends[0] <= ends[1] else -1,
             "ground": ground_at(s, x, z, y, yaw)}
        e["sign_yaw"] = sign_yaw(s, e)
        out.append(e)
        print(f"  workshop {w['id']}: servo layout, sign turned {math.degrees(e['sign_yaw']):.0f} deg")
    return out


def write(out):
    out.sort(key=lambda e: e["id"])
    comment = ("Servos on the map: OpenStreetMap fuel stations at least "
               f"{SPACING:.0f} m apart, each on open ground beside the real one, and the workshops "
               "that sell fuel (tools/places/place_servos.py). position is the middle of the pump bay; "
               "yaw turns scripts/world/servo.gd's frame; open_end is the end of the bay "
               "you drive in at (+1: +z); sign_yaw turns the price sign to face along the street; "
               "kinds (if there) is what the bay offers, else fuel; ground is the forecourt's height above "
               "position on a 1 m grid over the footprint (x fastest).")
    OUT.write_text('{"_comment": ' + json.dumps(comment) + ', "servos": [\n'
                   + ",\n".join(json.dumps(e) for e in out) + "\n]}\n")


def refresh():
    ground = json.loads(GROUND.read_text())
    dumps = {s["id"]: s for s in ground["servos"]}
    out = []
    for e in json.loads(OUT.read_text())["servos"]:
        if "kinds" in e:
            continue  # a workshop: redone below
        e["sign_yaw"] = sign_yaw(dumps[e["id"]], e)
        out.append(e)
        print(f"  {e['id']} {e['name']}: sign turned {math.degrees(e['sign_yaw']):.0f} deg")
    out += workshop_servos(ground)
    write(out)
    print(f"{len(out)} servos -> {OUT.relative_to(ROOT)}")


def main():
    if REFRESH:
        refresh()
        return
    ground = json.loads(GROUND.read_text())
    others, fuel = markers()
    placed, missed = [], []
    for s in ground["servos"]:
        ax, az = s["at"][0], s["at"][2]
        if any(math.hypot(ax - f[0], az - f[1]) < FUEL_WORKSHOP for f in fuel):
            print(f"  {s['id']} {s['name']} ({s['suburb']}): a workshop already sells fuel here")
            continue
        best = place(s, others)
        if best is None:
            missed.append(s)
            print(f"  {s['id']} {s['name']} ({s['suburb']}): nowhere fits")
            continue
        placed.append((s, best))
    # Real servos come in clumps (two across the road from each other); the
    # game needs one every SPACING metres or so. Best placed first.
    keep = [tuple(f) for f in fuel]
    out = []
    for s, best in sorted(placed, key=lambda sb: sb[1][0]):
        score, (x, z), y, yaw, grass, d, slab, open_end = best
        near = min((math.hypot(x - k[0], z - k[1]) for k in keep), default=math.inf)
        if near < SPACING:
            continue
        keep.append((x, z))
        suburb = s.get("suburb", "")
        out.append({"id": s["id"], "name": f"{suburb} servo" if suburb else "Servo", "suburb": suburb,
                    "position": [round(x, 2), round(y, 2), round(z, 2)],
                    "yaw": round(math.atan2(math.sin(yaw), math.cos(yaw)), 4), "open_end": open_end, "ground": slab})
        print(f"  KEEP {s['id']} {s['name']} ({suburb}): moved {math.hypot(x - s['at'][0], z - s['at'][2]):.0f} m, "
              f"{grass:.0%} grass, {d} m from a road, nearest other servo {near:.0f} m")
    dumps = {s["id"]: s for s in ground["servos"]}
    for e in out:
        e["sign_yaw"] = sign_yaw(dumps[e["id"]], e)
    out += workshop_servos(ground)
    write(out)
    print(f"{len(out)} servos kept of {len(placed)} that fit; {len(missed)} with nowhere that fits "
          f"-> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
