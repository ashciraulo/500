#!/usr/bin/env python3
"""Places the gameplay markers on the real map: badges, photo spots, parking
challenges, barn finds, the car meet, scenic drives and time-trial
checkpoints. Writes data/world/places.json.

Positions come from the map's road data, so re-run this after the map is
regenerated:

    godot --headless --path . --script res://tools/places/dump_roads.gd   # writes /tmp/roads.json
    python3 tools/places/gen_places.py [/tmp/roads.json]

Everything is picked by road name, so the output is stable between runs.
"""
import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROADS = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/roads.json")
OUT = ROOT / "data/world/places.json"

data = json.loads(ROADS.read_text())
roads = data["roads"]
by_name = {}
for r in roads:
    if r["name"]:
        by_name.setdefault(r["name"], []).append(r)

WIDTH = {"motorway": 11.0, "trunk": 10.0, "primary": 10.0, "secondary": 9.0, "tertiary": 8.0}


def samples(name):
    """Every centreline point on roads with this name, with its direction and road width."""
    out = []
    for r in by_name.get(name, []):
        pts = r["pts"]
        width = WIDTH.get(r["kind"], 6.5)
        if r.get("oneway"):
            width *= 0.6
        for i, p in enumerate(pts):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            dx, dz = b[0] - a[0], b[2] - a[2]
            n = math.hypot(dx, dz) or 1.0
            out.append((p, (dx / n, dz / n), width))
    if not out:
        raise SystemExit(f"no road called {name!r} in the map")
    return out


def along(name, t):
    """The point a fraction t along the road's longest axis."""
    s = samples(name)
    xs = [p[0][0] for p in s]
    zs = [p[0][2] for p in s]
    axis = 0 if max(xs) - min(xs) > max(zs) - min(zs) else 2
    s.sort(key=lambda q: q[0][axis])
    return s[min(int(t * (len(s) - 1)), len(s) - 1)]


def near(name, x, z):
    return min(samples(name), key=lambda q: (q[0][0] - x) ** 2 + (q[0][2] - z) ** 2)


def place(sample, side=0.0):
    """Offset sideways from the centreline: side is in road half-widths (1 = kerb), positive = left."""
    p, (dx, dz), width = sample
    # Left of the direction of travel (Perth drives on the left).
    lx, lz = dz, -dx
    off = side * width * 0.5
    yaw = math.atan2(-dx, -dz)
    return [round(p[0] + lx * off, 2), round(p[1], 2), round(p[2] + lz * off, 2)], round(yaw, 3)


def entry(sample, side=0.0, **extra):
    pos, yaw = place(sample, side)
    e = {"p": pos, "yaw": yaw}
    e.update(extra)
    return e


# --- photo spots -------------------------------------------------------------
PHOTO_SPOTS = [
    ("kings_park_fraser", "Fraser Avenue's lemon-scented gums", ("Fraser Avenue", 0.5)),
    ("kings_park_may", "May Drive through the bush", ("May Drive", 0.4)),
    ("kings_park_lovekin", "Lovekin Drive honour avenues", ("Lovekin Drive", 0.6)),
    ("kings_park_forrest", "Forrest Drive at dusk", ("Forrest Drive", 0.5)),
    ("kings_park_road", "Kings Park Road", ("Kings Park Road", 0.3)),
    ("mounts_bay_narrows", "The Narrows from Mounts Bay Road", ("Mounts Bay Road", 0.82)),
    ("mounts_bay_cliffs", "Under the Kings Park scarp", ("Mounts Bay Road", 0.6)),
    ("mounts_bay_crawley", "Mounts Bay Road, Crawley", ("Mounts Bay Road", 0.15)),
    ("riverside_east", "Riverside Drive and the river", ("Riverside Drive", 0.7)),
    ("riverside_quay", "Riverside Drive by the quay", ("Riverside Drive", 0.2)),
    ("the_esplanade", "The Esplanade", ("The Esplanade", 0.5)),
    ("barrack_street", "Barrack Street jetty end", ("Barrack Street", 0.9)),
    ("st_georges_tce", "St Georges Terrace towers", ("St Georges Terrace", 0.5)),
    ("hay_street", "Hay Street", ("Hay Street", 0.55)),
    ("murray_street", "Murray Street", ("Murray Street", 0.5)),
    ("william_street", "William Street, Northbridge", ("William Street", 0.3)),
    ("james_street", "James Street lights", ("James Street", 0.5)),
    ("lake_street", "Lake Street", ("Lake Street", 0.6)),
    ("beaufort_street", "Beaufort Street strip", ("Beaufort Street", 0.25)),
    ("newcastle_street", "Newcastle Street", ("Newcastle Street", 0.6)),
    ("bulwer_street", "Bulwer Street", ("Bulwer Street", 0.4)),
    ("adelaide_tce", "Adelaide Terrace", ("Adelaide Terrace", 0.5)),
    ("royal_street", "Royal Street, East Perth", ("Royal Street", 0.5)),
    ("mill_point", "Mill Point Road skyline", ("Mill Point Road", 0.15)),
    ("south_perth_esplanade", "South Perth foreshore", ("South Perth Esplanade", 0.5)),
    ("mends_street", "Mends Street ferry end", ("Mends Street", 0.9)),
    ("coode_street", "Coode Street", ("Coode Street", 0.2)),
    ("rokeby_road", "Rokeby Road, Subiaco", ("Rokeby Road", 0.5)),
    ("hamersley_road", "Hamersley Road", ("Hamersley Road", 0.5)),
    ("havelock_street", "Havelock Street, West Perth", ("Havelock Street", 0.5)),
]

