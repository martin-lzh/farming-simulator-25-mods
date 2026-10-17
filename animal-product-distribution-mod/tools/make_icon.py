# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==11.3.0"]
# ///
"""Draw the original bottle, egg and distribution-arrow icon."""
from pathlib import Path
import argparse
import shutil
import subprocess
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--texconv", default=shutil.which("texconv") or str(root.parent / "work/tools/directxtex/texconv.exe"))
args = parser.parse_args()
if not Path(args.texconv).is_file():
    parser.error("Supply the Microsoft DirectXTex texconv executable with --texconv")

scale = 2
im = Image.new("RGB", (512 * scale, 512 * scale), "#152e28")
d = ImageDraw.Draw(im)
def box(rect, fill, radius=0):
    r = tuple(v * scale for v in rect)
    d.rounded_rectangle(r, radius=radius * scale, fill=fill)
def polygon(points, fill):
    d.polygon([(x * scale, y * scale) for x, y in points], fill=fill)
box((24, 24, 488, 488), "#25483c", 62)
box((111, 114, 193, 144), "#b9dc65", 9)
polygon([(119, 146), (185, 146), (185, 176), (211, 212), (211, 327), (93, 327), (93, 212), (119, 176)], "#f2f1de")
box((93, 225, 211, 285), "#b9dc65")
d.ellipse((241 * scale, 192 * scale, 329 * scale, 327 * scale), fill="#ebc99c")
box((357, 149, 417, 200), "#b9dc65", 8)
box((357, 270, 417, 321), "#b9dc65", 8)
polygon([(246, 145), (293, 145), (293, 115), (335, 160), (293, 205), (293, 175), (246, 175)], "#f2f1de")
polygon([(97, 380), (338, 380), (338, 353), (387, 396), (338, 439), (338, 412), (97, 412)], "#b9dc65")
source = root / "assets/icon.png"
source.parent.mkdir(parents=True, exist_ok=True)
im.resize((512, 512), Image.Resampling.LANCZOS).save(source)
subprocess.run([args.texconv, "-f", "BC1_UNORM", "--ignore-srgb", "-m", "0", "-if", "BOX",
                "-y", "-o", str(root), str(source)], check=True)
