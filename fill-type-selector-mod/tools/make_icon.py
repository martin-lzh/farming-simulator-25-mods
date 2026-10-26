# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==11.3.0"]
# ///
"""Draw the original icon: a spreader hopper between a fertilizer and a lime bag, with a cycle arrow."""
from pathlib import Path
import argparse
import math
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
DARK, MID, LIGHT, LIME, CREAM = "#173a2f", "#24503f", "#2a5c48", "#b5dc63", "#f3f0dd"
STEEL, STEEL_DARK, GOLD, GOLD_DARK, CHALK = "#d9dccf", "#9aa59a", "#f0c24a", "#c8962a", "#fbfaf4"
p = lambda pts: [(x * S, y * S) for x, y in pts]
r = lambda b: tuple(v * S for v in b)

# Tile: lime rim around a dark green field with a soft light patch, as on the other Mod icons.
rim = Image.new("RGB", (512 * S, 512 * S), "#10261f")
ImageDraw.Draw(rim).rounded_rectangle(r((14, 14, 498, 498)), radius=76 * S, fill=LIME)
im = Image.new("RGB", rim.size, MID)
d = ImageDraw.Draw(im)
d.ellipse(r((-80, -60, 360, 380)), fill=LIGHT)
mask = Image.new("L", rim.size, 0)
ImageDraw.Draw(mask).rounded_rectangle(r((24, 24, 488, 488)), radius=68 * S, fill=255)
im = Image.composite(im, rim, mask)
d = ImageDraw.Draw(im)

# Cycle arrow above the hopper: two arcs, each ending in an arrowhead.
cx, cy, radius, width = 256, 128, 66, 18
box = r((cx - radius, cy - radius, cx + radius, cy + radius))
for start, end in ((200, 330), (20, 150)):
    d.arc(box, start=start, end=end, fill=LIME, width=width * S)
    angle = math.radians(end)
    tip_x, tip_y = cx + radius * math.cos(angle), cy + radius * math.sin(angle)
    # Arrowhead points along the direction of travel (clockwise in screen space).
    tangent = angle + math.pi / 2
    normal = angle
    head = [
        (tip_x + 30 * math.cos(tangent), tip_y + 30 * math.sin(tangent)),
        (tip_x + 24 * math.cos(normal), tip_y + 24 * math.sin(normal)),
        (tip_x - 24 * math.cos(normal), tip_y - 24 * math.sin(normal)),
    ]
    d.polygon(p(head), fill=LIME)

# Spreader hopper with a rim and two discs below.
d.rounded_rectangle(r((150, 222, 362, 248)), radius=8 * S, fill=LIME)
d.polygon(p([(160, 248), (352, 248), (296, 360), (216, 360)]), fill=STEEL)
d.polygon(p([(176, 248), (200, 248), (232, 356), (216, 360)]), fill=CHALK)
d.rectangle(r((236, 360, 276, 384)), fill=STEEL_DARK)
for disc_x in (214, 298):
    d.ellipse(r((disc_x - 40, 380, disc_x + 40, 404)), fill=DARK)
    d.ellipse(r((disc_x - 30, 384, disc_x + 30, 400)), fill=STEEL_DARK)
# Granules thrown out by the discs.
for gx, gy, size in ((130, 420, 9), (166, 440, 8), (204, 428, 7), (306, 428, 7), (346, 440, 8), (382, 420, 9),
                     (110, 446, 7), (402, 446, 7), (250, 444, 8)):
    d.ellipse(r((gx - size, gy - size, gx + size, gy + size)), fill=GOLD if gx < 256 else CHALK)


def bag(x, y, body, band, mark):
    """Upright sack with a tied top, a colored band and a simple mark."""
    d.polygon(p([(x - 40, y - 72), (x - 24, y - 92), (x + 24, y - 92), (x + 40, y - 72)]), fill=body)
    d.rounded_rectangle(r((x - 46, y - 76, x + 46, y + 40)), radius=18 * S, fill=body)
    d.rectangle(r((x - 14, y - 100, x + 14, y - 88)), fill=band)
    d.rectangle(r((x - 46, y - 30, x + 46, y - 4)), fill=band)
    mark(x, y)


def granules(x, y):
    for dx, dy in ((-14, 18), (0, 26), (14, 18)):
        d.ellipse(r((x + dx - 7, y + dy - 7, x + dx + 7, y + dy + 7)), fill=GOLD_DARK)


def powder(x, y):
    d.polygon(p([(x - 22, y + 32), (x, y + 10), (x + 22, y + 32)]), fill=STEEL_DARK)


bag(96, 330, CREAM, GOLD, granules)   # fertilizer
bag(416, 330, CHALK, STEEL_DARK, powder)  # lime

source = root / "assets/icon.png"
source.parent.mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(source)
# ModHub wants a 512x512 BC1 icon without mipmaps.
with tempfile.TemporaryDirectory() as out:
    subprocess.run([args.texconv, "-f", "BC1_UNORM", "--ignore-srgb", "-m", "1",
                    "-y", "-o", out, str(source)], check=True)
    shutil.move(Path(out) / "icon.dds", root / "icon_fillTypeSelector.dds")
