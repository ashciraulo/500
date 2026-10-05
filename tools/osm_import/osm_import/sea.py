"""The ocean, from OSM's coastline: land is on the coastline's left, water on
its right. Used by build.World (the tiles' sea) and overview (the backdrop's)."""
from __future__ import annotations

import numpy as np
import shapely


def sea_polygon(coast, frame):
    """The sea inside `frame` (a shapely box), or None. `coast` is the merged
    coastline (a LineString or MultiLineString in plan metres)."""
    if coast is None:
        return None
    lines = shapely.intersection(coast, frame)
    if lines.is_empty:
        return None
    faces = list(shapely.polygonize([shapely.union_all([lines, frame.exterior])]).geoms)
    # Points just to the right of the coastline are in the sea.
    probes = []
    for ln in getattr(lines, "geoms", [lines]):
        if ln.geom_type != "LineString" or ln.length < 4:
            continue
        side = ln.offset_curve(-1.0)
        for d in np.linspace(0, side.length, max(int(side.length // 25), 2)):
            probes.append(side.interpolate(d))
    if not faces or not probes:
        return None
    tree = shapely.STRtree(probes)
    sea = [f for f in faces if len(tree.query(f, predicate="contains"))]
    return shapely.union_all(sea) if sea else None


def merged_coast(ways):
    """The coastline ways (extract.Way with natural=coastline), merged."""
    from shapely.geometry import LineString
    lines = [LineString(w.coords) for w in ways if w.tags.get("natural") == "coastline"]
    return shapely.line_merge(shapely.union_all(lines)) if lines else None
