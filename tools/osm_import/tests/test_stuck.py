"""Places on foot you could drop into and not climb back out of."""
import numpy as np
import shapely
from shapely.geometry import LineString, Polygon, box

from osm_import.build import LID_DROP, RIVER_LEVEL, SEAT_GRADE, LinearWay, WaterBody, World, _lid
from osm_import.meshbuild import Surface
from osm_import.terrain import HeightField

STEP = 5.0


def field(fn, size=600.0, x0=None):
    n = int(size / STEP) + 1
    x = (-size / 2 if x0 is None else x0) + np.arange(n) * STEP
    E, N = np.meshgrid(x, x)
    return HeightField(x[0], x[0], STEP, np.asarray(fn(E, N), dtype=float))


def _world(hf, decks=(), water=(), ways=()):
    w = World.__new__(World)
    w.hf = hf
    w.decks = list(decks)
    w.water = list(water)
    w.water_union = shapely.union_all([wb.geom for wb in w.water]) if w.water else Polygon()
    w.road_core = np.zeros(hf.H.shape, dtype=bool)
    w.ways = list(ways)
    return w


def test_jetty_fingers_are_level_with_the_walkway_and_the_shore():
    # The river west of x = 0. The quay is 3 m up, and the DEM keeps an 8 m
    # mound just inland where the walkway starts (Elizabeth Quay's took the
    # walkway to 8 m and left its fingers at 1.2 m, metres below it).
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < -6, -2.5, np.where(E < 0, -0.3, np.where((E > 12) & (E < 30), 8.0, 3.0))))
    walkway = LineString([(25, 0), (-60, 0)]).buffer(1.5, cap_style=2)
    fingers = [LineString([(x, 1.5), (x, 20)]).buffer(1.5, cap_style=2) for x in (-20, -35, -50)]
    decks = [(walkway, "pier", 1)] + [(g, "pier", 10 + k) for k, g in enumerate(fingers)]
    w = _world(hf, decks, [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    parts = w.deck_parts = w._level_decks()
    tops = [d.top for d in parts]
    assert max(tops) - min(tops) < 1e-9          # one level for the whole jetty...
    assert abs(tops[0] - 3.0) < 0.1               # ...the quay's, not the mound's
    assert w.deck_top(12) == tops[0]
    # The quay where it leaves the land is level with it.
    assert abs(hf.sample(2.0, 0.0) - (tops[0] - 0.05)) < 0.05
    # The water round it keeps its shallows.
    assert abs(hf.sample(-5.0, 5.0) - (-0.3)) < 1e-9


def test_lone_jetty_out_in_the_water_stands_above_the_waves():
    river = box(-300, -300, 300, 300)
    hf = field(lambda E, N: np.full(E.shape, -2.5))
    w = _world(hf, [(LineString([(0, 0), (0, 30)]).buffer(1.5), "pier", 1)],
               [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    d, = w._level_decks()
    assert abs(d.top - (RIVER_LEVEL + 1.2)) < 1e-9 and d.bottom < -2.5 and d.landing is None


def test_footbridge_lands_on_the_ground_it_was_left_under():
    # Fitting the ground to the streets raised it 3 m at the bridge's west end.
    hf = field(lambda E, N: np.full(E.shape, 10.0))
    xs = np.linspace(-50, 50, 21)
    h = np.interp(xs, [-50, 0, 50], [7.0, 12.0, 12.0])
    bridge = LinearWay(1, {"highway": "footway", "bridge": "yes"}, "foot", np.column_stack([xs, np.zeros(21)]),
                       h, np.arange(1, 22), 2.0, True, False, False)
    w = _world(hf, ways=[bridge])
    w._land_footbridges()
    assert abs(bridge.h[0] - 10.0) < 1e-9       # lifted to the ground...
    assert abs(bridge.h[-1] - 12.0) < 1e-9      # ...the end already above it stays
    assert (bridge.h >= h - 1e-9).all()          # and nothing comes down


def test_tunnel_lid_follows_the_ground_over_it():
    # A street across a slope over a shallow tunnel: the low side's ground is
    # cut away to the roof, the high side's was left 2 m over it, a trench.
    hf = field(lambda E, N: 10.0 + 0.2 * N)
    xy = np.column_stack([np.linspace(-50, 50, 26), np.zeros(26)])
    roof = np.full(26, 9.0)
    surf = Surface()
    left, right = _lid(surf, xy, roof, 6.0, hf)
    v, _, _, idx = surf.arrays()
    g = hf.sample(v[:, 0], v[:, 1])
    assert np.allclose(v[:, 2], np.maximum(9.0, g - LID_DROP))
    assert left.max() > 10.0 and np.allclose(right, 9.0)  # under the ground uphill, the roof downhill
    # Faces point up.
    tri = v[idx]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    assert (n[:, 2] > 0).all()


def test_mole_keeps_its_beach_and_its_own_height():
    # A rock mole out into the sea with a pier at its end: the pier's top
    # stays off the mole, and the shallows along the mole stay shallow (they
    # are the way back to the shore for anyone who climbs down onto them).
    sea = box(-300, -300, 300, 0)
    hf = field(lambda E, N: np.where(N < -20, -3.0, np.where(N < 0, 0.1, 3.0)))
    mole = LineString([(0, 0), (0, -150)]).buffer(4.0, cap_style=2)
    pier = LineString([(4, -140), (40, -140)]).buffer(1.5, cap_style=2)
    w = _world(hf, [(mole, "groyne", 1), (pier, "pier", 2)], [WaterBody(sea, RIVER_LEVEL, True, "Indian Ocean")])
    w.deck_parts = w._level_decks()
    assert w.deck_top(1) != w.deck_top(2)
    assert hf.sample(-10.0, -10.0) > RIVER_LEVEL - 0.5


def test_road_bridge_parapets_fade_out_where_the_deck_meets_the_street():
    from osm_import.build import PARAPET_H, _parapet_heights, _runs
    from osm_import.meshbuild import offset_polyline
    # An overpass ramp starting at street level and climbing 4 m.
    hf = field(lambda E, N: np.full(E.shape, 10.0))
    xy = np.column_stack([np.linspace(0, 80, 21), np.zeros(21)])
    top = 10.0 + np.linspace(0.0, 4.0, 21)
    w = LinearWay(1, {"highway": "primary", "bridge": "yes"}, "road", xy, top, np.arange(21), 8.0, True, False, False)
    for side in (4.0, -4.0):
        ph = _parapet_heights(w, offset_polyline(xy, side), top, hf)
        assert ph[0] == 0.0 and ph[-1] == PARAPET_H and (np.diff(ph) >= 0).all()
        (a, b), = _runs(ph > 0.0)
        assert ph[a - 1] == 0.0 and b == 21
    foot = LinearWay(2, {"highway": "footway", "bridge": "yes"}, "foot", xy, top, np.arange(21), 3.0, True, False, False)
    assert (_parapet_heights(foot, xy, top, hf) == PARAPET_H).all()


def test_a_parapet_stands_over_the_drop_even_with_a_bank_on_the_other_side():
    # A ramp 3 m up with the ground banked up to it on its left: its right
    # side still drops 3 m, so it keeps its parapet there (it had none, and
    # you walked off it into a walled-in slot).
    from osm_import.build import PARAPET_H, _parapet_heights
    from osm_import.meshbuild import offset_polyline
    hf = field(lambda E, N: np.where(N > 0.0, 13.0, 10.0))
    xy = np.column_stack([np.linspace(0, 80, 21), np.zeros(21)])
    top = np.full(21, 13.0)
    w = LinearWay(1, {"highway": "motorway_link"}, "road", xy, top, np.arange(21), 8.0, True, False, False)
    assert (_parapet_heights(w, offset_polyline(xy, 6.0), top, hf) == 0.0).all()
    assert (_parapet_heights(w, offset_polyline(xy, -6.0), top, hf) == PARAPET_H).all()


def test_jetty_comes_up_to_the_street_that_leads_onto_it():
    # The street (and its footpath) reaches the jetty 0.8 m above the bank beside it.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 3.0))
    jetty = LineString([(2, 0), (-60, 0)]).buffer(1.5, cap_style=2)
    street = LinearWay(1, {"highway": "residential"}, "road", np.array([[40.0, 0.0], [2.5, 0.0]]),
                       np.array([3.8, 3.8]), np.array([1, 2]), 6.0, False, False, True)
    w = _world(hf, [(jetty, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")], ways=[street])
    top = w._level_decks()[0].top
    assert abs(top - 3.75) < 1e-9


def test_footpath_profile_off_the_ground_does_not_lift_the_jetty():
    # Footpaths are drawn on the ground; their profiles come off the bare DEM
    # and can be metres over it. One 9 m up took a jetty (and the ground round
    # its end, a 6 m tower on the lawn) with it.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 3.0))
    jetty = LineString([(2, 0), (-60, 0)]).buffer(1.5, cap_style=2)
    path = LinearWay(1, {"highway": "footway"}, "foot", np.array([[40.0, 0.0], [2.5, 0.0]]),
                     np.array([9.0, 9.0]), np.array([1, 2]), 2.0, False, False, False)
    w = _world(hf, [(jetty, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")], ways=[path])
    assert abs(w._level_decks()[0].top - 3.0) < 0.1
    assert hf.H.max() < 3.1


def test_bank_left_standing_inside_the_water_comes_down_to_the_jetty():
    # The water's outline takes in 10 m of bank the DEM still has 2 m over the
    # quay: you would drop off it onto the jetty and not get back up.
    river = box(-300, -300, 10, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, np.where(E < 10, 5.0, 3.0)))
    jetty = LineString([(12, 0), (-60, 0)]).buffer(1.5, cap_style=2)
    w = _world(hf, [(jetty, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    d, = w._level_decks()
    top = d.top
    assert abs(top - 3.0) < 0.1
    # The bank comes down to the deck beside it, which ramps down off the quay:
    # at its side, no more than a step up off the deck...
    assert abs(hf.sample(5.0, 0.0) - (d.heights(5.0, 0.0) - 0.05)) < 0.05
    assert hf.sample(5.0, 1.5) - d.heights(5.0, 1.5) < 0.3
    # ...easing back up to the bank, gently.
    ys = np.arange(0.0, 40.0, STEP)
    assert (np.diff(hf.sample(np.full(len(ys), 5.0), ys)) <= SEAT_GRADE * STEP * 1.5).all()


def test_jetty_off_a_high_bank_ramps_down_to_just_over_the_water():
    # Mends St: the bank is 4.8 m over the river. The jetty leaves it at that
    # height and comes down at JETTY_GRADE to JETTY_ABOVE over the water.
    from osm_import.build import JETTY_ABOVE, JETTY_GRADE
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 4.8))
    jetty = LineString([(6, 0), (-80, 0)]).buffer(2.0, cap_style=2)
    w = _world(hf, [(jetty, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    w.deck_parts = [d] = w._level_decks()
    assert abs(d.top - 4.8) < 0.1 and abs(d.low - (RIVER_LEVEL + JETTY_ABOVE)) < 1e-9
    x = np.arange(-78.0, 5.0, 0.5)
    h = d.heights(x, np.zeros(len(x)))
    assert abs(h[-1] - d.top) < 1e-9 and abs(h[0] - d.low) < 1e-9      # on at the bank, out over the water
    assert (np.diff(h) <= JETTY_GRADE * 0.5 + 1e-9).all()             # a steady ramp, no step
    assert abs(w.deck_height(1, -70.0, 0.0) - d.low) < 1e-9
    # Built: the cap and the sides follow the ramp.
    from osm_import.build import TileBuilder
    tb = TileBuilder.__new__(TileBuilder)
    from types import SimpleNamespace as NS
    from osm_import.meshbuild import MeshBuilder
    tb.w, tb.box, tb.mb = w, box(-300, -300, 300, 300), MeshBuilder()
    tb._decks()
    v, _, _, _ = tb.mb.surface("props", "path", "world").arrays()
    assert np.abs(v[:, 2] - d.heights(v[:, 0], v[:, 1])).max() < 1e-6
    assert v[:, 2].min() >= d.low - 1e-9 and v[:, 2].max() <= d.top + 1e-9


def test_low_road_bridge_side_slopes_down_to_the_ground_beside_it():
    # William St: the deck leaves the street with its side 0.4-0.9 m over the
    # ground beside the road, a ledge a car running wide snags on.
    from osm_import.build import BEVEL_MAX, BEVEL_RUN, _bevel
    from osm_import.meshbuild import offset_polyline
    hf = field(lambda E, N: np.full(E.shape, 10.0))
    xy = np.column_stack([np.linspace(0, 80, 21), np.zeros(21)])
    top = 10.3 + np.linspace(0.0, 3.0, 21)
    surf = Surface()
    _bevel(surf, xy, offset_polyline(xy, 4.0), top, hf)
    v, nrm, _, idx = surf.arrays()
    assert len(idx) and (nrm[:, 2] >= 0).all()
    t = v[idx]
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    big = np.linalg.norm(n, axis=1) > 1e-6
    assert (n[big, 2] > 0).all()                                   # faces up...
    slope = np.hypot(n[big, 0], n[big, 1]) / n[big, 2]
    assert slope.max() < 1.0 / BEVEL_RUN + 0.05                       # ...a ramp a car rides up
    assert v[:, 1].max() <= 4.0 + BEVEL_RUN * BEVEL_MAX + 1e-6
    # Only where the ledge is low: none once the deck is well up.
    assert v[:, 0].max() < 80 * (BEVEL_MAX - 0.3) / 3.0 + 4.0 + 1e-6


def test_deck_off_a_cliff_stays_level():
    # A lookout built out over the water from a cliff 20 m up isn't a jetty
    # to walk down to the water from: it stays level with the top.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 20.0))
    deck = LineString([(6, 0), (-20, 0)]).buffer(2.0, cap_style=2)
    w = _world(hf, [(deck, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    d, = w._level_decks()
    assert d.landing is None and abs(d.top - 20.0) < 0.1


def test_jetties_side_by_side_blend_between_them():
    # Two jetties off one bank, metres apart at different heights (one off the
    # quay, one off the beach below it): the ground between them comes to each
    # and eases between, no tower or pit where their pads meet.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, np.where(N > 0, 4.0, 1.5)))
    high = LineString([(4, 8), (-40, 8)]).buffer(1.5, cap_style=2)
    low = LineString([(4, -8), (-40, -8)]).buffer(1.5, cap_style=2)
    w = _world(hf, [(high, "pier", 1), (low, "pier", 2)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    a, b = w._level_decks()
    on = hf.H[:, (np.asarray(hf.node_coords()[0]) >= 0)]
    assert on.max() <= max(a.top, 4.0) + 0.1 and on.min() >= min(b.top, 1.5) - 0.1
    ys = np.arange(-20.0, 25.0, STEP)
    col = hf.sample(np.full(len(ys), 5.0), ys)
    was = np.where(ys > 0, 4.0, 1.5)
    assert np.abs(np.diff(col)).max() <= np.abs(np.diff(was)).max() + 0.1   # no step the bank didn't have


def test_quay_along_the_bank_has_no_river_left_between_it_and_the_bank():
    # Elizabeth Quay: a promenade deck 7.5 m up runs along the bank, 8 m out
    # over the river. The river bed under its landward edge pulled the ground
    # drawn between it and the bank down into a 1.5 m pit beside the deck.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 7.5))
    quay = box(-8.0, -60.0, 0.5, 60.0)
    w = _world(hf, [(quay, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    d, = w._level_decks()
    assert abs(d.top - 7.5) < 0.1 and d.low is None
    ys = np.arange(-40.0, 40.0, 2.5)
    for x in (-3.0, -0.5):  # under its landward edge, and between it and the bank
        g = hf.sample(np.full(len(ys), x), ys)
        assert (np.abs(g - (d.top - 0.05)) < 0.1).all(), np.round(g, 2)
    # The river past its far edge is left as it was.
    assert abs(hf.sample(-15.0, 0.0) - (-2.5)) < 1e-9


def test_lone_corner_of_river_by_a_jetty_root_is_not_filled():
    # Coode St: a jetty straight out from the bank. The river either side of
    # where it leaves the bank isn't a quay's strip; it stays river.
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E < 0, -2.5, 3.0))
    jetty = LineString([(4, 1), (-60, 1)]).buffer(1.5, cap_style=2)
    w = _world(hf, [(jetty, "pier", 1)], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    w._level_decks()
    for y in (-5.0, 5.0, 10.0):
        assert hf.sample(-5.0, y) < 0.0


def test_jetty_has_a_rail_over_dry_river_bed_but_not_over_the_water():
    # Fremantle's boardwalk: beside one finger the river bed was dry, 0.8 m
    # under the deck, walled in by the quay; you dropped in and couldn't get
    # back up. That side has a rail. Over the water, and along the quay it
    # leaves (no drop), it doesn't.
    from osm_import.build import RAIL_H, Deck, TileBuilder
    from osm_import.meshbuild import MeshBuilder
    river = box(-300, -300, 0, 300)
    hf = field(lambda E, N: np.where(E >= 0, 2.0, np.where((N >= 0) & (E > -25), 1.2, -2.5)))
    jetty = LineString([(2, 0), (-40, 0)]).buffer(2.0, cap_style=2)
    w = _world(hf, [], [WaterBody(river, RIVER_LEVEL, True, "Swan River")])
    w.deck_parts = [Deck(jetty, "pier", 1, 2.0, -3.5)]
    tb = TileBuilder.__new__(TileBuilder)
    tb.w, tb.box, tb.mb = w, box(-300, -300, 300, 300), MeshBuilder()
    tb._decks()
    v, _, _, _ = tb.mb.surface("props", "concrete", "world").arrays()
    rail = v[v[:, 2] > 2.0 + RAIL_H / 2]
    assert len(rail)
    dry = rail[rail[:, 1] > 1.5]
    assert dry[:, 0].min() < -20.0 and dry[:, 0].min() > -27.0 and dry[:, 0].max() < 0.5
    assert (rail[rail[:, 1] < 1.5][:, 0] > -4.5).all()  # the other side: only over the bank's foot
