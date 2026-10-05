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
from osm_import.meshbuild import CellGrid, MeshBuilder, Surface, drape, ribbon, triangulate, walls
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
