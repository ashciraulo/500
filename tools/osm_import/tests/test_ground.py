"""Smooth roads and ground: road profiles and the ground fitted to them."""
import numpy as np
from shapely.geometry import box

from osm_import import styles
from osm_import.build import LinearWay, World
from osm_import.extract import Way
from osm_import.heights import densify_ways, compute_node_heights
from osm_import.terrain import HeightField

STEP = 5.0


def field(fn, size=600.0):
    n = int(size / STEP) + 1
    x = -size / 2 + np.arange(n) * STEP
    E, N = np.meshgrid(x, x)
    return HeightField(-size / 2, -size / 2, STEP, fn(E, N))


def lumpy(E, N):
    """A gentle slope with building-sized lumps and noise, like the DEM."""
    rng = np.random.default_rng(3)
    return (20.0 + 0.02 * E + 1.2 * np.sin(E / 7.0) * np.cos(N / 9.0)
            + rng.normal(0.0, 0.3, E.shape))


def profile(ways, h, step=1.0):
    """Heights every `step` metres along a chain of ways, as the tiles drape them."""
    xy = np.concatenate([w.coords for w in ways])
    hh = np.concatenate([[h[int(n)] for n in w.nodes] for w in ways])
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(xy, axis=0), axis=1))])
    keep = np.concatenate([[True], np.diff(s) > 1e-9])
    ss = np.arange(0.0, s[-1], step)
    return ss, np.interp(ss, s[keep], hh[keep])


def bumps(h, half=2.5, step=1.0):
    n = int(half / step)
    return np.abs(h[n:-n] - 0.5 * (h[:-2 * n] + h[2 * n:]))


def street(way_id, x0, y0, x1, y1, every, tags=None, first=1):
    k = max(int(np.hypot(x1 - x0, y1 - y0) / every), 1)
    t = np.linspace(0.0, 1.0, k + 1)
    coords = np.column_stack([x0 + t * (x1 - x0), y0 + t * (y1 - y0)])
    return Way(way_id, tags or {"highway": "residential"}, np.arange(first, first + k + 1, dtype=np.int64), coords)


def test_road_profile_is_smooth_over_a_lumpy_dem():
    hf = field(lumpy)
    ways = densify_ways([street(1, -250, 0, 250, 0, every=60.0)])
    h = compute_node_heights(ways, hf)["road"]
    s, p = profile(ways, h)
    # No lump a car would feel (a real road's vertical curves stay under a couple of cm)...
    assert bumps(p).max() < 0.02
    # ...and the road still climbs the slope under it.
    assert abs(np.polyfit(s, p, 1)[0] - 0.02) < 0.004
    # The old way (heights at OSM nodes only, chords between) kinks at every node.
    raw = [street(1, -250, 0, 250, 0, every=60.0)]
    s0, p0 = profile(raw, {int(n): float(hf.sample(*c)) for n, c in zip(raw[0].nodes, raw[0].coords)})
    assert bumps(p0).max() > 0.05


def test_smoothing_is_in_metres_not_nodes():
    hf = field(lumpy)
    sparse = densify_ways([street(1, -250, 0, 250, 0, every=40.0)])
    dense = densify_ways([street(1, -250, 0, 250, 0, every=1.0)])
    _, ps = profile(sparse, compute_node_heights(sparse, hf)["road"])
    _, pd = profile(dense, compute_node_heights(dense, hf)["road"])
    assert np.abs(ps - pd)[50:-50].max() < 0.15


def test_divided_road_halves_come_out_level():
    from osm_import.build import _carriageway_pairs
    # A cross slope of 8 %: the two halves, 8 m apart, sample DEM heights 0.64 m apart.
    hf = field(lambda E, N: 20.0 + 0.08 * N)
    tags = {"highway": "primary", "oneway": "yes", "name": "St Georges Terrace"}
    ways = densify_ways([street(1, -200, 4, 200, 4, every=50.0, tags=tags),
                         street(2, 200, -4, -200, -4, every=50.0, tags=tags, first=100)])
    h = compute_node_heights(ways, hf, _carriageway_pairs(ways))["road"]
    a = np.array([h[int(n)] for n in ways[0].nodes])
    b = np.array([h[int(n)] for n in ways[1].nodes])[::-1]
    assert np.abs(a - b)[3:-3].max() < 0.15


def test_street_keeps_headroom_under_a_bridge():
    # The DEM has a mound right where a street passes under a freeway bridge.
    hf = field(lambda E, N: 10.0 + 3.0 * np.exp(-(E ** 2 + N ** 2) / (2 * 20.0 ** 2)))
    fwy = {"highway": "motorway", "lanes": "3", "oneway": "yes"}
    ways = [street(1, -250, 0, -40, 0, every=30.0, tags=fwy),
            street(2, -40, 0, 40, 0, every=80.0, tags=dict(fwy, bridge="yes", layer="1"), first=8),
            street(3, 40, 0, 250, 0, every=30.0, tags=fwy, first=9),
            street(4, 0, -250, 0, 250, every=50.0, tags={"highway": "primary"}, first=100)]
    ways = densify_ways(ways)
    h = compute_node_heights(ways, hf)["road"]
    deck = min(h[int(n)] for n in ways[1].nodes)
    under = [h[int(n)] for n, c in zip(ways[3].nodes, ways[3].coords) if abs(c[1]) < 5]
    assert deck - max(under) >= 5.6 - 1e-6
    # The dip under the bridge eases in and out.
    _, p = profile(ways[3:], h)
    assert np.abs(np.diff(p)).max() <= 0.12 + 1e-6


