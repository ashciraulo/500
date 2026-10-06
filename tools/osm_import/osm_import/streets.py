"""Street layout: one width per street, and no roads drawn through buildings.

OSM tags lanes segment by segment. A street is lanes=2 mid-block, lanes=4
where turn lanes open up at the lights, untagged on the next block, and a
one-way stretch of it falls back to half the class default. Taken per way,
that made a street step between 3.3 m and 13 m at random joins (1,379 such
steps in the first slice alone). Here every way of one street (same name or
ref, class and direction) gets the street's typical lane count: the
length-weighted median of the lanes its ways are tagged with. `width` tags
are ignored on roads: a few are carriageway widths, others the whole road
reserve, and they disagree with the next segment either way.

A one-way street keeps the width of a normal street (one lane plus kerbside
parking) unless it is one half of a divided road, so a street that turns
one-way for a block doesn't shrink to a single lane.

Car park aisles on upper decks and in basements, and service roads that run
inside buildings, are dropped: drawn at street level they poked asphalt and
kerbs out of the buildings above them, and traffic drove into the walls.

`normalise()` writes the result into each road's tags as `_lanes` and
`_width`, which `styles.road_lanes()` and `styles.road_width()` read first,
so the road surface, lane markings, carriageway levelling and the traffic
lanes all agree.
"""
from __future__ import annotations

from dataclasses import replace

import numpy as np
import shapely
from shapely.geometry import LineString

from . import styles
from .heights import way_group

# Most lanes a street of each class is given (both directions / one direction).
MAX_LANES = {
    "motorway": 8, "trunk": 6, "primary": 6, "secondary": 4, "tertiary": 4,
    "unclassified": 4, "residential": 2, "living_street": 2, "busway": 2, "road": 2,
}
MAX_LANES_ONEWAY = {
    "motorway": 5, "trunk": 4, "primary": 4, "secondary": 3, "tertiary": 2,
    "unclassified": 2, "residential": 2, "living_street": 1, "busway": 1, "road": 2,
}
MAX_LANES_LINK = 2
PAIR_REACH = 30.0        # the other carriageway of a divided road is this close
INSIDE_BUILDING = 0.5    # share of a service road's length under buildings that drops it


def _base_class(hw: str) -> str:
    return hw[:-5] if hw.endswith("_link") else hw


def _tagged_lanes(tags) -> int | None:
    v = styles._num(tags.get("lanes"))
    return int(v) if v and v >= 1 else None


def _default_lanes(tags) -> int:
    return styles.road_lanes({k: v for k, v in tags.items() if k not in ("lanes", "_lanes")})


def _length(w) -> float:
    return float(np.linalg.norm(np.diff(w.coords, axis=0), axis=1).sum())


def _weighted_median(values, weights) -> float:
    order = np.argsort(values)
    v, wt = np.asarray(values, float)[order], np.asarray(weights, float)[order]
    c = np.cumsum(wt)
    return float(v[np.searchsorted(c, c[-1] / 2)])


def street_key(w):
    """Ways of one street share a key; an unnamed way is a street of its own."""
    t = w.tags
    label = t.get("name") or t.get("ref")
    if not label:
        return ("way", w.id)
    return (label, t["highway"], styles.is_oneway(t) or t.get("oneway") == "-1")


def _levels_off_ground(tags) -> bool:
    lv = tags.get("level")
    if not lv:
        return False
    vals = [styles._num(p.strip().lstrip("-")) for p in lv.split(";")]
    return all(v is not None and v != 0 for v in vals)


def off_grade(tags) -> bool:
    """A car park aisle or service road on another deck than the street."""
    if tags.get("highway") != "service" or styles.is_bridge(tags) or styles.is_tunnel(tags):
        return False
    return styles.layer(tags) != 0 or tags.get("location") in ("underground", "roof", "rooftop", "indoor") \
        or _levels_off_ground(tags)


def _inside_buildings(ways, buildings) -> set[int]:
    """Ids of service roads that run mostly inside building footprints."""
    if not buildings:
        return set()
    tree = shapely.STRtree(buildings)
    out = set()
    for w in ways:
        t = w.tags
        if t.get("highway") != "service" or styles.is_bridge(t) or styles.is_tunnel(t):
            continue
        line = LineString(w.coords)
        if line.length < 1e-6:
            continue
        idx = tree.query(line, predicate="intersects")
        if not len(idx):
            continue
        under = line.intersection(shapely.union_all([buildings[i] for i in idx])).length
        if under >= INSIDE_BUILDING * line.length:
            out.add(w.id)
    return out


