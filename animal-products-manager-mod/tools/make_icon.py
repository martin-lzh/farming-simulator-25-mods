# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==11.3.0"]
# ///
"""Draw the original icon: milk can and egg branching to store, sell and distribute."""
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
DARK, MID, LIGHT, LIME, CREAM, EGG = "#173a2f", "#24503f", "#2a5c48", "#b5dc63", "#f3f0dd", "#e9c597"
GOLD, GOLD_DARK, BADGE = "#f0c24a", "#c8962a", "#e7e3c9"
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

# Milk can.
d.rounded_rectangle(r((92, 128, 172, 156)), radius=10 * S, fill=LIME)
d.polygon(p([(104, 156), (160, 156), (160, 176), (192, 210), (72, 210), (104, 176)]), fill=CREAM)
d.rounded_rectangle(r((66, 200, 198, 404)), radius=22 * S, fill=CREAM)
d.rectangle(r((66, 262, 198, 304)), fill=LIME)
d.rounded_rectangle(r((40, 222, 66, 272)), radius=10 * S, outline=CREAM, width=10 * S)
d.rounded_rectangle(r((198, 222, 224, 272)), radius=10 * S, outline=CREAM, width=10 * S)
d.rounded_rectangle(r((84, 216, 96, 386)), radius=6 * S, fill="#fbfaf0")

# Egg in front of the can.
d.ellipse(r((150, 286, 246, 420)), fill=DARK)
d.ellipse(r((158, 294, 238, 412)), fill=EGG)
d.ellipse(r((174, 316, 194, 352)), fill="#f6e2c4")

# One arrow from the products branching to the three destinations.
d.line(p([(244, 256), (284, 256)]), fill=LIME, width=20 * S)
for y in (128, 256, 384):
    d.line(p([(276, 256), (300, y), (332, y)] if y != 256 else [(276, 256), (332, 256)]), fill=LIME, width=20 * S, joint="curve")
    d.polygon(p([(326, y - 24), (356, y), (326, y + 24)]), fill=LIME)
d.ellipse(r((266, 246, 286, 266)), fill=LIME)
for y in (128, 256, 384):
    d.ellipse(r((362, y - 54, 470, y + 54)), fill=CREAM)
    d.ellipse(r((370, y - 46, 462, y + 46)), fill=BADGE)

# Store: warehouse.
x, y = 416, 128
d.polygon(p([(x - 36, y - 4), (x, y - 32), (x + 36, y - 4)]), fill=DARK)
d.rectangle(r((x - 30, y - 6, x + 30, y + 30)), fill=DARK)
d.rectangle(r((x - 13, y + 6, x + 13, y + 30)), fill=LIME)
for line_y in (y + 13, y + 21):
    d.line(p([(x - 13, line_y), (x + 13, line_y)]), fill=DARK, width=3 * S)

# Sell: coin stack.
x, y = 416, 256
for coin_y in (y + 20, y + 6, y - 8):
    d.rounded_rectangle(r((x - 32, coin_y - 6, x + 32, coin_y + 12)), radius=9 * S, fill=GOLD_DARK)
    d.ellipse(r((x - 32, coin_y - 14, x + 32, coin_y + 4)), fill=GOLD)
d.ellipse(r((x - 18, y - 19, x + 18, y - 7)), outline=GOLD_DARK, width=3 * S)

# Distribute: factory with a saw-tooth roof and chimney.
x, y = 416, 384
d.rectangle(r((x + 14, y - 36, x + 26, y - 4)), fill=DARK)
d.polygon(p([(x - 34, y + 30), (x - 34, y - 6), (x - 14, y - 20), (x - 14, y - 6), (x + 6, y - 20),
             (x + 6, y - 6), (x + 34, y - 6), (x + 34, y + 30)]), fill=DARK)
for window_x in (x - 24, x - 6, x + 12):
    d.rectangle(r((window_x, y + 4, window_x + 10, y + 16)), fill=LIME)

source = root / "assets/icon.png"
source.parent.mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(source)
# ModHub wants a 512x512 BC1 icon without mipmaps.
with tempfile.TemporaryDirectory() as out:
    subprocess.run([args.texconv, "-f", "BC1_UNORM", "--ignore-srgb", "-m", "1",
                    "-y", "-o", out, str(source)], check=True)
    shutil.move(Path(out) / "icon.dds", root / "icon_animalProductsManager.dds")
