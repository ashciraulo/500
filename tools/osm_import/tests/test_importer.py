"""Unit tests for the OSM importer that don't need the OSM extract or network."""
import struct
import zlib

import numpy as np
from shapely.geometry import Polygon, box

import math
from types import SimpleNamespace

from osm_import import places, styles
from osm_import.extract import Way
from osm_import.heights import compute_node_heights
from osm_import.meshbuild import CellGrid, MeshBuilder, Surface, drape, polygons_of, ribbon, triangulate, walls
from osm_import.terrain import HeightField
from osm_import.tilewriter import encode_surface
from osm_import.variant import MAGIC, encode, pack_tile, unpack_tile


def flat_field(h=10.0, size=1000.0, step=5.0):
    n = int(size / step) + 1
    return HeightField(-size / 2, -size / 2, step, np.full((n, n), h))


def test_variant_packed_arrays_and_container():
    v = np.array([[1, 2, 3]], dtype=np.float32)
    enc = encode(v)
    assert struct.unpack("<II", enc[:8]) == (36, 1)  # PACKED_VECTOR3_ARRAY, one element
    assert struct.unpack("<3f", enc[8:]) == (1.0, 2.0, 3.0)
    assert encode("ab") == struct.pack("<II", 4, 2) + b"ab\0\0"
    blob = pack_tile({"a": 1})
    assert blob[:4] == MAGIC
    assert unpack_tile(blob) == encode({"a": 1})
    old = b"P5TZ" + blob[4:8] + zlib.compress(encode({"a": 1}))
    assert unpack_tile(old) == encode({"a": 1})


def test_triangulate_is_ccw_and_covers_area():
    poly = Polygon([(0, 0), (10, 0), (10, 10), (0, 10)], [[(4, 4), (6, 4), (6, 6), (4, 6)]])
    v, t = triangulate(poly)
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    cross = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    assert (cross > 0).all()
    assert np.isclose(cross.sum() / 2, poly.area)


def test_walls_face_outwards():
    s = Surface()
    ring = np.array([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)], dtype=float)
    walls(s, ring, 0.0, 3.0, 4.0, 3.2)
    v, n, uv, idx = s.arrays()
    assert len(idx) == 8  # four quads
    centre = np.array([5.0, 5.0])
    for tri in idx:
        p = v[tri].mean(axis=0)
        e1, e2 = v[tri[1]] - v[tri[0]], v[tri[2]] - v[tri[0]]
        face_n = np.cross(e1, e2)
        assert np.dot(face_n[:2], p[:2] - centre) > 0


def test_drape_follows_terrain_and_covers_shape():
    hf = flat_field(12.0)
    grid = CellGrid(hf, (0, 0, 500, 500))
    s = Surface()
    shape = box(10.3, 10.3, 47.9, 33.1)
    drape(s, shape, grid, 0.06, 4.0)
    v, n, uv, idx = s.arrays()
    assert np.allclose(v[:, 2], 12.06)
    a, b, c = v[idx[:, 0]], v[idx[:, 1]], v[idx[:, 2]]
    area = np.abs(np.cross(b - a, c - a)[:, 2]).sum() / 2
    assert np.isclose(area, shape.area, rtol=1e-6)


def test_ribbon_triangles_face_up():
    s = Surface()
    xy = np.array([(0, 0), (10, 0), (20, 5)], dtype=float)
    ribbon(s, xy, np.zeros(3), 4.0, 2.0)
    v, n, uv, idx = s.arrays()
    for tri in idx:
        assert np.cross(v[tri[1]] - v[tri[0]], v[tri[2]] - v[tri[0]])[2] > 0


def test_bridge_lifts_and_ramps_at_max_grade():
    hf = flat_field(5.0)
    xs = np.arange(-300, 301, 20.0)
    coords = np.column_stack([xs, np.zeros_like(xs)])
    ids = np.arange(len(xs), dtype=np.int64) + 1
    mid = len(xs) // 2
    ways = [
        Way(1, {"highway": "primary"}, ids[:mid - 1], coords[:mid - 1]),
        Way(2, {"highway": "primary", "bridge": "yes", "layer": "1"}, ids[mid - 2:mid + 3], coords[mid - 2:mid + 3]),
        Way(3, {"highway": "primary"}, ids[mid + 2:], coords[mid + 2:]),
    ]
    h = compute_node_heights(ways, hf)["road"]
    deck = h[int(ids[mid])]
    assert deck >= 5.0 + 6.0 - 1e-6
    heights = np.array([h[int(i)] for i in ids])
    grades = np.abs(np.diff(heights)) / 20.0
    assert grades.max() <= 0.06 + 1e-6
    assert np.isclose(heights[0], 5.0, atol=0.05)


def test_road_widths_and_lanes():
    assert styles.road_lanes({"highway": "residential"}) == 2
    assert styles.road_width({"highway": "primary", "lanes": "4"}) == 4 * styles.LANE_WIDTH
    assert styles.road_lanes({"highway": "primary", "oneway": "yes"}) == 2
    assert styles.is_tunnel({"tunnel": "yes"}) and not styles.is_tunnel({"tunnel": "building_passage"})
    minh, h = styles.building_height({"building": "yes", "building:levels": "10"}, 500, 1, True)
    assert minh == 0 and np.isclose(h, 10 * styles.LEVEL_H + 1.0)


def test_surface_encoding_round_trip():
    pos = np.array([[0, 0, 0], [1.5, 2.25, -3.0], [400.0, 30.0, -499.0]], dtype=float)
    nrm = np.array([[0, 1, 0]] * 3, dtype=float)
    uv = np.array([[1000.25, 3.5], [1001.0, 4.0], [1002.0, 3.0]])
    tris = np.array([[0, 1, 2]])
    s = encode_surface("asphalt", pos, nrm, uv, tris)
    n = s["count"]
    p = np.frombuffer(s["pos"].tobytes(), dtype="<i2").reshape(3, n).T / 32.0
    assert np.allclose(np.sort(p, axis=0), np.sort(pos, axis=0), atol=1 / 64)
    u = np.frombuffer(s["uv"].tobytes(), dtype="<i2").reshape(2, n).T / s["uvq"]
    assert u.min() >= 0 and u.max() < 3  # shifted towards zero
    assert np.cumsum(s["idx"]).max() == n - 1


def test_home_frame_and_marker_snap():
    # Scene +Z faces due east: local x runs north, local -z runs west.
    home = places.HomeSite(100.0, 50.0, math.pi - math.radians(90), Polygon())
    assert np.allclose(home.to_plan(0, 1), (101, 50))
    assert np.allclose(home.to_plan(1, 0), (100, 51))
    # An east-west road 8 m wide; a marker north of it lands in the north lane,
    # facing east (traffic keeps left), 1.3 m in from the kerb.
    road = SimpleNamespace(group="road", grade_separated=False, tags={"highway": "residential"},
                           xy=np.array([[0.0, 0.0], [100.0, 0.0]]), width=8.0)
    e, n, yaw = places.snap_to_road([road], 40.0, 20.0)
    assert np.isclose(e, 40) and np.isclose(n, 4 - places.KERB_GAP)
    assert np.isclose(yaw, places.godot_yaw(1, 0))



def test_traffic_lanes_and_access():
    from osm_import.traffic import drives, lane_split
    assert lane_split({"highway": "primary", "lanes": "3"}, False) == (2, 1)
    assert lane_split({"highway": "primary", "lanes": "3", "lanes:backward": "2"}, False) == (1, 2)
    assert lane_split({"highway": "primary", "lanes": "2", "oneway": "yes"}, True) == (2, 0)
    assert drives({"highway": "residential"})
    assert not drives({"highway": "residential", "access": "private"})
    assert not drives({"highway": "service"})


