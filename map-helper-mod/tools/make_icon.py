# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==11.3.0"]
# ///
"""Draw the original icon: a map pin over a folded map, with a small tractor on its route."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--texconv", default=shutil.which("texconv") or str(root.parent / "work/tools/directxtex/texconv.exe"))
args = parser.parse_args()
if not Path(args.texconv).is_file():
    parser.error("Supply the Microsoft DirectXTex texconv executable with --texconv")

S = 4  # draw at 2048 px, then downsample
DARK, MID, LIGHT, LIME, CREAM, PAPER = "#173a2f", "#24503f", "#2a5c48", "#b5dc63", "#f3f0dd", "#ddd7b9"
FIELD, FIELD_DARK, GOLD, GOLD_DARK, WHITE = "#a9cf6a", "#8db357", "#f0c24a", "#c8962a", "#fbfaf0"
p = lambda pts: [(x * S, y * S) for x, y in pts]
r = lambda b: tuple(v * S for v in b)

# Tile: lime rim around a dark green field with a soft light patch.
rim = Image.new("RGB", (512 * S, 512 * S), "#10261f")
ImageDraw.Draw(rim).rounded_rectangle(r((14, 14, 498, 498)), radius=76 * S, fill=LIME)
im = Image.new("RGB", rim.size, MID)
d = ImageDraw.Draw(im)
d.ellipse(r((-80, -60, 360, 380)), fill=LIGHT)
mask = Image.new("L", rim.size, 0)
ImageDraw.Draw(mask).rounded_rectangle(r((24, 24, 488, 488)), radius=68 * S, fill=255)
im = Image.composite(im, rim, mask)
d = ImageDraw.Draw(im)

# Folded map: three panels in a zigzag, with a shadow underneath.
top = [(70, 214), (184, 184), (300, 214), (442, 184)]
bottom = [(70, 448), (184, 418), (300, 448), (442, 418)]
d.polygon(p([(x + 8, y + 10) for x, y in top + bottom[::-1]]), fill=DARK)
for i, color in enumerate((CREAM, PAPER, CREAM)):
    d.polygon(p([top[i], top[i + 1], bottom[i + 1], bottom[i]]), fill=color)

# Fields printed on the map.
d.polygon(p([(92, 262), (164, 244), (164, 300), (92, 318)]), fill=FIELD)
d.polygon(p([(206, 240), (282, 260), (282, 318), (206, 298)]), fill=FIELD_DARK)
d.polygon(p([(316, 244), (420, 218), (420, 270), (316, 296)]), fill=FIELD)

# Dashed route from the tractor to the pin.
route = [(166, 392), (214, 370), (262, 386), (316, 352), (346, 318)]
for (x1, y1), (x2, y2) in zip(route, route[1:]):
    steps = 3
    for s in range(steps):
        a, b = s / steps, (s + 0.55) / steps
        d.line(p([(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a), (x1 + (x2 - x1) * b, y1 + (y2 - y1) * b)]),
               fill=DARK, width=9 * S)

# Small tractor at the start of the route.
x, y = 126, 392
d.rounded_rectangle(r((x - 34, y - 26, x + 30, y + 4)), radius=6 * S, fill=DARK)
d.rectangle(r((x - 30, y - 58, x - 2, y - 24)), fill=DARK)
d.rectangle(r((x - 25, y - 53, x - 7, y - 32)), fill=LIME)
d.rectangle(r((x + 14, y - 44, x + 20, y - 26)), fill=DARK)
d.ellipse(r((x - 44, y - 14, x - 4, y + 26)), fill=DARK)
d.ellipse(r((x - 33, y - 3, x - 15, y + 15)), fill=LIME)
d.ellipse(r((x + 6, y - 2, x + 32, y + 24)), fill=DARK)
d.ellipse(r((x + 14, y + 6, x + 24, y + 16)), fill=LIME)

# Map pin above the destination.
cx, cy, radius = 346, 150, 82
d.ellipse(r((cx - radius - 8, cy - radius - 8, cx + radius + 8, cy + radius + 8)), fill=DARK)
d.polygon(p([(cx - 66, cy + 58), (cx, cy + 186), (cx + 66, cy + 58)]), fill=DARK)
d.ellipse(r((cx - radius, cy - radius, cx + radius, cy + radius)), fill=GOLD)
d.polygon(p([(cx - 58, cy + 52), (cx, cy + 172), (cx + 58, cy + 52)]), fill=GOLD)
d.polygon(p([(cx, cy + 172), (cx + 58, cy + 52), (cx + 30, cy + 70)]), fill=GOLD_DARK)
d.ellipse(r((cx - 34, cy - 34, cx + 34, cy + 34)), fill=WHITE)
d.ellipse(r((cx - 16, cy - 16, cx + 16, cy + 16)), fill=DARK)

source = root / "assets/icon.png"
source.parent.mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(source)
# ModHub wants a 512x512 BC1 icon without mipmaps.
with tempfile.TemporaryDirectory() as out:
    subprocess.run([args.texconv, "-f", "BC1_UNORM", "--ignore-srgb", "-m", "1",
                    "-y", "-o", out, str(source)], check=True)
    shutil.move(Path(out) / "icon.dds", root / "icon_mapHelper.dds")