# --- parking challenges ------------------------------------------------------
# Parallel bays at the kerb, between two parked cars. Length is the gap.
PARKING = [
    ("james_st_gap", "James Street squeeze", ("James Street", 0.35), 4.6),
    ("aberdeen_gap", "Aberdeen Street", ("Aberdeen Street", 0.5), 4.8),
    ("lake_st_gap", "Lake Street", ("Lake Street", 0.3), 4.5),
    ("bulwer_gap", "Bulwer Street", ("Bulwer Street", 0.7), 4.7),
    ("havelock_gap", "Havelock Street", ("Havelock Street", 0.3), 4.6),
    ("royal_st_gap", "Royal Street", ("Royal Street", 0.7), 4.4),
    ("mends_gap", "Mends Street", ("Mends Street", 0.4), 4.5),
    ("hay_st_gap", "Hay Street, West Perth", ("Hay Street", 0.3), 4.3),
    ("rokeby_gap", "Rokeby Road", ("Rokeby Road", 0.3), 4.4),
    ("coode_gap", "Coode Street", ("Coode Street", 0.6), 4.2),
]

# --- barn finds ---------------------------------------------------------------
# (car id, where, rumour, road, (x, z) to snap near or t along the road)
BARN_FINDS = [
    ("classic_500f", "a lock-up garage off Bulwer Street", "Old bloke on Bulwer Street had a 500 in his garage for forty years. Never drove it.", "Bulwer Street", 0.55),
    ("classic_d", "under a tarp in a Northbridge laneway", "There's a car-shaped tarp behind the shops on Aberdeen Street. Rear-hinged doors, they reckon.", "Aberdeen Street", 0.75),
    ("classic_nuova", "a carport in Subiaco", "A widow on Hensman Road wants the little car in the carport gone. 1958, apparently.", "Hensman Road", 0.4),
    ("classic_sport", "a West Perth service lane", "Someone saw a red stripe under the dust in a lane off Havelock Street.", "Havelock Street", 0.75),
    ("classic_giardiniera", "behind a South Perth corner shop", "The corner shop near Coode Street used a little Fiat wagon for deliveries. It's still out the back.", "Coode Street", 0.8),
    ("classic_500l", "an East Perth warehouse", "The warehouse on Royal Street is being cleared. There's a chrome-bumpered 500 in there.", "Royal Street", 0.25),
    ("classic_500r", "a Shenton Park backyard", "A 1974 R in a backyard on Onslow Road. Last of the line, needs everything.", "Onslow Road", 0.5),
    ("classic_abarth_595", "a Kensington shed", "Scorpion badges spotted through a shed window on Kensington Street.", "Kensington Street", 0.5),
    ("classic_abarth_695", "under the Narrows Bridge", "Fishermen under the Narrows say there's an old Abarth dumped by the pylons. Engine lid propped open.", "Mounts Bay Road", (-470.0, 1760.0)),
    ("classic_jolly", "on the South Perth foreshore after midnight", "A beach car with wicker seats and no doors. Only seen on the foreshore between midnight and four.", "South Perth Esplanade", 0.3),
]

# --- scenic drives ------------------------------------------------------------
SCENIC = [
    ("kings_park_sunset", "Kings Park at sunset", [("Fraser Avenue", 0.1), ("Fraser Avenue", 0.9), ("May Drive", 0.6), ("Lovekin Drive", 0.4), ("Forrest Drive", 0.3)]),
    ("riverside", "Riverside Drive", [("Riverside Drive", 0.05), ("Riverside Drive", 0.5), ("Riverside Drive", 0.95)]),
    ("mounts_bay", "Mounts Bay Road under the scarp", [("Mounts Bay Road", 0.9), ("Mounts Bay Road", 0.55), ("Mounts Bay Road", 0.1)]),
    ("south_perth", "South Perth foreshore", [("Mill Point Road", 0.1), ("South Perth Esplanade", 0.2), ("South Perth Esplanade", 0.8), ("Mends Street", 0.8)]),
    ("northbridge_lights", "Northbridge lights", [("James Street", 0.2), ("Lake Street", 0.5), ("Aberdeen Street", 0.6), ("William Street", 0.3)]),
]

