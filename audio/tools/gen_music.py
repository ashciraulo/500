#!/usr/bin/env python3
"""Generate the game's music: Italian 60s/70s lounge and library pieces
composed in code, rendered with FluidSynth + FluidR3_GM (MIT), then run
through a worn-VHS tape chain.

Usage (from any directory):
    python3 audio/tools/gen_music.py             # every track
    python3 audio/tools/gen_music.py mus_main_theme mus_sting_failed
    python3 audio/tools/gen_music.py --list

Output: audio/music/<name>.ogg (48 kHz stereo, -16 LUFS, OGG q6).
Requires: fluidsynth (CLI), /usr/share/sounds/sf2/FluidR3_GM.sf2, ffmpeg,
python3 with numpy, scipy, soundfile, pyloudnorm. Deterministic: the same
code gives the same files. Rendered stems are cached in the system temp dir.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import music_core as mc  # noqa: E402
import sfxlib  # noqa: E402
import music_tracks_main as tm  # noqa: E402


def _main_theme():
    y, s = tm.main_theme()
    return {"mus_main_theme": (y, True)}


def _mission():
    yb, yi, s = tm.mission_tension()
    # the intensity layer keeps its level relative to the base (see docs)
    return {"mus_mission_tension_base": (yb, True),
            "mus_mission_tension_intensity": (yi, True, "none")}


# name -> builder; a builder may produce several files (stems, variants)
TRACKS = {
    "mus_main_theme": _main_theme,
    "mus_mission_tension": _mission,
    "mus_sting_complete": lambda: {"mus_sting_complete": (tm.sting_complete(), False)},
    "mus_sting_failed": lambda: {"mus_sting_failed": (tm.sting_failed(), False)},
    "mus_sting_tier_unlock": lambda: {"mus_sting_tier_unlock": (tm.sting_tier_unlock(), False)},
    "mus_midnight_theme": lambda: {"mus_midnight_theme": (tm.midnight_theme(), True)},
    "mus_sting_new_car": lambda: {"mus_sting_new_car": (tm.sting_new_car(), False)},
}


def _register():
    try:
        import music_tracks_more as tmore  # noqa: F401
        TRACKS.update(tmore.TRACKS)
    except ImportError:
        pass


def main(argv):
    _register()
    if "--list" in argv:
        print("\n".join(TRACKS))
        return
    names = [a for a in argv if not a.startswith("-")] or list(TRACKS)
    # a name may refer to one output of a multi-output builder
    builders = []
    for n in names:
        key = n if n in TRACKS else next((k for k in TRACKS if n.startswith(k)), None)
        if key is None:
            raise SystemExit(f"unknown track {n}; try --list")
        if key not in builders:
            builders.append(key)
    for key in builders:
        t0 = time.time()
        outs = TRACKS[key]()
        for name, spec in outs.items():
            y, loop = spec[0], spec[1]
            norm = spec[2] if len(spec) > 2 else "music"
            mc.analyse(name, y, loop)
            sfxlib.save(f"music/{name}", y, norm=norm)
        print(f"  ({time.time() - t0:.0f}s)", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