def _world(hf, src_ways, buildings=()):
    """Just enough of a World to fit the ground (World._fit_ground_to_roads)."""
    w = World.__new__(World)
    w.hf = hf
    w.home = None
    w.keep_dem = np.zeros(hf.H.shape, dtype=bool)
    w.built = w._built_up_mask(buildings)
    from scipy.ndimage import gaussian_filter
    from osm_import.build import BUILT_SOFT
    w.built_soft = gaussian_filter(w.built.astype(float), BUILT_SOFT / hf.step)
    w.bare = w._bare_earth()
    ways = densify_ways(src_ways)
    h = compute_node_heights(ways, w.bare).get("road", {})
    w.ways = [LinearWay(x.id, x.tags, "road", x.coords, np.array([h[int(n)] for n in x.nodes]), x.nodes,
                        styles.road_width(x.tags), False, False, False) for x in ways]
    return w


def test_ground_between_streets_loses_building_mounds():
    # Flat ground at 10 m with a 4 m mound where a block of buildings stood.
    hf = field(lambda E, N: 10.0 + 4.0 * np.exp(-((E - 0) ** 2 + N ** 2) / (2 * 18.0 ** 2)))
    block = [box(-30, -30, 30, 30)]
    w = _world(hf, [street(1, -280, -60, 280, -60, every=40.0),
                    street(2, -280, 60, 280, 60, every=40.0, first=100)], block)
    w._fit_ground_to_roads()
    H = hf.H
    # The mound is gone: the block sits level with the streets around it.
    assert H.max() < 10.6
    # No cliffs anywhere: neighbouring grid nodes differ by less than a 1 in 5 slope.
    assert np.abs(np.diff(H, axis=0)).max() / STEP < 0.2
    assert np.abs(np.diff(H, axis=1)).max() / STEP < 0.2


def test_ground_under_a_road_is_level_across_and_eases_out():
    # A street across a 6 % side slope: its cross-section is flat, and the
    # ground beside it eases back to the slope without a step.
    hf = field(lambda E, N: 20.0 + 0.06 * N)
    w = _world(hf, [street(1, -280, 0, 280, 0, every=40.0, tags={"highway": "secondary"})])
    w._fit_ground_to_roads()
    half = styles.road_width({"highway": "secondary"}) / 2
    xs = np.linspace(-200, 200, 41)
    for off in (-half + 0.3, half - 0.3):
        across = hf.sample(xs, np.full(len(xs), off)) - hf.sample(xs, np.zeros(len(xs)))
        assert np.abs(across).max() < 0.01
    col = hf.H[:, hf.H.shape[1] // 2]
    assert np.abs(np.diff(col)).max() / STEP < 0.2
    # Far from the road the slope is the DEM's own.
    assert abs(hf.sample(0.0, 250.0) - (20.0 + 0.06 * 250.0)) < 0.05


def test_lake_shore_is_graded_not_a_wall():
    # A wetland: the DEM reads the reeds round the water as a bank 5 m above it.
    from shapely.geometry import Point
    from osm_import.build import SHORE_GRADE, WaterBody
    lake = Point(0, 0).buffer(120)
    # On the west side the reeds reach 10 m into the outline too.
    hf = field(lambda E, N: np.where((np.hypot(E, N) < 110) | ((np.hypot(E, N) < 120) & (E > 0)), 4.0, 9.0))
    w = _world(hf, [])
    w.water = [w._water_body(type("A", (), {"geom": lake, "tags": {"natural": "water"}})())]
    w._sculpt_terrain()
    H = hf.H
    level = w.water[0].level
    # The shore comes down to the water (the bank was a 4 m wall)...
    assert hf.sample(125.0, 0.0) - level < 1.2
    # ...on a slope a person can walk down, with no step anywhere on dry land.
    es, ns = hf.node_coords()
    E, N = np.meshgrid(es, ns)
    dry = np.hypot(E, N) >= 120
    assert (np.abs(np.diff(H, axis=0)) / STEP)[dry[1:] & dry[:-1]].max() <= SHORE_GRADE + 0.03
    assert (np.abs(np.diff(H, axis=1)) / STEP)[dry[:, 1:] & dry[:, :-1]].max() <= SHORE_GRADE + 0.03
    # Nothing inside the outline stands above the water.
    assert H[np.hypot(E, N) < 119].max() <= level + 0.4
    # Away from the water the ground is untouched.
    assert abs(hf.sample(250.0, 250.0) - 9.0) < 0.05


def test_traffic_lines_drop_points_the_surface_does_not_need():
    from osm_import.traffic import _simplify
    # A 200 m street densified to 5 m on a 3 % grade with a 20 m crest curve.
    x = np.arange(0.0, 200.1, 5.0)
    y = 10.0 + 0.03 * x - np.maximum(0.0, 1.0 - ((x - 100.0) / 20.0) ** 2) * 0.6
    pts = np.column_stack([x, y, np.zeros_like(x)]).astype(np.float32)
    out = _simplify(pts)
    assert len(out) < len(pts) / 2
    assert (out[0] == pts[0]).all() and (out[-1] == pts[-1]).all()
    # Every dropped point is still within 4 cm of the simplified line.
    assert np.abs(np.interp(x, out[:, 0], out[:, 1]) - y).max() <= 0.04 + 1e-4
