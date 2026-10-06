"""Classification rules: road widths, land cover, building heights and facades."""
from __future__ import annotations

import re

import numpy as np

from .common import stable_rng

# --- Roads -----------------------------------------------------------------

DRIVABLE = {
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "living_street", "service", "busway", "track", "road",
}
FOOT = {"footway", "path", "cycleway", "pedestrian", "steps", "bridleway", "corridor"}

# Default lane count (total, both directions) and lane width per class.
LANES = {
    "motorway": 3, "trunk": 4, "primary": 4, "secondary": 2, "tertiary": 2,
    "motorway_link": 1, "trunk_link": 1, "primary_link": 1, "secondary_link": 1,
    "tertiary_link": 1, "unclassified": 2, "residential": 2, "living_street": 2,
    "service": 1, "busway": 2, "track": 1, "road": 2,
}
LANE_WIDTH = 3.3
ONEWAY_MIN_WIDTH = 6.0   # a one-way street: one lane plus kerbside parking
PAIRED_MIN_WIDTH = 5.0   # one carriageway of a divided road
LINK_MIN_WIDTH = 4.5     # slip roads and ramps
# Classes that get a footpath strip alongside them.
SIDEWALK = {"primary", "secondary", "tertiary", "residential", "unclassified",
            "living_street", "primary_link", "secondary_link", "tertiary_link", "trunk"}
SIDEWALK_WIDTH = 2.6
FOOT_WIDTH = {"footway": 2.0, "path": 1.6, "cycleway": 2.6, "pedestrian": 5.0,
              "steps": 2.0, "bridleway": 2.0, "corridor": 2.0}


def _num(v, default=None):
    if v is None:
        return default
    m = re.match(r"\s*([0-9]+(?:\.[0-9]+)?)", str(v))
    return float(m.group(1)) if m else default


def is_oneway(tags) -> bool:
    return tags.get("oneway") in ("yes", "1", "true") or tags.get("junction") == "roundabout" or \
        tags.get("highway") in ("motorway", "motorway_link")