def test_carriageways_pushed_apart():
    from osm_import.traffic import TrafficNetwork

    def road(rid, a, b, z):
        xs = np.linspace(0, 100, 11) if a < b else np.linspace(100, 0, 11)
        pts = np.column_stack([xs, np.zeros(11), np.full(11, z)]).astype(np.float32)
        return {"id": rid, "a": a, "b": b, "pts": pts, "oneway": True, "roundabout": False,
                "lanes_fwd": 2, "name": "Barrack Street"}

    net = TrafficNetwork.__new__(TrafficNetwork)
    net.roads = [road("w1/0", 1, 2, 0.0), road("w2/0", 4, 3, 5.0)]  # 5 m apart, 4 lanes
    net.pos = {1: (0, 0, 0), 2: (100, 0, 0), 3: (0, 0, 5), 4: (100, 0, 5)}
    assert net.separate_carriageways() == 2
    mid = [float(r["pts"][len(r["pts"]) // 2, 2]) for r in net.roads]
    assert mid[1] - mid[0] >= 2 * 3.2 + 0.5  # lanes clear each other
    # A different street alongside is left alone.
    net.roads = [road("w1/0", 1, 2, 0.0), {**road("w2/0", 4, 3, 5.0), "name": "Ramp"}]
    assert net.separate_carriageways() == 0


def test_parking_bay_rows_split():
    from types import SimpleNamespace
    from shapely.geometry import box
    from osm_import.parking import Parking

    class HF:
        e0 = n0 = -100.0
        step = 10.0
        H = np.zeros((21, 21))

        def sample(self, e, n):
            return 0.0

    world = SimpleNamespace(hf=HF(), ways=[], parking=[
        SimpleNamespace(tags={"amenity": "parking_space"}, geom=box(0, 0, 25, 5)),   # 10 bays
        SimpleNamespace(tags={"amenity": "parking_space"}, geom=box(40, 0, 42.5, 5)),  # one bay
        SimpleNamespace(tags={"amenity": "parking", "parking": "surface", "capacity": "40"},
                        geom=box(-50, -50, -20, -20)),
    ])
    pk = Parking(world, [])
    assert len(pk.spaces) == 11
    assert pk.spaces[-1]["length"] == 5.0 and pk.spaces[-1]["width"] == 2.5
    assert len(pk.lots) == 1 and pk.lots[0]["capacity"] == 40
    tile = pk.tile_data((-100, -100, 100, 100))
    lot_bays = [p for p in tile if p["kind"] == "lot"]
    assert len(lot_bays) >= 11 + 24  # the 11 bays plus a 30 x 30 m car park: three rows of ten
    assert set(tile[0]) == {"pos", "yaw", "kind"} and tile[0]["pos"].shape == (3,)


def test_roads_level_with_home_at_its_edge():
    from osm_import.build import HOME_RAMP, World, _split_at_edge
    fp = box(-10, -10, 10, 10)
    # A lane 2 m below the home's ground runs through the block.
    w = Way(7, {"highway": "service"}, np.array([1, 2, 3], dtype=np.int64),
            np.array([[-80.0, 0.0], [0.0, 0.0], [80.0, 0.0]]))
    s = _split_at_edge(w, fp)
    assert len(s.nodes) == 5 and np.allclose(s.coords[1], [-10, 0]) and np.allclose(s.coords[3], [10, 0])
    assert len(set(int(n) for n in s.nodes)) == 5
    world = World.__new__(World)
    world.home = SimpleNamespace(footprint=fp, h=22.0)
    node_h = {"road": {int(n): 20.0 for n in s.nodes}}
    world._level_to_home([s], node_h)
    h = node_h["road"]
    assert np.isclose(h[int(s.nodes[1])], 22.0) and np.isclose(h[2], 22.0)
    assert np.isclose(h[1], 20.0)  # past the ramp, its own height
    assert HOME_RAMP < 70


def test_landmarks_build_closed_solid_shapes():
    from shapely.geometry import LineString, Point
    from osm_import import landmarks
    from osm_import.meshbuild import MeshBuilder
    hf = flat_field(10.0)
    foot = {"bell_tower": Point(0, 0).buffer(9), "obelisk": box(-4, -4, 4, 4),
            "stadium": Point(0, 0).buffer(130).intersection(box(-150, -110, 150, 110)),
            "round_house": Point(0, 0).buffer(6), "tea_house": box(-20, -12, 20, 12),
            "council_house": box(-31, -11, 31, 11), "dna_tower": Point(0, 0).buffer(2.7),
            "arena": Point(0, 0).buffer(70), "markets": box(-60, -30, 60, 30).difference(box(0, 0, 60, 30)),
            "hotel_tower": box(-16, -34, 16, 34)}
    for kind, geom in foot.items():
        mb = MeshBuilder()
        lm = landmarks.Landmark(kind, kind, kind, ("area", 1), geom=geom)
        landmarks.build(mb, lm, hf)
        v = np.concatenate([s.arrays()[0] for s in mb.meshes[landmarks.MESH].values()])
        assert v[:, 2].min() >= 9.0 and v[:, 2].max() > 15.0, kind
        assert np.hypot(v[:, 0], v[:, 1]).max() < 200, kind
    for kind in ("eq_bridge", "matagarup"):
        mb = MeshBuilder()
        lm = landmarks.Landmark(kind, kind, kind, ("way", 1), geom=LineString([(0, 0), (300, 0)]),
                                h=np.array([12.0, 12.0]))
        landmarks.build(mb, lm, hf)
        v = np.concatenate([s.arrays()[0] for s in mb.meshes[landmarks.MESH].values()])
        assert v[:, 2].max() > 30.0 and v[:, 2].min() > 11.0, kind
        assert mb.meshes[landmarks.DETAIL], kind  # hangers


def test_poi_slugs():
    from osm_import.pois import NOT_A_VIEW, slug
    assert slug("Fraser Avenue lookout") == "fraser_avenue_lookout"
    assert NOT_A_VIEW.search("Tiger enclosure") and not NOT_A_VIEW.search("Two Rivers Lookout")


def test_bike_lane_tags():
    from osm_import.traffic import _bike_lane
    assert _bike_lane({"cycleway:left": "lane"})
    assert _bike_lane({"cycleway": "shared_lane"})
    assert not _bike_lane({"cycleway": "track"})
    assert not _bike_lane({})


def _street(wid, tags, xs, z=0.0, first_node=None):
    xs = np.asarray(xs, dtype=float)
    coords = np.column_stack([xs, np.full(len(xs), z)])
    start = first_node if first_node is not None else wid * 100
    return Way(wid, {"highway": "primary", **tags}, np.arange(start, start + len(xs), dtype=np.int64), coords)


def test_one_width_per_street():
    from osm_import import streets
    ways = [
        _street(1, {"name": "Roe Street", "lanes": "2"}, [0, 100, 200]),
        _street(2, {"name": "Roe Street", "lanes": "4", "lanes:forward": "3", "lanes:backward": "1"},
                [200, 230], first_node=102),  # turn lanes at the lights
        _street(3, {"name": "Roe Street", "width": "14"}, [230, 380], first_node=201),
        _street(4, {"name": "Roe Street", "lanes": "1", "oneway": "yes"}, [380, 500], first_node=301),
        _street(5, {"name": "Lake Street", "highway": "residential", "lanes": "6"}, [0, 100], z=50.0),
    ]
    out = {w.id: w for w in streets.normalise(ways)}
    widths = [styles.road_width(out[i].tags) for i in (1, 2, 3)]
    assert np.allclose(widths, 2 * styles.LANE_WIDTH)  # the flare and the width tag don't change it
    assert styles.road_lanes(out[2].tags) == 2 and "lanes:forward" not in out[2].tags
    # The one-way block stays as wide as a street, not a single 3.3 m lane.
    assert styles.road_width(out[4].tags) >= styles.ONEWAY_MIN_WIDTH
    assert styles.road_lanes(out[5].tags) == 2  # residential streets get at most two lanes
    # Raw tags: width tags are ignored and one-ways keep a street's width.
    assert np.isclose(styles.road_width({"highway": "residential", "width": "12"}), 2 * styles.LANE_WIDTH)
    assert styles.road_width({"highway": "residential", "oneway": "yes"}) == styles.ONEWAY_MIN_WIDTH


def test_divided_road_halves_are_narrower_than_lone_oneways():
    from osm_import import streets
    ways = [
        _street(1, {"name": "Wellington Street", "highway": "tertiary", "oneway": "yes"}, [0, 100, 200]),
        _street(2, {"name": "Wellington Street", "highway": "tertiary", "oneway": "yes"}, [200, 100, 0], z=9.0),
        _street(3, {"name": "James Street", "highway": "tertiary", "oneway": "yes"}, [0, 100, 200], z=300.0),
    ]
    assert streets.paired_oneways(ways) == {1, 2}
    out = {w.id: w for w in streets.normalise(ways)}
    assert np.isclose(styles.road_width(out[1].tags), streets.styles.PAIRED_MIN_WIDTH)
    assert np.isclose(styles.road_width(out[3].tags), styles.ONEWAY_MIN_WIDTH)


def test_car_park_decks_and_roads_in_buildings_are_dropped():
    from osm_import import streets
    ways = [
        _street(1, {"highway": "service", "service": "parking_aisle", "layer": "1"}, [0, 50]),
        _street(2, {"highway": "service", "service": "parking_aisle", "level": "-1"}, [0, 50], z=10.0),
        _street(3, {"highway": "service", "level": "0;1"}, [0, 50], z=20.0),       # a ramp up from the street
        _street(4, {"highway": "service"}, [100, 160], z=0.0),                   # inside a building
        _street(5, {"highway": "service"}, [100, 160], z=30.0),                  # beside it
        _street(6, {"highway": "primary", "name": "Wellington Street"}, [100, 160], z=1.0),
        Way(7, {"highway": "footway"}, np.array([700, 701]), np.array([[100.0, 0.0], [160.0, 0.0]])),
    ]
    building = box(95, -10, 170, 10)
    kept = {w.id for w in streets.normalise(ways, [building])}
    assert kept == {3, 5, 6, 7}


def test_road_gaps_close_and_junction_corners_round():
    from osm_import import streets
    from shapely.geometry import LineString as L
    pair = L([(0, 0), (100, 0)]).buffer(3, cap_style=2).union(L([(0, 8), (100, 8)]).buffer(3, cap_style=2))
    assert len(polygons_of(pair)) == 2                     # a 2 m strip of ground between them
    assert len(polygons_of(streets.close_gaps(pair, 1.5))) == 1
    tee = L([(-50, 0), (50, 0)]).buffer(3, cap_style=2).union(L([(0, 0), (0, 50)]).buffer(3, cap_style=2))
    closed = streets.close_gaps(tee, 1.5)
    assert closed.area > tee.area                          # fillets in the two corners
    assert closed.buffer(0.5).contains(tee)                # and nothing of the road lost
    wide = L([(0, 0), (100, 0)]).buffer(3, cap_style=2).union(L([(0, 20), (100, 20)]).buffer(3, cap_style=2))
    assert len(polygons_of(streets.close_gaps(wide, 1.5))) == 2  # a real median stays


def test_mapped_sidewalks_beside_streets_are_not_drawn_twice():
    from osm_import import streets
    from types import SimpleNamespace as NS

    def way(wid, group, tags, xy, width=2.0, sidewalk=False):
        return NS(id=wid, group=group, tags=tags, xy=np.asarray(xy, float), width=width,
                  sidewalk=sidewalk, grade_separated=False)

    ways = [
        way(1, "road", {"highway": "residential"}, [(0, 0), (200, 0)], width=6.6, sidewalk=True),
        way(2, "foot", {"highway": "footway", "footway": "sidewalk"}, [(0, 7), (200, 7)]),     # beside it
        way(3, "foot", {"highway": "footway", "footway": "sidewalk"}, [(0, 40), (200, 40)]),   # across a park
        way(4, "foot", {"highway": "footway"}, [(0, 6), (200, 6)]),                            # a plain path
        way(5, "foot", {"highway": "footway", "footway": "crossing"}, [(50, -8), (50, 8)]),
        way(6, "road", {"highway": "service"}, [(0, 80), (200, 80)], width=4.0),
        way(7, "foot", {"highway": "footway", "footway": "sidewalk"}, [(0, 84), (200, 84)]),   # lane has no footpath
    ]
    assert streets.doubled_footways(ways) == {2, 5}


def test_service_roads_listed_for_the_maps():
    from osm_import.traffic import TrafficNetwork
    from types import SimpleNamespace as NS

    def way(tags, xy, group="road"):
        xy = np.asarray(xy, float)
        return NS(group=group, tags=tags, xy=xy, h=np.zeros(len(xy)), grade_separated=False)

    net = TrafficNetwork.__new__(TrafficNetwork)
    net.w = NS(ways=[
        way({"highway": "service", "service": "alley", "name": "Little Shenton Lane"}, [(0, 0), (40, 0)]),
        way({"highway": "service"}, [(0, 10), (40, 10)]),
        way({"highway": "residential"}, [(0, 20), (40, 20)]),
        way({"highway": "footway"}, [(0, 30), (40, 30)], group="foot"),
    ])
    lanes = net._service_roads()
    assert [(f["kind"], f["name"]) for f in lanes] == [("alley", "Little Shenton Lane"), ("service", "")]
    assert np.allclose(lanes[0]["pts"][:, 2], 0) and np.isclose(lanes[0]["pts"][-1, 0], 40)


def test_walkers_on_paths_stand_on_the_ground_drawn_there():
    from osm_import.traffic import TrafficNetwork
    from types import SimpleNamespace as NS

    # Sloping ground, 1 m per 10 m east, with a 3 m bump the path's own
    # profile (smoothed from the bare DEM) doesn't know about.
    n = 201
    e = np.arange(n) * 5.0 - 500
    H = np.tile(e / 10.0, (n, 1))
    H[:, 100:103] += 3.0
    hf = HeightField(-500, -500, 5.0, H)

    def way(tags, h, bridge=False, tunnel=False):
        xy = np.array([(-40.0, 3.0), (60.0, 3.0)])
        return NS(group="foot", tags={"highway": "footway", "bicycle": "designated", **tags}, xy=xy,
                  h=np.asarray(h, float), bridge=bridge, tunnel=tunnel, grade_separated=bridge or tunnel)

    net = TrafficNetwork.__new__(TrafficNetwork)
    net.w = NS(hf=hf, ways=[
        way({"name": "On the ground"}, [8.5, 8.5]),                      # metres over the slope
        way({"name": "Bridge", "bridge": "yes"}, [20.0, 20.0], bridge=True),
        way({"name": "Deep tunnel", "tunnel": "yes"}, [-30.0, -30.0], tunnel=True),
        way({"name": "Shallow tunnel", "tunnel": "yes"}, [-3.0, 3.0], tunnel=True),  # the build leaves it out
    ])
    paths = {f["name"]: f["pts"] for f in net._cycleways()}
    for name in ("On the ground", "Shallow tunnel"):
        p = paths[name]
        assert np.abs(np.diff(p[:, 0])).max() <= 2.5 + 1e-6
        ground = hf.sample(p[:, 0], -p[:, 2])
        assert np.abs(p[:, 1] - (ground + 0.05)).max() < 1e-3, name
        # Between the points, too: walkers go straight from one to the next.
        mid = (p[1:] + p[:-1]) / 2
        assert np.abs(mid[:, 1] - hf.sample(mid[:, 0], -mid[:, 2]) - 0.05).max() < 0.35, name
    assert np.allclose(paths["Bridge"][:, 1], 20.05) and len(paths["Bridge"]) == 2
    assert np.allclose(paths["Deep tunnel"][:, 1], -29.95)


def test_tunnel_roofs_stay_under_the_ground_with_no_holes_beside_them():
    import shapely
    from types import SimpleNamespace as NS
    from osm_import.build import TUNNEL_HEADROOM, TUNNEL_HEIGHT, TUNNEL_ROOF, LinearWay, TileBuilder
    from osm_import.common import TileKey
    from shapely.geometry import Point

    hf = flat_field(10.0, size=1200.0)
    xs = np.linspace(150, 350, 41)
    # A road tunnel under flat ground: 12 m down, then 5 m (less than a full
    # height box), then 3 m near its east portal.
    floor = np.interp(xs, [150, 210, 230, 290, 310, 350], [-2.0, -2.0, 5.0, 5.0, 7.0, 7.0])
    tunnel = LinearWay(1, {"highway": "primary", "tunnel": "yes"}, "road", np.column_stack([xs, np.full(41, 250.0)]),
                       floor, np.arange(1, 42), 8.0, False, True, False)
    above = LinearWay(2, {"highway": "residential"}, "road", np.array([[260.0, 200.0], [260.0, 300.0]]),
                      np.full(2, 10.0), np.array([50, 51]), 6.6, False, False, True)
    ways = [tunnel, above]
    world = NS(hf=hf, tile_size=500, ways=ways, ways_near=lambda b: ways, doubled_paths=set(), home=None,
               water=[], water_union=Polygon(), cover=[])
    tb = TileBuilder(world, TileKey(0, 0))
    tb._road_geoms(); tb._tunnel_cut(); tb._ground(); tb._roads(); tb._sidewalks_paths(); tb._tunnels()

    tris = []
    for mesh, mats in tb.mb.meshes.items():
        if tb.mb.collision.get(mesh):
            for surf in mats.values():
                if surf.arrays() is not None:
                    v, _, _, idx = surf.arrays()
                    tris.append(v[idx])
    tris = np.concatenate(tris)
    solid = shapely.union_all(shapely.polygons(np.concatenate([tris[:, :, :2], tris[:, :1, :2]], axis=1)))
    assert box(140, 225, 360, 275).difference(solid).area < 0.05  # nothing to fall through

    def top(x, y):
        """Height of the highest collision surface over (x, y)."""
        best = -1e9
        for a, b, c in tris:
            if not shapely.Polygon([a[:2], b[:2], c[:2]]).buffer(1e-6).contains(Point(x, y)):
                continue
            n = np.cross(b - a, c - a)
            if abs(n[2]) > 1e-9:
                best = max(best, a[2] - (n[0] * (x - a[0]) + n[1] * (y - a[1])) / n[2])
        return best

    assert np.isclose(top(170, 250), 10.0, atol=0.05)  # deep: the ground over it is whole
    assert np.isclose(top(270, 250), 10.0, atol=0.05)  # 5 m down: so is the ground
    assert np.isclose(top(260, 250), 10.02, atol=0.05)  # and the street over it
    # ... because the ceiling comes down, keeping the headroom.
    v, _, _, _ = tb.mb.meshes["tunnels"]["tunnel_wall"].arrays()
    ceiling = v[np.abs(v[:, 0] - 260) < 2.5, 2].max() - 5.02
    assert TUNNEL_HEADROOM["road"] <= ceiling < 10.0 - 5.02 - TUNNEL_ROOF
    # 3 m down there is no room for it: the box shows, near the portal, as low as it goes,
    # with the ground cut to it.
    assert np.isclose(top(340, 250), 7.02 + TUNNEL_HEADROOM["road"] + TUNNEL_ROOF, atol=0.05)


def test_no_cracks_along_footpaths_on_curved_streets():
    import shapely
    from types import SimpleNamespace as NS
    from osm_import.build import LinearWay, TileBuilder
    from osm_import.common import TileKey

    hf = flat_field(10.0, size=1200.0)
    a = np.linspace(0.2, 1.4, 80)
    xy = np.column_stack([250 + 120 * np.cos(a), 150 + 120 * np.sin(a)])
    street = LinearWay(1, {"highway": "residential"}, "road", xy, np.full(len(xy), 10.0), np.arange(1, 81),
                       6.6, False, False, True)
    world = NS(hf=hf, tile_size=500, ways=[street], ways_near=lambda b: [street], doubled_paths=set(), home=None,
               water=[], water_union=Polygon(), cover=[])
    tb = TileBuilder(world, TileKey(0, 0))
    tb._road_geoms(); tb._tunnel_cut(); tb._ground(); tb._roads(); tb._sidewalks_paths()
    tris = np.concatenate([s.arrays()[0][s.arrays()[3]] for mats in tb.mb.meshes.values()
                           for s in mats.values() if s.arrays() is not None])
    solid = shapely.union_all(shapely.polygons(np.concatenate([tris[:, :, :2], tris[:, :1, :2]], axis=1)))
    assert tb.box.difference(solid).area < 0.5  # drape drops specks under 0.01 m²


def _interchange():
    """A freeway along y = 0 under a street bridge along x = 0, and a slip
    road leaving the bridge's deck over the freeway's edge that comes down
    beside it (their asphalt touching) and merges into it. OSM tags only
    the street's span as a bridge."""
    fx = np.arange(-200, 201, 5.0)
    freeway = Way(1, {"highway": "motorway", "oneway": "yes", "lanes": "3"},
                  np.arange(1000, 1000 + len(fx), dtype=np.int64), np.column_stack([fx, np.zeros_like(fx)]))
    by = np.arange(-150, 151, 5.0)
    bid = np.arange(2000, 2000 + len(by), dtype=np.int64)
    bxy = np.column_stack([np.zeros_like(by), by])
    a, b = np.searchsorted(by, [-25, 25])
    street = {"highway": "trunk", "lanes": "2"}
    ways = [freeway,
            Way(2, street, bid[:a + 1], bxy[:a + 1]),
            Way(3, {**street, "bridge": "yes", "layer": "1"}, bid[a:b + 1], bxy[a:b + 1]),
            Way(4, street, bid[b:], bxy[b:])]
    sx = np.r_[0.0, 6.0, 12.0, np.arange(20, 141, 10.0), 150.0, 160.0]
    sy = np.r_[-5.0, -8.0, -9.5, np.full(13, -9.5), -6.0, 0.0]
    sid = np.r_[bid[np.searchsorted(by, -5)], 3001 + np.arange(len(sx) - 2), 1000 + np.searchsorted(fx, 160)]
    slip = Way(5, {"highway": "motorway_link", "oneway": "yes"}, sid.astype(np.int64), np.column_stack([sx, sy]))
    return ways + [slip], slip


def test_slip_road_off_a_bridge_comes_down_at_a_driveable_grade():
    from osm_import.build import _carriageway_pairs

    ways, slip = _interchange()
    h = compute_node_heights(ways, flat_field(0.0), _carriageway_pairs(ways))["road"]
    deck = h[int(slip.nodes[0])]
    assert deck > 5.0
    prof = np.array([h[int(n)] for n in slip.nodes])
    grade = np.abs(np.diff(prof)) / np.linalg.norm(np.diff(slip.coords, axis=0), axis=1)
    # Not pulled down to the freeway beside it (it had a 4 m drop off the deck).
    assert grade.max() <= 0.07, np.round(prof, 2)
    # The freeway still clears the bridge, and isn't lifted by the slip road.
    assert max(h[1000 + k] for k in range(len(ways[0].nodes))) < 0.5


def test_slip_road_over_the_freeway_is_drawn_on_a_deck_with_no_parapet_across_it():
    import shapely
    from types import SimpleNamespace as NS
    from osm_import.build import LIFT, LinearWay, TileBuilder, World, _carriageway_pairs
    from osm_import.common import TileKey

    ways, slip = _interchange()
    hf = flat_field(0.0, size=1200.0)
    h = compute_node_heights(ways, hf, _carriageway_pairs(ways))["road"]
    lw = [LinearWay(w.id, w.tags, "road", w.coords, np.array([h[int(n)] for n in w.nodes]), w.nodes,
                    styles.road_width(w.tags), styles.is_bridge(w.tags), False, False) for w in ways]
    world = NS(ways=lw)
    World._lift_stacked(world)
    freeway, deck, sl = lw[0], lw[2], lw[-1]
    # The slip road is over the freeway where it leaves the deck, and on the ground further on.
    assert freeway.lift is None and deck.lift is None
    assert sl.lift is not None and sl.lift[:2].all() and not sl.lift[-5:].any()
    pieces = sl.pieces()
    assert [p.bridge for p in pieces] == [True, False]
    assert pieces[0].nodes[0] == slip.nodes[0] and pieces[1].nodes[-1] == slip.nodes[-1]
    assert pieces[0].nodes[-1] == pieces[1].nodes[0]
    assert all(dh > LIFT for dh in sl.h[sl.lift] - 0.0)

    # Its deck and the bridge's meet with no parapet across either.
    world = NS(hf=hf, tile_size=500, ways=lw, ways_near=lambda b: lw, doubled_paths=set(), home=None,
               water=[], water_union=Polygon(), cover=[])
    tb = TileBuilder(world, TileKey(0, -1))
    assert sum(p.bridge for p in tb.ways if p.id == slip.id) == 1
    tb._bridges()
    v, _, _, idx = tb.mb.meshes["bridges"]["concrete"].arrays()
    tris = v[idx]
    top = h[int(slip.nodes[0])]
    # Concrete standing up over the deck (parapets), as plan shapes.
    up = tris[(tris[:, :, 2] > top + 0.3).any(axis=1)]
    walls_plan = shapely.union_all([shapely.LineString(t[:, :2]).buffer(0.05) for t in up])
    lane = shapely.LineString(slip.coords[:3]).buffer(1.2)  # the slip road's middle, off the deck
    assert walls_plan.intersection(lane).area < 0.05
    # The far side keeps its parapet all along, past where the approach joins (no gap there).
    half = styles.road_width(ways[2].tags) / 2
    far = shapely.LineString([(-half + 0.3, -25.0), (-half + 0.3, -0.5)])
    assert walls_plan.intersection(far).length > 24.0


def test_bridge_ways_meeting_at_a_bend_leave_no_crack_outside_it():
    import shapely
    from shapely.geometry import Point
    from types import SimpleNamespace as NS
    from osm_import.build import LinearWay, TileBuilder
    from osm_import.common import TileKey

    hf = flat_field(0.0, size=1200.0)
    tags = {"highway": "primary", "bridge": "yes"}
    p = np.array([250.0, 250.0])
    turn = np.radians(12.0)  # bearing right, so the crack was on the left
    out = np.array([np.sin(turn), np.cos(turn)])
    a = LinearWay(1, tags, "road", np.array([[250.0, 150.0], p]), np.full(2, 8.0), np.array([1, 2]),
                  7.0, True, False, False)
    b = LinearWay(2, tags, "road", np.array([p, p + out * 100.0]), np.full(2, 8.0), np.array([2, 3]),
                  7.0, True, False, False)
    world = NS(hf=hf, tile_size=500, ways=[a, b], ways_near=lambda bb: [a, b], doubled_paths=set(), home=None,
               water=[], water_union=Polygon(), cover=[])
    tb = TileBuilder(world, TileKey(0, 0))
    tb._bridges()
    v, _, _, idx = tb.mb.meshes["bridges"]["asphalt"].arrays()
    deck = shapely.union_all([Polygon(t[:, :2]) for t in v[idx] if Polygon(t[:, :2]).area > 1e-6])
    assert Point(p).buffer(3.4).difference(deck).area < 0.01
    # The side wall and parapet carry on round the outside of the bend.
    v, _, _, idx = tb.mb.meshes["bridges"]["concrete"].arrays()
    up = [t for t in v[idx] if (t[:, 2] > 8.3).any()]
    walls_plan = shapely.union_all([shapely.LineString(t[:, :2]).buffer(0.05) for t in up])
    left = np.array([-np.cos(turn / 2), np.sin(turn / 2)])
    across = shapely.LineString([p + left * 3.0, p + left * 3.8])
    assert walls_plan.intersection(across).length > 0.15  # its outer face and the parapet's inner one


def test_roads_running_off_the_built_map_are_closed_with_barriers():
    from types import SimpleNamespace as NS
    from osm_import.build import EDGE_INSET, LinearWay, TileBuilder, World
    from osm_import.common import TileKey

    hf = flat_field(10.0, size=1200.0)
    # East along y = 250 from tile 0_0 into 1_0, which isn't built; and a
    # street wholly inside the tile.
    xs = np.linspace(300, 700, 9)
    off = LinearWay(1, {"highway": "primary"}, "road", np.column_stack([xs, np.full(9, 250.0)]), np.full(9, 10.0),
                    np.arange(1, 10), 7.0, False, False, True)
    inner = LinearWay(2, {"highway": "residential"}, "road", np.array([[100.0, 100.0], [400.0, 100.0]]),
                      np.full(2, 10.0), np.array([20, 21]), 6.6, False, False, True)
    world = NS(ways=[off, inner], tile_size=500)
    closures = World.edge_closures(world, {"0_0"})
    assert len(closures) == 1
    c = closures[0]
    assert c["way"] == 1 and np.allclose(c["xy"], [500 - EDGE_INSET, 250], atol=1.0) and np.allclose(c["out"], [1, 0])

    world = NS(hf=hf, tile_size=500, ways=[off, inner], ways_near=lambda b: [off, inner], doubled_paths=set(),
               home=None, water=[], water_union=Polygon(), cover=[], closures=closures)
    tb = TileBuilder(world, TileKey(0, 0))
    tb._edge_barriers()
    v, n, _, idx = tb.mb.meshes["props"]["concrete"].arrays()
    # Across the road and its sidewalks, standing on it, facing out.
    assert v[:, 1].min() < 250 - 3.5 - 2.0 and v[:, 1].max() > 250 + 3.5 + 2.0
    assert np.isclose(v[:, 2].max(), 10.0 + 0.75, atol=0.05)
    assert np.abs(v[:, 0] - c["xy"][0]).max() < 0.5
    tri = v[idx]
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    side = np.abs(fn[:, 0]) > np.abs(fn[:, 1]) + np.abs(fn[:, 2])  # the faces towards and away from the edge
    assert side.any() and (np.sign(fn[side, 0]) == np.sign(tri[side, :, 0].mean(axis=1) - c["xy"][0])).all()


def test_traffic_stops_short_of_the_barriers_at_the_map_edge():
    from osm_import.build import LinearWay, World
    from osm_import.traffic import EDGE_STOP, _on_map
    from types import SimpleNamespace as NS

    # Out of tile 0_0 into 1_0 (not built) and back into 2_0.
    xs = np.linspace(300, 1300, 21)
    w = LinearWay(7, {"highway": "primary"}, "road", np.column_stack([xs, np.full(21, 250.0)]),
                  np.linspace(10, 20, 21), np.arange(100, 121), 7.0, False, False, True)
    closures = World.edge_closures(NS(ways=[w], tile_size=500), {"0_0", "2_0"})
    assert [c["sign"] for c in closures] == [1.0, -1.0]
    parts = _on_map(w, closures)
    assert len(parts) == 2
    a, b = parts
    assert a.nodes[0] == 100 and a.nodes[-1] < 0 and b.nodes[0] < 0 and b.nodes[-1] == 120
    assert np.isclose(a.xy[-1, 0], closures[0]["xy"][0] - EDGE_STOP)
    assert np.isclose(b.xy[0, 0], closures[1]["xy"][0] + EDGE_STOP)
    assert np.isclose(a.h[-1], np.interp(a.xy[-1, 0], xs, w.h))
    assert len(set(a.nodes) | set(b.nodes)) == len(a.nodes) + len(b.nodes)
    assert _on_map(w, None) == [w]


def test_one_row_of_barriers_across_both_halves_of_a_divided_road():
    from osm_import.build import _merge_closures

    c = dict(out=np.array([0.0, 1.0]), h=5.0, grade_separated=False, half=5.1)
    rows = _merge_closures([{**c, "xy": np.array([100.0, 492.0])}, {**c, "xy": np.array([106.0, 492.5])},
                            {**c, "xy": np.array([300.0, 492.0])}])
    assert len(rows) == 2
    assert np.allclose(rows[0]["xy"], [103.0, 492.0]) and np.isclose(rows[0]["half"], 8.1)


def test_bridge_piers_stand_clear_of_the_lanes_under_it():
    # A footbridge over the Graham Farmer Fwy had a pier in the westbound
    # lanes: a car following the lane hit it and stuck.
    from types import SimpleNamespace as NS
    from osm_import.build import PIER_CLEAR, LinearWay, TileBuilder
    from shapely.geometry import LineString, Point
    hf = flat_field(0.0, size=400.0)
    # The footbridge crosses the freeway square on, with a pier due at its middle (s = 30 m).
    xs = np.linspace(-30.0, 30.0, 16)
    bridge = LinearWay(1, {"highway": "footway", "bridge": "yes"}, "foot", np.stack([np.zeros(16), xs], axis=1),
                       np.full(16, 7.0), np.arange(16), 3.0, True, False, False)
    freeway = LinearWay(2, {"highway": "motorway"}, "road", np.array([[-200.0, 0.0], [200.0, 0.0]]),
                        np.zeros(2), np.array([100, 101]), 14.0, False, False, False)
    tb = NS(w=NS(hf=hf), ways=[bridge, freeway])
    bot = bridge.h - 1.1
    spots = TileBuilder._pier_spots(tb, bridge, bridge.xy, bot)
    lane = LineString(freeway.xy)
    assert spots, "the footbridge keeps its pier"
    for p, yaw, foot, top in spots:
        # The pier is 1.4 m along the deck: its near face clears the asphalt.
        assert lane.distance(Point(p)) - 0.7 >= freeway.width / 2 + PIER_CLEAR - 1e-6
        assert foot < 0.0 < top
    # With no road under it, the pier stands where it's due.
    tb.ways = [bridge]
    (p, _, _, _), = TileBuilder._pier_spots(tb, bridge, bridge.xy, bot)
    assert abs(p[1]) < 1e-6


def test_roads_meeting_on_a_hill_are_not_stacked_at_the_junction():
    # Fraser Avenue leaves Malcolm Street at a sharp angle where Malcolm Street
    # drops steeply away. A few metres out Malcolm Street is a metre below it,
    # by its own grade, not passing under it: Fraser Avenue was put on a deck
    # with a 0.7 m side standing over Malcolm Street.
    from types import SimpleNamespace as NS
    from osm_import.build import LinearWay, World
    s = np.arange(0.0, 60.0, 4.0)
    a = np.radians(30.0)
    malcolm = LinearWay(1, {"highway": "primary"}, "road", np.stack([s, np.zeros(len(s))], axis=1),
                        66.3 - 0.25 * s, np.arange(len(s)) + 100, 6.6, False, False, False)
    fraser = LinearWay(2, {"highway": "unclassified"}, "road", np.stack([s * np.cos(a), s * np.sin(a)], axis=1),
                       np.full(len(s), 66.3), np.r_[100, np.arange(1, len(s)) + 200], 5.0, False, False, False)
    world = NS(ways=[malcolm, fraser])
    World._lift_stacked(world)
    assert fraser.lift is None and malcolm.lift is None


def test_a_lifted_deck_carries_on_until_the_ground_meets_it():
    from types import SimpleNamespace as NS
    from osm_import.build import LIFT_REACH, LinearWay, World

    xs = np.arange(0, 101, 5.0)
    h = np.interp(xs, [0, 30, 45, 100], [6.0, 4.0, 0.1, 0.0])
    w = LinearWay(1, {"highway": "motorway_link"}, "road", np.column_stack([xs, np.zeros_like(xs)]), h,
                  np.arange(1, 22), 4.5, False, False, False, lift=xs <= 20)
    World._land_lifts(NS(ways=[w], hf=flat_field(0.0)))
    # On over the ground until it is within 15 cm of the road (at 45 m, where
    # the deck now lands), and no further.
    assert np.array_equal(w.lift, xs <= 40)
    # Never more than LIFT_REACH past where it was lifted.
    w = LinearWay(1, {"highway": "motorway_link"}, "road", np.column_stack([xs, np.zeros_like(xs)]),
                  np.full(len(xs), 3.0), np.arange(1, 22), 4.5, False, False, False, lift=xs <= 20)
    World._land_lifts(NS(ways=[w], hf=flat_field(0.0)))
    assert np.array_equal(w.lift, xs < 20 + LIFT_REACH)


def _lw(i, tags, group, xy, h, width, nodes=None):
    from osm_import.build import LinearWay
    xy = np.asarray(xy, dtype=float)
    nodes = np.arange(len(xy)) + 1000 * i if nodes is None else nodes
    return LinearWay(i, tags, group, xy, np.broadcast_to(np.asarray(h, float), (len(xy),)).copy(),
                     nodes, width, False, False, False)


def test_road_running_along_the_top_of_a_rail_cutting_stands_on_a_wall():
    # A service road 6 m over the railway beside it (Milligan Street): no
    # 5 m ground can slope that far between them, and its edge dropped 0.8 m
    # in 3 m. It's walled instead; a street 1.2 m over another one 6 m past
    # its kerb isn't (those streets have a slope between them).
    from types import SimpleNamespace as NS
    from osm_import.build import World
    xs = np.arange(-100.0, 101.0, 5.0)
    line = lambda y: np.column_stack([xs, np.full(len(xs), y)])
    rail = _lw(1, {"railway": "rail"}, "rail", line(0.0), 9.8, 3.2)
    lane = _lw(2, {"highway": "service"}, "road", line(6.6), 15.8, 5.0)
    high = _lw(3, {"highway": "residential"}, "road", line(100.0), 11.2, 6.6)
    low = _lw(4, {"highway": "residential"}, "road", line(100.0 + 6.6 + 6.0), 10.0, 6.6)
    World._lift_stacked(NS(ways=[rail, lane, high, low]))
    assert lane.lift is not None and lane.lift.all()
    assert rail.lift is None and high.lift is None and low.lift is None


def test_freeway_beside_the_railway_in_its_median_stands_on_a_wall():
    from types import SimpleNamespace as NS
    from osm_import.build import STACK_WIDE, World
    xs = np.arange(-100.0, 101.0, 5.0)
    line = lambda y: np.column_stack([xs, np.full(len(xs), y)])
    rail = _lw(1, {"railway": "rail"}, "rail", line(0.0), 10.0, 3.2)
    # Its lanes 2 m over the tracks, 8 m past the ballast; the far carriageway
    # 2 m under them and too far off to matter.
    near = _lw(2, {"highway": "motorway"}, "road", line(1.6 + 8.0 + 5.35), 12.0, 10.7)
    far = _lw(3, {"highway": "motorway"}, "road", line(-(1.6 + STACK_WIDE + 5.35 + 1.0)), 8.0, 10.7)
    World._lift_stacked(NS(ways=[rail, near, far]))
    assert near.lift is not None and near.lift.all()
    # The railway is higher than the far carriageway but not beside it.
    assert rail.lift is None and far.lift is None


def test_short_gaps_between_lifted_stretches_are_lifted_too():
    from osm_import.build import LIFT_GAP, _close_gaps
    xs = np.arange(0.0, 201.0, 5.0)
    w = _lw(1, {"highway": "motorway"}, "road", np.column_stack([xs, np.zeros_like(xs)]), 0.0, 10.0)
    lift = (xs < 50) | ((xs > 65) & (xs < 100)) | (xs > 100 + LIFT_GAP + 10)
    out = _close_gaps(w, lift)
    # 50 m to 65 m (25 m between the lifted nodes either side) closes; the
    # gap after 100 m is longer and stays; nothing is lifted past the ends.
    assert out[(xs >= 50) & (xs <= 65)].all()
    assert not out[(xs >= 100) & (xs <= 100 + LIFT_GAP + 5)].any()
    assert np.array_equal(out[xs > 140], lift[xs > 140])


def test_ground_never_comes_up_through_a_lifted_deck():
    # A freeway lifted over the railway beside it, in a cutting: the ground on
    # its other side was fitted to the bank, higher than the deck.
    from types import SimpleNamespace as NS
    from osm_import.build import LIFT_UNDER, World
    from osm_import.meshbuild import densify, offset_polyline
    xs = np.arange(-100.0, 101.0, 5.0)
    w = _lw(1, {"highway": "motorway"}, "road", np.column_stack([xs, np.zeros_like(xs)]), 12.0, 10.7)
    w.lift = np.ones(len(xs), bool)
    hf = flat_field(0.0, size=400.0)
    es, ns = hf.node_coords()
    N = np.broadcast_to(ns[:, None], hf.H.shape)
    hf.H[:] = np.where(N > -5.0, 12.0 + 0.5 * np.maximum(N + 5.0, 0.0), 10.0)
    core = np.zeros(hf.H.shape, bool)
    core[np.abs(N - 30.0) < 4.0] = True  # a street up the bank keeps its ground
    keep = hf.H[core].copy()
    World._cut_under_lifts(NS(ways=[w], hf=hf, road_core=core))
    xy, h = densify(w.xy, w.h, 2.0)
    inner = slice(5, -5)
    for o in np.linspace(-w.width / 2, w.width / 2, 7):
        q = offset_polyline(xy, o)[inner]
        assert (hf.sample(q[:, 0], q[:, 1]) <= h[inner] - LIFT_UNDER + 1e-6).all()
    assert np.array_equal(hf.H[core], keep)
    # A slip road beside it at its own height comes down no more than LIFT_UNDER
    # (it had a 0.3 m step all along the deck's side).
    hf.H[:] = np.where(np.abs(N - 9.0) < 3.0, 12.0, 10.0)
    beside = np.abs(N - 9.0) < 3.0
    World._cut_under_lifts(NS(ways=[w], hf=hf, road_core=beside))
    assert hf.H[beside].min() >= 12.0 - LIFT_UNDER - 1e-6 and LIFT_UNDER <= 0.1
    # Lower ground (the railway's side) is left alone.
    assert (hf.H[N < -10.0] == 10.0).all()


def test_no_room_to_stand_under_a_walled_deck():
    # A ramp 2.5 m over flat ground is walled down to it on both sides; with
    # 1.4 m under its slab you could stand in there (dropped in where the
    # wall stops) and never get out. A deck 6 m up is open underneath.
    from types import SimpleNamespace as NS
    from osm_import.build import DECK_THICKNESS, LIFT_WALL_CLEAR, World
    xs = np.arange(-100.0, 101.0, 5.0)
    for top, walled in ((12.5, True), (16.0, False)):
        w = _lw(1, {"highway": "motorway_link"}, "road", np.column_stack([xs, np.zeros_like(xs)]), top, 10.7)
        w.lift = np.ones(len(xs), bool)
        hf = flat_field(10.0, size=400.0)
        es, ns = hf.node_coords()
        E, N = np.meshgrid(es, ns)
        World._cut_under_lifts(NS(ways=[w], hf=hf, road_core=np.zeros(hf.H.shape, bool)))
        under = (np.abs(N) < w.width / 2) & (np.abs(E) < 80.0)
        assert (top - 10.0 < LIFT_WALL_CLEAR) == walled
        if walled:
            assert (hf.H[under] >= top - DECK_THICKNESS - 1e-6).all()
        else:
            assert (hf.H[under] == 10.0).all()
        assert (hf.H[np.abs(N) > w.width / 2 + 5.0] == 10.0).all()


def test_no_slot_between_two_walled_decks_side_by_side():
    # A ramp walled beside the freeway, 3 m of grass between their walls:
    # the grass comes up level with them instead of being a slot to fall in.
    from types import SimpleNamespace as NS
    from osm_import.build import LIFT_UNDER, World
    xs = np.arange(-100.0, 101.0, 5.0)
    a = _lw(1, {"highway": "motorway"}, "road", np.column_stack([xs, np.full(len(xs), -7.0)]), 12.0, 11.0)
    b = _lw(2, {"highway": "motorway_link"}, "road", np.column_stack([xs, np.full(len(xs), 5.5)]), 12.5, 8.0)
    for w in (a, b):
        w.lift = np.ones(len(xs), bool)
    hf = flat_field(10.0, size=400.0)
    E, N = np.meshgrid(*hf.node_coords())
    World._cut_under_lifts(NS(ways=[a, b], hf=hf, road_core=np.zeros(hf.H.shape, bool)))
    q = np.column_stack([np.arange(-60.0, 61.0, 1.0), np.full(121, 0.0)])
    assert (hf.sample(q[:, 0], q[:, 1]) >= 12.0 - LIFT_UNDER - 1e-6).all()
    assert (hf.H[np.abs(N) > 25.0] == 10.0).all()


def test_wide_gap_between_two_walled_decks_comes_up_to_the_lower():
    # Mounts Bay Road: a slip road walled 2 m over the grass and the road
    # beside it half a metre up, 6.4 m of grass between their walls (wider
    # than a ground node): the grass comes up level with the lower deck.
    from types import SimpleNamespace as NS
    from osm_import.build import LIFT_UNDER, World
    xs = np.arange(-100.0, 101.0, 5.0)
    a = _lw(1, {"highway": "trunk_link"}, "road", np.column_stack([xs, np.full(len(xs), -6.5)]), 9.2, 6.6)
    b = _lw(2, {"highway": "primary"}, "road", np.column_stack([xs, np.full(len(xs), 6.5)]), 7.3, 6.6)
    for w in (a, b):
        w.lift = np.ones(len(xs), bool)
    hf = flat_field(6.7, size=400.0)
    World._cut_under_lifts(NS(ways=[a, b], hf=hf, road_core=np.zeros(hf.H.shape, bool)))
    q = np.column_stack([np.arange(-60.0, 61.0, 1.0), np.full(121, 0.0)])
    assert (np.abs(hf.sample(q[:, 0], q[:, 1]) - (7.3 - LIFT_UNDER)) < 1e-6).all()


def test_slot_beside_a_walled_deck_comes_up_under_a_low_open_one():
    # The Esplanade: a slip road 4 m over the ground, open underneath, beside
    # a ramp walled 2 m over it. The slot between them ran in under the open
    # deck; it comes up level with the walled one, leaving no room to stand
    # under the other.
    from types import SimpleNamespace as NS
    from osm_import.build import DECK_THICKNESS, LIFT_UNDER, World
    xs = np.arange(-100.0, 101.0, 5.0)
    a = _lw(1, {"highway": "motorway_link"}, "road", np.column_stack([xs, np.full(len(xs), -3.5)]), 16.0, 4.5)
    b = _lw(2, {"highway": "service"}, "road", np.column_stack([xs, np.full(len(xs), 3.5)]), 14.0, 5.0)
    for w in (a, b):
        w.lift = np.ones(len(xs), bool)
    hf = flat_field(12.0, size=400.0)
    World._cut_under_lifts(NS(ways=[a, b], hf=hf, road_core=np.zeros(hf.H.shape, bool)))
    q = np.column_stack([np.arange(-60.0, 61.0, 1.0), np.full(121, -1.0)])
    g = hf.sample(q[:, 0], q[:, 1])
    assert (g >= 14.0 - LIFT_UNDER - 1e-6).all()
    assert (g <= 16.0 - DECK_THICKNESS - 0.3 + 1e-6).all()
    assert (16.0 - DECK_THICKNESS - g < 1.2).all()


def test_crevice_between_a_walled_deck_and_a_building_comes_up_level_with_the_deck():
    # The Esplanade: a slip road walled 2.5 m over the ground runs 1.5 m
    # from an office tower's wall. You dropped off the deck into the crevice
    # between them and couldn't climb out; the ground there comes up level
    # with the deck. A building further off keeps its ground.
    from types import SimpleNamespace as NS
    from shapely.geometry import box as sbox
    from osm_import.build import LIFT_UNDER, World
    xs = np.arange(-100.0, 101.0, 5.0)
    a = _lw(1, {"highway": "service"}, "road", np.column_stack([xs, np.zeros(len(xs))]), 13.0, 5.0)
    a.lift = np.ones(len(xs), bool)
    hf = flat_field(10.5, size=400.0)
    near = NS(geom=sbox(-30.0, 4.0, 30.0, 40.0))  # 1.5 m off the deck's edge
    far = NS(geom=sbox(-30.0, -60.0, 30.0, -12.5))  # 10 m off the other edge
    World._cut_under_lifts(NS(ways=[a], hf=hf, road_core=np.zeros(hf.H.shape, bool), buildings=[near, far]))
    q = np.column_stack([np.arange(-20.0, 21.0, 1.0), np.full(41, 3.5)])
    assert (np.abs(hf.sample(q[:, 0], q[:, 1]) - (13.0 - LIFT_UNDER)) < 1e-6).all()
    assert (np.abs(hf.sample(q[:, 0], np.full(41, -12.5)) - 10.5) < 1e-6).all()


def test_rail_cutting_bank_has_barriers_along_its_top_but_not_across_a_road():
    # Roe Street: the bank down into the rail yard starts behind the
    # footpath. A row of barriers runs along its top, none where a road
    # goes in, and none along a side where the ground stays level.
    import shapely
    from shapely.geometry.polygon import orient
    from osm_import.build import _cutting_fence
    hf = flat_field(18.0, size=400.0)
    E, N = np.meshgrid(*hf.node_coords())
    hf.H[:] = np.where(N > -5.0, 18.0, np.maximum(18.0 - (-5.0 - N) * 0.8, 10.0))
    yard = orient(box(-60.0, -80.0, 60.0, 0.0), 1.0)
    road = box(-4.0, -40.0, 4.0, 10.0)
    blocks = _cutting_fence(np.asarray(yard.exterior.coords), hf, road)
    xy = np.array([b[0] for b in blocks])
    top = xy[np.abs(xy[:, 1] + 5.0) < 3.0]
    assert len(top) > 40
    assert (top[:, 1] > -5.6).all() and (top[:, 1] < -2.5).all()
    assert not shapely.contains_xy(road, xy[:, 0], xy[:, 1]).any()
    assert (xy[:, 1] > -10.0).all()  # not along the level floor's far sides
    # Standing on the street's level, not on the slope below it.
    assert all(b[2] >= 18.0 - 1e-6 for b in blocks if abs(b[0][1] + 5.0) < 3.0)
    assert all(b[3] <= b[2] - 0.15 for b in blocks)


def test_a_lone_narrow_landmark_doesnt_make_the_ground_round_it_built_up():
    # The State War Memorial stands alone on the Kings Park escarpment. As
    # built-up ground it was interpolated from the roads, which pulled the
    # hilltop 23 m down towards Mounts Bay Rd below. The Bell Tower has
    # buildings beside it and stays built-up, and so does a landmark too
    # wide for the bare earth to take its mound out.
    from types import SimpleNamespace as NS
    from shapely.geometry import box as sbox
    from osm_import import landmarks
    from osm_import.build import _lone_landmarks
    ids = {lm.id: lm.osm[1] for lm in landmarks.CATALOGUE}
    memorial = NS(id=ids["state_war_memorial"], geom=sbox(0.0, 0.0, 19.0, 19.0))
    inside = NS(id=1, geom=sbox(8.0, 8.0, 11.0, 11.0))   # under the memorial's own model
    far = NS(id=2, geom=sbox(100.0, 0.0, 130.0, 30.0))
    bell = NS(id=ids["bell_tower"], geom=sbox(500.0, 0.0, 525.0, 25.0))
    beside = NS(id=3, geom=sbox(530.0, 0.0, 560.0, 25.0))
    stadium = NS(id=ids["optus_stadium"], geom=sbox(1000.0, 0.0, 1270.0, 230.0))
    lone = _lone_landmarks([memorial, inside, far, bell, beside, stadium])
    assert lone == {memorial.id}


def test_boardwalk_sits_just_over_the_ground_or_water_it_crosses():
    # Herdsman Lake: the boardwalk's clearance was measured from the DEM, and
    # the shore under it is sculpted lower, which left it metres up in the
    # air on piers. It sits just over the final ground, and over the water
    # just over the water.
    from dataclasses import replace
    from types import SimpleNamespace as NS
    from shapely.geometry import box as sbox
    from osm_import.build import BOARDWALK_DECK, World
    hf = flat_field(10.0, size=400.0)
    E, N = np.meshgrid(*hf.node_coords())
    hf.H[:] = np.where(np.abs(E) < 80.0, 6.0, 10.0)  # a hollow (the sculpted shore)
    xs = np.arange(-100.0, 101.0, 5.0)
    bw = replace(_lw(1, {"highway": "footway", "bridge": "boardwalk"}, "foot",
                     np.column_stack([xs, np.zeros(len(xs))]), 15.0, 2.0), bridge=True)
    pond = NS(geom=sbox(-20.0, -20.0, 20.0, 20.0), level=7.0)
    World._seat_boardwalks(NS(ways=[bw], hf=hf, water=[pond]))
    ground = hf.sample(xs, np.zeros(len(xs)))
    dry = np.abs(xs) > 20.0
    assert np.allclose(bw.h[dry], ground[dry] + BOARDWALK_DECK)
    assert np.allclose(bw.h[np.abs(xs) < 20.0], 7.0 + BOARDWALK_DECK)