def _tangent(line: LineString, s: float) -> np.ndarray:
    a = np.array(line.interpolate(max(0.0, s - 2.0)).coords[0])
    b = np.array(line.interpolate(min(line.length, s + 2.0)).coords[0])
    d = b - a
    n = np.linalg.norm(d)
    return d / n if n > 1e-9 else d


def paired_oneways(ways) -> set[int]:
    """Ids of one-way roads running beside an opposite one-way of the same
    name: the two carriageways of a divided road."""
    named = [w for w in ways if styles.is_oneway(w.tags) and w.tags.get("name") and len(w.coords) > 1
             and not w.tags["highway"].endswith("_link") and w.tags.get("junction") != "roundabout"]
    if len(named) < 2:
        return set()
    lines = [LineString(w.coords[::-1] if w.tags.get("oneway") == "-1" else w.coords) for w in named]
    tree = shapely.STRtree(lines)
    out = set()
    for i, (w, la) in enumerate(zip(named, lines)):
        for j in tree.query(la, predicate="dwithin", distance=PAIR_REACH):
            if j == i or named[j].tags["name"] != w.tags["name"]:
                continue
            lb = lines[j]
            for f in (0.25, 0.5, 0.75):
                sa = la.length * f
                p = la.interpolate(sa)
                if lb.distance(p) > PAIR_REACH:
                    continue
                if _tangent(la, sa) @ _tangent(lb, lb.project(p)) < -0.7:
                    out.add(w.id)
                    break
            if w.id in out:
                break
    return out


def street_lanes(ways) -> dict[int, int]:
    """{way id: lanes} with one lane count per street."""
    groups: dict = {}
    for w in ways:
        groups.setdefault(street_key(w), []).append(w)
    out = {}
    for group in groups.values():
        tagged = [(_tagged_lanes(w.tags), _length(w)) for w in group]
        tagged = [(n, max(L, 1.0)) for n, L in tagged if n]
        if tagged:
            lanes = int(round(_weighted_median([n for n, _ in tagged], [L for _, L in tagged])))
        else:
            lanes = _default_lanes(group[0].tags)
        t = group[0].tags
        hw = t["highway"]
        if hw.endswith("_link"):
            cap = MAX_LANES_LINK
        elif styles.is_oneway(t) or t.get("oneway") == "-1":
            cap = MAX_LANES_ONEWAY.get(_base_class(hw), 2)
        else:
            cap = MAX_LANES.get(_base_class(hw), 2)
        lanes = int(np.clip(lanes, 1, cap))
        for w in group:
            out[w.id] = lanes
    return out


def normalise(ways, buildings=()) -> list:
    """`ways` with off-grade service roads dropped and every road's `_lanes`
    and `_width` set per street. Other ways pass through unchanged."""
    roads = [w for w in ways if way_group(w.tags) == "road"]
    drop = {w.id for w in roads if off_grade(w.tags)} | _inside_buildings(roads, list(buildings))
    roads = [w for w in roads if w.id not in drop]
    lanes = street_lanes(roads)
    paired = paired_oneways(roads)
    out = []
    for w in ways:
        if w.id in drop and way_group(w.tags) == "road":
            continue
        if w.id not in lanes or way_group(w.tags) != "road":
            out.append(w)
            continue
        t = dict(w.tags)
        n = lanes[w.id]
        t["_lanes"] = str(n)
        t["_width"] = f"{styles.road_width(t, w.id in paired):.2f}"
        fwd = _tagged_lanes({"lanes": t.get("lanes:forward")})
        back = _tagged_lanes({"lanes": t.get("lanes:backward")})
        fits = (fwd and back and fwd + back == n) or (bool(fwd) != bool(back) and (fwd or back) < n)
        if (fwd or back) and not fits:
            # Turn lanes at the lights, not the street's own split.
            t.pop("lanes:forward", None)
            t.pop("lanes:backward", None)
        out.append(replace(w, tags=t))
    return out
