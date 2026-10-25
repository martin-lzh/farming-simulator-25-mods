# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==11.3.0"]
# ///
"""Draw the original icon: a factory whose output arrow splits into a pallet and a coin."""
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
DARK, MID, LIGHT, LIME, CREAM = "#173a2f", "#24503f", "#2a5c48", "#b5dc63", "#f3f0dd"
STEEL, STEEL_DARK, GOLD, GOLD_DARK, WOOD, WOOD_DARK = "#d9dccf", "#9aa59a", "#f0c24a", "#c8962a", "#c9955a", "#8f6236"
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

# Factory on the left: saw-tooth roof, chimney with smoke, door and windows.
d.rectangle(r((150, 86, 182, 170)), fill=STEEL_DARK)
for cx, cy, radius in ((176, 66, 16), (204, 50, 12), (228, 40, 9)):
    d.ellipse(r((cx - radius, cy - radius, cx + radius, cy + radius)), fill=CREAM)
d.polygon(p([(64, 300), (64, 196), (120, 150), (120, 196), (176, 150), (176, 196), (232, 150), (232, 300)]), fill=STEEL)
d.rectangle(r((64, 300, 232, 318)), fill=STEEL_DARK)
for wx in (84, 140):
    d.rectangle(r((wx, 222, wx + 36, 252)), fill=DARK)
d.rectangle(r((180, 236, 214, 300)), fill=DARK)

# Output arrow leaving the factory, then splitting up and down.
d.rectangle(r((232, 244, 300, 270)), fill=LIME)
d.rounded_rectangle(r((290, 150, 316, 364)), radius=10 * S, fill=LIME)
d.rectangle(r((300, 150, 350, 176)), fill=LIME)
d.rectangle(r((300, 338, 350, 364)), fill=LIME)
d.polygon(p([(346, 134), (380, 163), (346, 192)]), fill=LIME)
d.polygon(p([(346, 322), (380, 351), (346, 380)]), fill=LIME)

# Pallet with stacked bags at the upper branch.
d.rectangle(r((388, 176, 468, 186)), fill=WOOD)
for bx in (390, 422, 456):
    d.rectangle(r((bx, 186, bx + 12, 200)), fill=WOOD_DARK)
d.rectangle(r((388, 198, 468, 206)), fill=WOOD)
for bx, by in ((392, 140), (430, 140), (411, 104)):
    d.rounded_rectangle(r((bx, by, bx + 36, by + 36)), radius=8 * S, fill=CREAM)
    d.rectangle(r((bx + 4, by + 14, bx + 32, by + 22)), fill=GOLD_DARK)

# Coin at the lower branch.
d.ellipse(r((388, 312, 468, 392)), fill=GOLD_DARK)
d.ellipse(r((394, 316, 462, 384)), fill=GOLD)
d.ellipse(r((408, 330, 448, 370)), outline=GOLD_DARK, width=6 * S)

# Ground line under the factory.
d.rounded_rectangle(r((52, 330, 244, 344)), radius=6 * S, fill=DARK)

source = root / "assets/icon.png"
source.parent.mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(source)
# ModHub wants a 512x512 BC1 icon without mipmaps.
with tempfile.TemporaryDirectory() as out:
    subprocess.run([args.texconv, "-f", "BC1_UNORM", "--ignore-srgb", "-m", "1",
                    "-y", "-o", out, str(source)], check=True)
    shutil.move(Path(out) / "icon.dds", root / "icon_productionOverflow.dds")
