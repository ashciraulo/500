#!/usr/bin/env python3
"""Download the recorded source material used by gen_amb.py.

Every recording is listed in SOURCES below (freesound id, author, licence we
expect). For each one the script fetches the sound's own freesound page,
checks that the licence shown there is CC0 or CC-BY (anything else aborts),
pulls the high-quality preview (…-hq.mp3) into build/sources/<key>.mp3 and
records the page metadata in build/sources/manifest.json.

Already-downloaded files are skipped, so re-running is cheap. Needs only
curl. Run from any directory:

    python3 audio/tools/fetch_sources.py            # fetch everything
    python3 audio/tools/fetch_sources.py --verify   # re-check licences only
"""
from __future__ import annotations

import html
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "build" / "sources"
UA = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"

CC0 = "Creative Commons 0"
BY = "Attribution"  # CC-BY 3.0 / 4.0 (never NonCommercial, never Sampling+)

# key: (freesound id, author username, expected licence, short note)
SOURCES: dict[str, tuple[int, str, str, str]] = {
    # --- Kings Park / bush, Perth birds --------------------------------
    "mag_kp2":       (353060, "dbache", CC0, "Magpie family calling, Kings Park Perth"),
    "mag_dl":        (319767, "DangerLaef", CC0, "Australian magpies"),
    "kook_kp":       (671250, "dbache", CC0, "Kookaburra family, Kings Park WA"),
    "lorikeets":     (593156, "dannydandanshababaloo", CC0, "Rainbow lorikeets"),
    "cockatoo_perth": (514053, "bushtobazaar", CC0, "Black cockatoos at dusk, Perth"),
    "walyunga":      (523549, "bushtobazaar", CC0, "Walyunga National Park WA, bush ambience"),
    "raven_db":      (555187, "dbache", CC0, "Australian ravens defending territory"),
    "raven_yell":    (400395, "samarobryn", CC0, "Ravens ('crows') at Yellagonga, Perth"),
    "wagtail1":      (388734, "Inkahootz81", CC0, "Australian willie wagtail"),
    # --- night ---------------------------------------------------------
    "boobook1":      (409436, "Monkey Pants", CC0, "Boobook owl / mopoke"),
    "pobble1":       (512775, "volition74", CC0, "Pobblebonk (banjo frog) with cicadas"),
    "pobble2":       (530274, "Hypo_Mix", CC0, "Pobblebonk frogs"),
    "crickets_sub":  (699142, "roisin.gleeson", CC0, "Night crickets, suburban Adelaide"),
    # --- urban ---------------------------------------------------------
    "hydepark":      (691375, "arefrashidan", CC0, "Hyde Park Perth: park, light traffic, children"),
    "traffic_peak":  (680419, "EarJuice", CC0, "Main road traffic at peak hour, 60 km/h"),
    "traffic_night": (640635, "soundofsong", CC0, "Traffic ambience at night"),
    "bar_wa":        (490288, "veronicalyn", CC0, "Bar atmos"),
    "pub_crowd":     (828867, "wjb_88", CC0, "Bar crowd ambience"),
    "highway_wa":    (418097, "Kalaji", CC0, "Afternoon highway, Western Australia"),
    "freeway":       (795499, "nickeverest69", CC0, "Traffic passing on freeway"),
    "lawnmower":     (637653, "kyles", CC0, "Lawnmower, far distant"),
    "sprinkler":     (347025, "blaccard", CC0, "Impact sprinkler loop"),
    "dogs_far":      (820267, "IENBA", CC0, "Distant dogs barking"),
    "dog_far2":      (615258, "alberto59", CC0, "Distant dog barking"),
    # --- water / coast -------------------------------------------------
    "beach_day":     (790724, "DeppStudios1977", CC0, "Beach atmos, Australia, day"),
    "beach_night":   (790720, "DeppStudios1977", CC0, "Australian beach, night waves"),
    "laps_horn":     (470781, "earsaregood", CC0, "Australia: water laps, ship horn, bird"),
    "lapping":       (570955, "rj13", CC0, "Ocean waves lapping"),
    "ferry":         (452924, "kyles", CC0, "Small ferry engine, bassy"),
    "freo_train":    (351425, "dbache", CC0, "Cargo train leaving Port of Fremantle, signals"),
}


def curl(url: str, out: Path | None = None) -> str:
    cmd = ["curl", "-sS", "-L", "--fail", "-A", UA, url]
    if out is not None:
        subprocess.run(cmd + ["-o", str(out)], check=True)
        return ""
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def page_info(sid: int) -> dict:
    page = curl(f"https://freesound.org/s/{sid}/")
    lic = re.search(r'title="Go to the full license text" href="([^"]+)"[^>]*>([^<]+)</a>', page)
    prev = re.search(r'https://cdn\.freesound\.org/previews/[^"]+-hq\.mp3', page)
    title = re.search(r'<meta property="og:title" content="([^"]*)"', page)
    url = re.search(r'data-sound-page-url="([^"]+)"', page)
    if not (lic and prev):
        raise RuntimeError(f"could not parse freesound page for {sid}")
    return {
        "licence": html.unescape(lic.group(2)).strip(),
        "licence_url": lic.group(1),
        "preview": prev.group(0),
        "title": html.unescape(title.group(1)) if title else "",
        "url": url.group(1) if url else f"https://freesound.org/s/{sid}/",
    }


def licence_ok(found: str, expected: str) -> bool:
    if found == CC0:
        return expected == CC0
    # "Attribution 4.0" / "Attribution 3.0" only; reject NonCommercial etc.
    return expected == BY and re.fullmatch(r"Attribution( \d\.\d)?", found) is not None


def main() -> int:
    verify_only = "--verify" in sys.argv
    DEST.mkdir(parents=True, exist_ok=True)
    man_path = DEST / "manifest.json"
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {}
    bad = []
    (DEST / ".gdignore").touch()  # keep Godot from importing raw downloads
    for key, (sid, author, lic, note) in SOURCES.items():
        out = DEST / f"{key}.mp3"
        if out.exists() and key in manifest and not verify_only:
            continue
        info = page_info(sid)
        time.sleep(1.5)  # be polite
        if not licence_ok(info["licence"], lic):
            bad.append((key, sid, info["licence"]))
            print(f"!! {key} ({sid}): licence is '{info['licence']}', expected {lic}", file=sys.stderr)
            continue
        info.update(id=sid, author=author, note=note)
        manifest[key] = info
        if not out.exists():
            print(f"-> {key}: {info['title']} by {author} [{info['licence']}]", file=sys.stderr)
            part = out.with_suffix(".part")
            curl(info["preview"], part)
            part.rename(out)
            time.sleep(1.5)
        man_path.write_text(json.dumps(manifest, indent=1, ensure_ascii=False))
    man_path.write_text(json.dumps(manifest, indent=1, ensure_ascii=False))
    if bad:
        print(f"{len(bad)} source(s) failed the licence check", file=sys.stderr)
        return 1
    print(f"ok: {len(manifest)} sources in {DEST}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