def road_lanes(tags) -> int:
    if "_lanes" in tags:  # one lane count for the whole street (streets.normalise)
        return int(tags["_lanes"])
    hw = tags.get("highway")
    lanes = _num(tags.get("lanes"))
    if lanes is None:
        lanes = LANES.get(hw, 2)
        if is_oneway(tags) and hw not in ("motorway",) and not hw.endswith("_link") and hw != "service":
            lanes = max(1, lanes // 2)
    return max(1, int(lanes))


def road_width(tags, paired: bool = False) -> float:
    """Carriageway width. OSM `width` tags are ignored: some give the
    carriageway, some the whole road reserve, and they disagree from one
    segment to the next. `paired`: one carriageway of a divided road."""
    if "_width" in tags:  # set per street by streets.normalise
        return float(tags["_width"])
    hw = tags.get("highway")
    if hw == "service":
        return 4.0 if tags.get("service") in ("alley", "driveway", "parking_aisle") else 5.0
    if hw == "track":
        return 3.0
    w = road_lanes(tags) * LANE_WIDTH + (0.8 if hw in ("motorway", "trunk") else 0.0)
    if hw.endswith("_link"):
        return max(w, LINK_MIN_WIDTH)
    if (is_oneway(tags) or tags.get("oneway") == "-1") and hw != "motorway":
        return max(w, PAIRED_MIN_WIDTH if paired else ONEWAY_MIN_WIDTH)
    return w


def is_bridge(tags) -> bool:
    return tags.get("bridge") not in (None, "no")


def is_tunnel(tags) -> bool:
    return tags.get("tunnel") in ("yes", "culvert")  # building_passage stays at grade


def layer(tags) -> int:
    try:
        return int(float(tags.get("layer", "0")))
    except ValueError:
        return 0


# --- Land cover --------------------------------------------------------------

# (material, priority): higher priority wins where polygons overlap.
def landcover(tags) -> tuple[str, int] | None:
    nat, lu, lei, am = tags.get("natural"), tags.get("landuse"), tags.get("leisure"), tags.get("amenity")
    if nat == "water" or lu in ("basin", "reservoir") or tags.get("water") or \
            tags.get("waterway") == "riverbank" or lei == "swimming_pool":
        return ("water", 100)
    if nat in ("beach", "sand") or lei == "beach_resort":
        return ("sand", 60)
    if nat == "wetland":
        return ("wetland", 55)
    if tags.get("man_made") in ("breakwater", "groyne"):
        return ("ballast", 65)  # rock walls (build.World._raise_moles)
    if nat in ("wood", "scrub", "heath") or lu in ("forest",):
        return ("bush", 50)
    if lei in ("pitch", "golf_course", "stadium", "track") and tags.get("surface") not in ("asphalt", "concrete"):
        return ("turf", 45)
    if lei in ("park", "garden", "playground", "dog_park", "recreation_ground", "common", "nature_reserve") or \
            lu in ("grass", "recreation_ground", "village_green", "cemetery", "meadow", "flowerbed",
                   "allotments", "orchard", "greenfield") or nat == "grassland" or \
            tags.get("golf") in ("fairway", "green", "tee", "rough"):
        return ("grass", 40)
    if am in ("parking", "fuel", "bus_station") or lu in ("garages",) or tags.get("area:highway") or \
            (tags.get("highway") in ("pedestrian", "service", "footway") and tags.get("area") == "yes") or \
            tags.get("place") == "square" or tags.get("man_made") in ("pier",):
        return ("paving", 70)
    if lu in ("construction", "brownfield", "railway", "landfill", "quarry"):
        return ("dirt", 35)
    if lu in ("industrial",):
        return ("concrete", 20)
    if am in ("school", "university", "college", "hospital") or lu in ("residential", "commercial", "retail"):
        return None  # keep the zone's default ground
    return None


def ground_default(zone: str) -> str:
    return "ground_urban"


# --- Buildings ---------------------------------------------------------------

LEVEL_H = 3.2

HOUSE_TYPES = {"house", "detached", "semidetached_house", "terrace", "bungalow", "residential", "duplex"}
SHED_TYPES = {"garage", "garages", "shed", "carport", "hut", "cabin", "kiosk", "toilets", "roof", "shelter"}


def building_height(tags, area_m2: float, osm_id: int, cbd: bool) -> tuple[float, float]:
    """Return (min_height, height) above ground in metres."""
    rng = stable_rng("bh", osm_id)
    h = _num(tags.get("height"))
    lv = _num(tags.get("building:levels"))
    roof_lv = _num(tags.get("roof:levels"), 0.0)
    if h is None and lv is not None:
        h = (lv + roof_lv) * LEVEL_H + (1.0 if lv > 2 else 0.4)
    minh = _num(tags.get("min_height"))
    if minh is None:
        ml = _num(tags.get("building:min_level"))
        minh = ml * LEVEL_H if ml is not None else 0.0
    if h is None:
        b = tags.get("building") or tags.get("building:part") or "yes"
        if b in SHED_TYPES:
            h = 2.8 + rng.random() * 0.6
        elif b in ("house", "detached", "bungalow", "semidetached_house", "duplex"):
            h = (1 if rng.random() < 0.7 else 2) * LEVEL_H + 0.6
        elif b in ("terrace", "residential"):
            h = (2 if area_m2 < 400 else 3) * LEVEL_H + 0.6
        elif b in ("apartments", "flats", "hotel", "dormitory"):
            h = rng.integers(3, 9) * LEVEL_H + 1
        elif b in ("church", "cathedral", "chapel"):
            h = 12 + rng.random() * 6
        elif b in ("industrial", "warehouse", "hangar", "factory", "storage_tank"):
            h = 6 + rng.random() * 4
        elif b in ("parking", "multi-storey"):
            h = rng.integers(3, 7) * 3.0
        elif b in ("train_station", "transportation", "stadium", "grandstand"):
            h = 9 + rng.random() * 6
        elif cbd:
            if area_m2 > 1500:
                h = rng.integers(8, 30) * LEVEL_H
            elif area_m2 > 400:
                h = rng.integers(3, 12) * LEVEL_H
            else:
                h = rng.integers(2, 5) * LEVEL_H
        else:
            if area_m2 < 60:
                h = 3.0
            elif area_m2 < 250:
                h = (1 if rng.random() < 0.6 else 2) * LEVEL_H + 0.5
            elif area_m2 < 1200:
                h = rng.integers(1, 4) * LEVEL_H + 0.8
            else:
                h = rng.integers(2, 5) * LEVEL_H + 1
    h = float(np.clip(h, minh + 2.2, 320.0))
    return minh, h


def facade(tags, height: float, area_m2: float, cbd: bool, osm_id: int) -> tuple[str, str]:
    """(ground floor material, upper floors material)."""
    b = tags.get("building") or tags.get("building:part") or "yes"
    rng = stable_rng("fac", osm_id)
    if tags.get("historic") or tags.get("heritage") or b in ("church", "cathedral", "chapel"):
        return "facade_heritage", "facade_heritage"
    if b in SHED_TYPES:
        return "facade_shed", "facade_shed"
    if b in ("industrial", "warehouse", "hangar", "factory"):
        return "facade_warehouse", "facade_warehouse"
    if b in ("parking", "multi-storey"):
        return "facade_carpark", "facade_carpark"
    if b in ("house", "detached", "bungalow", "semidetached_house", "duplex", "terrace") or \
            (not cbd and b in ("yes", "residential") and height < 8 and area_m2 < 400):
        return ("facade_brick", "facade_brick") if rng.random() < 0.6 else ("facade_render", "facade_render")
    if b in ("apartments", "flats", "residential", "dormitory", "hotel"):
        return "facade_apartment", "facade_apartment"
    if height > 40:
        return ("facade_glass", "facade_glass") if rng.random() < 0.6 else ("facade_office", "facade_office")
    if b in ("retail", "commercial", "supermarket", "kiosk") or (cbd and height < 20):
        return "facade_shopfront", ("facade_office" if height > 12 else "facade_upper")
    if height > 12:
        return "facade_office", "facade_office"
    return "facade_shopfront" if cbd else "facade_render", "facade_upper"


def roof_kind(tags, area_m2: float, height: float, rect_ratio: float) -> str:
    shape = tags.get("roof:shape")
    if shape in ("gabled", "hipped", "pyramidal", "half-hipped", "gambrel"):
        return "gabled" if rect_ratio > 0.75 else "flat"
    if shape:
        return "flat"
    b = tags.get("building") or "yes"
    if b in ("house", "detached", "bungalow", "semidetached_house", "duplex", "terrace", "garage", "shed") or \
            (b in ("yes", "residential") and height < 8 and area_m2 < 350):
        return "gabled" if rect_ratio > 0.8 else "flat"
    return "flat"