# --- time trials ----------------------------------------------------------------
# Checkpoints become JobSites (kind "trial", not discoverable); trials.json
# routes reference them by id.
TRIALS = {
    "kings_park_loop": [("Fraser Avenue", 0.1), ("May Drive", 0.5), ("Lovekin Drive", 0.5), ("Forrest Drive", 0.6), ("Fraser Avenue", 0.85)],
    "mounts_bay_dusk": [("Mounts Bay Road", 0.95), ("Mounts Bay Road", 0.6), ("Mounts Bay Road", 0.2)],
    "riverside_run": [("Riverside Drive", 0.0), ("Riverside Drive", 0.5), ("Riverside Drive", 1.0)],
    "beaufort_sprint": [("Beaufort Street", 0.95), ("Beaufort Street", 0.5), ("Beaufort Street", 0.05)],
    "northbridge_night": [("James Street", 0.1), ("Lake Street", 0.7), ("Newcastle Street", 0.6), ("William Street", 0.4), ("James Street", 0.6)],
    "freeway_onramp": [("Mitchell Freeway", 0.2), ("Mitchell Freeway", 0.6)],
    "south_perth_sprint": [("Mill Point Road", 0.05), ("Mill Point Road", 0.5), ("South Perth Esplanade", 0.6)],
    "subiaco_climb": [("Hay Street", 0.05), ("Rokeby Road", 0.6), ("Hamersley Road", 0.5)],
    "canning_hwy": [("Canning Highway", 0.25), ("Canning Highway", 0.5), ("Canning Highway", 0.75)],
    "coast_road": [("Marine Parade", 0.5), ("West Coast Highway", 0.3), ("West Coast Highway", 0.7)],
}


def at(spec):
    name, where = spec
    return near(name, *where) if isinstance(where, tuple) else along(name, where)


def badges(count=60, spacing=260.0):
    rng = random.Random(500)
    pool = [r for r in roads if r["kind"] in ("residential", "living_street", "unclassified", "tertiary", "secondary")]
    rng.shuffle(pool)
    chosen = []
    for r in pool:
        if len(chosen) >= count:
            break
        pts = r["pts"]
        if len(pts) < 2:
            continue
        i = rng.randrange(len(pts) - 1)
        a, b = pts[i], pts[i + 1]
        dx, dz = b[0] - a[0], b[2] - a[2]
        n = math.hypot(dx, dz)
        if n < 4.0:
            continue
        t = rng.random()
        p = [a[0] + dx * t, a[1] + (b[1] - a[1]) * t, a[2] + dz * t]
        if any((p[0] - c["p"][0]) ** 2 + (p[2] - c["p"][2]) ** 2 < spacing ** 2 for c in chosen):
            continue
        width = WIDTH.get(r["kind"], 6.5)
        e = entry((p, (dx / n, dz / n), width), rng.choice([-0.45, 0.45]))
        e["id"] = "b%02d" % (len(chosen) + 1)
        e["hint"] = r["name"] or "a side street"
        chosen.append(e)
    return chosen


def main():
    out = {
        "_comment": "Generated by tools/places/gen_places.py from the map's roads. Re-run after regenerating the map. Positions are [x, y, z] world metres; y is the road surface.",
        "photo_spots": [entry(at(spec), 1.2, id=i, title=t) for i, t, spec in PHOTO_SPOTS],
        "parking": [entry(at(spec), 0.9, id=i, title=t, gap=g) for i, t, spec, g in PARKING],
        "barn_finds": [],
        "scenic_drives": [],
        "checkpoints": [],
        "badges": badges(),
        "car_meet": entry(along("Roe Street", 0.55), 1.6, id="roe_st_meet", title="Roe Street car park meet"),
    }
    for car, where, rumour, road, loc in BARN_FINDS:
        e = entry(near(road, *loc) if isinstance(loc, tuple) else along(road, loc), 1.7, car=car, where=where, rumour=rumour)
        if car == "classic_jolly":
            e["hours"] = [0, 4]
        out["barn_finds"].append(e)
    for i, t, specs in SCENIC:
        out["scenic_drives"].append({"id": i, "title": t, "points": [place(at(s))[0] for s in specs]})
    for trial, specs in TRIALS.items():
        for n, s in enumerate(specs):
            e = entry(at(s), 0.0, id="cp_%s_%d" % (trial, n))
            out["checkpoints"].append(e)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=1) + "\n")
    print("wrote", OUT.relative_to(ROOT), {k: len(v) for k, v in out.items() if isinstance(v, list)})


main()
