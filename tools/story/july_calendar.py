"""The shed's calendar turned over to JULY 1979, the 11th in red (the
finale, STORY.md). Same size and plate font as the model's own MARCH page
(art/models/scripts/lib/shed_reveal.py _calendar_img), which the game swaps
for this one once the shed is open.

    python3 tools/story/july_calendar.py
"""
import ast
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "art/models/home/mystery/shed_calendar_july.png"
W, H = 28, 30


def _font():
    src = (ROOT / "art/models/scripts/lib/textures.py").read_text()
    for node in ast.parse(src).body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "FONT":
            return ast.literal_eval(node.value)
    raise SystemExit("no FONT in textures.py")


def _text(font, lines, w, h, top=1):
    rows = []
    for i, line in enumerate(lines):
        rows.append((line, (w - 4 * len(line) + 1) // 2, h - top - (i + 1) * 6))

    def ink(x, y):
        for line, x0, y0 in rows:
            gx, gy = x - x0, y - y0
            if 0 <= gx < 4 * len(line) and 0 <= gy < 5:
                lx, ly = gx % 4, gy
                if lx < 3 and font.get(line[gx // 4], font[" "])[(4 - ly) * 3 + lx] == "1":
                    return True
        return False
    return ink


def page(month, red):
    """`red` is the (column, row) of the coloured-in day, rows from the top."""
    text = _text(_font(), [month, "1979"], W, H)

    def px(x, y):
        if text(x, y):
            return (0.12, 0.12, 0.14)
        if 1 <= y <= 16 and 1 <= x <= 25:
            if (x - 1) % 4 == 0 or (16 - y) % 3 == 0:
                return (0.55, 0.5, 0.42)
            if (x - 1) // 4 == red[0] and (16 - y) // 3 == red[1]:
                return (0.75, 0.1, 0.08)
        return (0.95, 0.93, 0.86)

    im = Image.new("RGB", (W, H))
    for y in range(H):
        for x in range(W):
            im.putpixel((x, H - 1 - y), tuple(round(c * 255) for c in px(x, y)))
    return im


if __name__ == "__main__":
    # July 1979 began on a Sunday: the 11th is the Wednesday of the second week.
    page("JULY", (3, 1)).save(OUT)
    print("wrote", OUT)
