# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.1.1", "numpy==2.4.3"]
# ///
"""Render a GIANTS Engine GUI scenario to a static HTML page (GUI preview lab).

    uv run tools/gui_lab/render.py tools/gui_lab/scenarios/calibration-active-workers.json

Writes outputs/gui-lab/<name>.html. Converted textures and tinted slices are cached in
work/gui-lab/cache/. Game files are read from the ignored work/ folder and never copied
into tracked files. See tools/gui_lab/README.md for the scenario format.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gui_engine as g  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REFERENCE = ROOT / "work" / "reference" / "1.25.0.0" / "dataS-archive"
CACHE = ROOT / "work" / "gui-lab" / "cache"
OUTPUT = ROOT / "outputs" / "gui-lab"
TEXCONV = ROOT / "work" / "tools" / "directxtex" / "texconv.exe"

# Texture configs registered by main.lua (prefix -> path inside dataS).
BASE_TEXTURE_CONFIGS = {
    "gui": "menu/gui.xml",
    "ui_elements": "menu/ui_elements.xml",
    "mapHotspots": "menu/hud/mapHotspots.xml",
}

DEFAULT_KEYS = {
    "MENU_BACK": "Esc", "MENU_ACCEPT": "Enter", "MENU_ACTIVATE": "Space",
    "MENU_CANCEL": "Backspace", "MENU_PAGE_PREV": "Q", "MENU_PAGE_NEXT": "E",
    "MENU_EXTRA_1": "X", "MENU_EXTRA_2": "C", "INGAMEMAP_ACCEPT": "Enter",
    "MENU_MAP_ACTION_1": "R",
}

FONT_STACK = "'Noto Sans SC', 'Microsoft YaHei', 'Nunito Sans', sans-serif"
MEASURE_FONTS = {
    False: ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/NotoSansSC-VF.ttf"],
    True: ["C:/Windows/Fonts/msyhbd.ttc", "C:/Windows/Fonts/NotoSansSC-VF.ttf"],
}


# ------------------------------------------------------------------ helpers

def linear_to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def css_color(color) -> str:
    r, g_, b = (round(linear_to_srgb(v) * 255) for v in color[:3])
    a = max(0.0, min(1.0, color[3]))
    return f"rgba({r},{g_},{b},{a:.3f})"


def corner_colors(color):
    """(BL, TL, BR, TR) colours; a 4-value colour applies to all corners."""
    if len(color) == 16:
        return [color[i:i + 4] for i in range(0, 16, 4)]
    return [color[:4]] * 4


def css_fill(color) -> str:
    bl, tl, br, tr = corner_colors(color)
    if bl == tl == br == tr:
        return f"background:{css_color(bl)}"
    if bl == tl and br == tr:
        return f"background:linear-gradient(to right,{css_color(bl)},{css_color(br)})"
    if bl == br and tl == tr:
        return f"background:linear-gradient(to bottom,{css_color(tl)},{css_color(bl)})"
    # Bilinear corners: a right-to-left gradient per edge, blended top to bottom by a mask is
    # not possible on one background, so average each edge (exact for separable gradients).
    top = [(a + b) / 2 for a, b in zip(tl, tr)]
    bottom = [(a + b) / 2 for a, b in zip(bl, br)]
    return f"background:linear-gradient(to bottom,{css_color(top)},{css_color(bottom)})"


def resolve_path(text: str, reference: Path, base: Path | None = None) -> Path:
    if text.startswith("$ref/"):
        return reference / text[len("$ref/"):]
    path = Path(text)
    if path.is_absolute():
        return path
    if base is not None and (base / path).exists():
        return base / path
    return ROOT / path


class FontMeasurer(g.TextMeasurer):
    """Measures with a local CJK font through Pillow; falls back to the heuristic."""

    def __init__(self, scale: float = 1.0):
        self.scale = scale
        self.fonts = {}
        for bold, candidates in MEASURE_FONTS.items():
            for candidate in candidates:
                if Path(candidate).exists():
                    self.fonts[bold] = candidate
                    break
        self.cache = {}

    def width_px(self, text: str, size_px: float, bold: bool) -> float:
        size_px *= self.scale
        path = self.fonts.get(bold) or self.fonts.get(False)
        if not path or size_px <= 0:
            return super().width_px(text, size_px, bold)
        key = (path, round(size_px * 4))
        font = self.cache.get(key)
        if font is None:
            font = ImageFont.truetype(path, max(1, round(size_px * 4)))
            self.cache[key] = font
        return font.getlength(text) / 4


# ------------------------------------------------------------------ textures

class Atlas:
    def __init__(self, prefix: str, xml_path: Path):
        root = g.parse_xml(str(xml_path))
        meta = root.find("meta")
        filename = meta.findtext("filename") if meta is not None else None
        size = meta.find("size") if meta is not None else None
        self.size = (int(size.get("width")), int(size.get("height"))) if size is not None else None
        self.prefix = prefix
        self.slices = {}
        for item in root.iter("slice"):
            parts = [float(p.replace("px", "")) for p in item.get("uvs", "").split()]
            if len(parts) == 4:
                self.slices[item.get("id")] = parts
        stem = Path(filename or xml_path.with_suffix(".png").name).stem
        self.dds = xml_path.parent / f"{stem}.dds"
        self.png_source = xml_path.parent / f"{stem}.png"
        self._image = None

    def image(self) -> Image.Image | None:
        if self._image is None:
            png = convert_texture(self.dds if self.dds.exists() else self.png_source, self.prefix)
            if png is None:
                return None
            self._image = Image.open(png).convert("RGBA")
        return self._image


def convert_texture(source: Path, tag: str) -> Path | None:
    """DDS -> PNG with texconv into work/gui-lab/cache/textures (cached by mtime)."""
    if not source.exists():
        return None
    if source.suffix.lower() == ".png":
        return source
    out_dir = CACHE / "textures" / tag
    out = out_dir / f"{source.stem}.png"
    if out.exists() and out.stat().st_mtime >= source.stat().st_mtime:
        return out
    if not TEXCONV.exists():
        print(f"warning: {TEXCONV} missing, cannot convert {source}", file=sys.stderr)
        return None
    out_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(TEXCONV), "-nologo", "-y", "-ft", "png", "-o", str(out_dir), str(source)],
                   check=True, capture_output=True)
    return out


class SliceCache:
    def __init__(self, atlases: dict[str, Atlas], html_dir: Path):
        self.atlases = atlases
        self.html_dir = html_dir
        self.dir = CACHE / "slices"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.solid = {}

    def lookup(self, slice_id: str):
        if "." not in slice_id:
            return None, None
        prefix, name = slice_id.rsplit(".", 1) if slice_id.count(".") > 1 else slice_id.split(".", 1)
        atlas = self.atlases.get(prefix)
        if atlas is None or name not in atlas.slices:
            return None, None
        return atlas, atlas.slices[name]

    def is_solid_white(self, slice_id: str) -> bool:
        if slice_id in self.solid:
            return self.solid[slice_id]
        atlas, uvs = self.lookup(slice_id)
        result = False
        if atlas is not None and atlas.image() is not None:
            x, y, w, h = (int(v) for v in uvs)
            region = np.asarray(atlas.image().crop((x, y, x + w, y + h)))
            result = bool(region.size) and region.min() >= 250
        self.solid[slice_id] = result
        return result

    def tinted(self, slice_id: str, color, invert_x: bool = False, rotation=None) -> str | None:
        """Crop the slice and multiply it with the (linear) colour in linear space."""
        atlas, uvs = self.lookup(slice_id)
        if atlas is None or atlas.image() is None:
            return None
        key = json.dumps([slice_id, [round(c, 5) for c in color], invert_x, rotation])
        name = hashlib.sha1(key.encode()).hexdigest()[:16] + ".png"
        path = self.dir / name
        if not path.exists():
            x, y, w, h = (int(round(v)) for v in uvs)
            crop = atlas.image().crop((x, y, x + w, y + h))
            if invert_x:
                crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if rotation:
                crop = crop.rotate(-90 * int(rotation), expand=True)
            data = np.asarray(crop).astype(np.float32) / 255.0
            rgb = data[..., :3]
            lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
            corners = corner_colors(color)
            hh, ww = data.shape[0], data.shape[1]
            fx = np.linspace(0, 1, ww)[None, :, None]
            fy = np.linspace(0, 1, hh)[:, None, None]  # 0 = top
            bl, tl, br, tr = (np.array(c, dtype=np.float32) for c in corners)
            top = tl * (1 - fx) + tr * fx
            bottom = bl * (1 - fx) + br * fx
            tint = top * (1 - fy) + bottom * fy
            out_lin = lin * tint[..., :3]
            out = np.where(out_lin <= 0.0031308, out_lin * 12.92, 1.055 * np.power(out_lin, 1 / 2.4) - 0.055)
            alpha = data[..., 3:4] * tint[..., 3:4]
            result = np.concatenate([out, alpha], axis=-1)
            Image.fromarray(np.clip(result * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(path)
        return os.path.relpath(path, self.html_dir).replace("\\", "/")


# ------------------------------------------------------------------ scenario

def load_l10n(reference: Path, language: str | None, extra: dict) -> dict:
    texts = {}
    if language:
        path = reference / "l10n" / f"l10n_{language}.xml"
        if path.exists():
            root = g.parse_xml(str(path))
            for item in root.iter("e"):
                texts[item.get("k")] = item.get("v")
    texts.update(extra or {})
    return texts


def find_path(root: g.Element, key: str) -> list:
    """Override keys: `id`, `name`, `id[3]` (3rd child), `outer/inner` (search below)."""
    current = [root]
    for segment in key.split("/"):
        index = None
        if segment.endswith("]") and "[" in segment:
            segment, _, rest = segment.partition("[")
            index = int(rest[:-1])
        found = []
        for base in current:
            if index is None or segment:
                matches = [e for e in base.iter() if e is not base and (e.id == segment or e.name == segment)] \
                    if segment else [base]
            else:
                matches = [base]
            if index is not None:
                matches = [m.children[index - 1] for m in matches if 0 < index <= len(m.children)]
            found.extend(matches)
        # an id is unique: prefer id matches over name matches
        ids = [e for e in found if e.id == segment] if segment else []
        current = ids or found
    return current


def inject(builder: g.GuiBuilder, root: g.Element, spec: dict, reference: Path) -> None:
    """Mod pattern: g_gui:loadProfileSet(xml, "GUI.GuiProfiles") then loadGuiRec(xml, "GUI", parent)."""
    path = resolve_path(spec["file"], reference)
    node = g.parse_xml(str(path))
    profiles = g.child_by_tag(node, "GUIProfiles")
    if profiles is not None:
        builder.store.load_profile_set(profiles, override=spec.get("overrideProfiles", False))
    parent_key = spec.get("parent")
    parents = find_path(root, parent_key) if parent_key else [root]
    if not parents:
        raise SystemExit(f"injection parent '{parent_key}' not found")
    parent = parents[0]
    source = path.name
    before = len(parent.children)
    builder.load_rec(node, parent, source)
    if spec.get("index") is not None:
        new = parent.children[before:]
        del parent.children[before:]
        for offset, element in enumerate(new):
            parent.children.insert(spec["index"] + offset, element)


def build(scenario: dict, scenario_dir: Path):
    reference = resolve_path(scenario.get("reference", str(DEFAULT_REFERENCE)), DEFAULT_REFERENCE)
    width, height = scenario.get("screen", [1920, 1080])
    screen = g.Screen(width, height)
    store = g.ProfileStore()
    store.load_profiles_file(g.parse_xml(str(reference / "guiProfiles.xml")))
    l10n = load_l10n(reference, scenario.get("language"), scenario.get("l10n"))
    keys = dict(DEFAULT_KEYS)
    keys.update(scenario.get("keys", {}))
    measurer = FontMeasurer(scenario.get("fontScale", 1.0))
    builder = g.GuiBuilder(store, screen, l10n, measurer, keys)

    base_path = resolve_path(scenario["base"], reference)
    root = builder.load_gui(g.parse_xml(str(base_path)), base_path.name)
    for spec in scenario.get("injections", []):
        inject(builder, root, spec, reference)

    overrides = scenario.get("overrides", {})
    missing = []
    for key, value in overrides.items():
        targets = find_path(root, key)
        if not targets:
            missing.append(key)
        for target in targets:
            g.apply_override(builder, target, value)
            if target.upper in ("MULTITEXTOPTION", "OPTIONTOGGLE", "BINARYOPTION"):
                g.update_option_content(target)
    root.update_absolute_position()
    for key, data in scenario.get("lists", {}).items():
        targets = [t for t in find_path(root, key) if t.upper == "SMOOTHLIST"]
        if not targets:
            missing.append(key)
        for target in targets:
            selected = scenario.get("listSelection", {}).get(key, 1)
            g.populate_list(builder, target, data, selected)
    # overrides addressed into list cells (e.g. "activeWorkerList/title") run after population
    for key, value in scenario.get("cellOverrides", {}).items():
        for target in find_path(root, key):
            g.apply_override(builder, target, value)
    g.finish_layout(builder, root)
    for key in scenario.get("lists", {}):
        for target in find_path(root, key):
            update_empty_indicator(root, target)
    g.finish_layout(builder, root)
    return root, builder, reference, missing


def update_empty_indicator(root: g.Element, lst: g.Element) -> None:
    """SmoothList hides its emptyIndicatorId element when it has items."""
    indicator = lst.attr("emptyIndicatorId")
    if indicator and lst.extra.get("itemCount", 0) > 0:
        for element in root.iter():
            if element.id == indicator:
                element.visible = False
    # SmoothListElement:updateScrollClippers (view offset 0: start hidden, end shown if content overflows)
    content = lst.extra.get("contentSize", 0.0)
    overflow = content > 0 and content - lst.abs_size[1] > 0.01
    for attr, visible in (("startClipperElementName", False), ("endClipperElementName", overflow)):
        name = lst.attr(attr)
        if name and lst.parent is not None:
            for element in lst.parent.iter():
                if element.name == name:
                    element.visible = visible and lst.visible


# ------------------------------------------------------------------ HTML

class HtmlWriter:
    def __init__(self, scenario, builder, slices: SliceCache, root: g.Element):
        self.scenario = scenario
        self.builder = builder
        self.slices = slices
        self.root = root
        self.screen = builder.screen
        self.font_scale = scenario.get("fontScale", 1.0)
        self.outline = scenario.get("outline", False)
        self.unknown = 0
        self.out = []

    def overlay_html(self, overlay: dict, state: str, x, y, w, h, extra_style="") -> str:
        if overlay is None or w <= 0 or h <= 0:
            return ""
        color = g.overlay_color(overlay, state)
        alphas = [c[3] for c in corner_colors(color)]
        if max(alphas) <= 0:
            return ""
        box = f"left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px"
        if overlay.get("file"):
            src = os.path.relpath(resolve_path(overlay["file"], DEFAULT_REFERENCE), OUTPUT).replace("\\", "/")
            return f'<div class="o" style="{box};background-image:url(\'{src}\');{extra_style}"></div>'
        slice_id = g.overlay_slice(overlay, state)
        if slice_id is None and not overlay.get("filename"):
            return ""  # GuiOverlay.loadOverlay: no file and no slice -> nothing is drawn
        if slice_id is None or self.slices.is_solid_white(slice_id):
            return f'<div class="o" style="{box};{css_fill(color)};{extra_style}"></div>'
        src = self.slices.tinted(slice_id, color, overlay.get("invertX", False), overlay.get("rotation"))
        if src is None:
            return (f'<div class="o missing" title="missing slice {html.escape(slice_id)}" '
                    f'style="{box};{css_fill(color)};{extra_style}"></div>')
        return f'<div class="o" style="{box};background-image:url(\'{src}\');{extra_style}"></div>'

    def text_html(self, e: g.Element, rect, extra_x=0.0) -> str:
        layout = g.text_layout(e, self.builder.measurer)
        if layout is None:
            return ""
        ex, ey, _, _ = rect
        parts = []
        size = layout["size_px"] * self.font_scale
        weight = 700 if layout["bold"] else 400
        shift = {"left": "0", "center": "-50%", "right": "-100%"}[layout["align"]]
        for line in layout["lines"]:
            x = line["x"] - ex + extra_x
            parts.append(
                f'<div class="tl" data-b="{line["baseline"] - ey:.2f}" style="left:{x:.2f}px;'
                f'top:{line["baseline"] - ey - size * 0.94:.2f}px;font-size:{size:.2f}px;'
                f'font-weight:{weight};color:{css_color(layout["color"])};'
                f'transform:translateX({shift})">{html.escape(line["text"])}</div>')
        return "".join(parts)

    def key_glyph_html(self, key: str, x, y, w, h, text_color, bg_color) -> str:
        """ButtonOverlay:renderButton: button_left/middle/right tinted with iconBg colour."""
        cap = h * 6 / 25
        out = [self.overlay_html({"slices": {"": "gui.button_left"}, "colors": {"": bg_color}}, "", x, y, cap, h),
               self.overlay_html({"slices": {"": "gui.button_middle"}, "colors": {"": bg_color}}, "", x + cap, y, max(w - 2 * cap, 0), h),
               self.overlay_html({"slices": {"": "gui.button_right"}, "colors": {"": bg_color}}, "", x + w - cap, y, cap, h)]
        size = h * g.KEY_GLYPH_TEXT_FACTOR * self.font_scale
        # renderText with VERTICAL_ALIGN_MIDDLE at the box centre, raised by textYOffsetFactor
        out.append(f'<div class="kg" style="left:{x:.2f}px;top:{y - size * 0.17:.2f}px;width:{w:.2f}px;'
                   f'height:{h:.2f}px;font-size:{size:.2f}px;color:{css_color(text_color)}">'
                   f'{html.escape(key.upper())}</div>')
        return "".join(out)

    def element(self, e: g.Element, parent_rect) -> None:
        if not e.visible:
            return
        x, y, w, h = e.rect_px()
        px, py = parent_rect[0], parent_rect[1]
        upper = e.upper
        classes = ["el"]
        style = [f"left:{x - px:.2f}px;top:{y - py:.2f}px;width:{max(w, 0):.2f}px;height:{max(h, 0):.2f}px"]
        if e.clipping:
            style.append("overflow:hidden")
        known = upper in g.KNOWN_TYPES or upper in g.BITMAP_TYPES
        if not known:
            classes.append("unknown")
            self.unknown += 1
        if self.outline:
            classes.append("outline")
        if e.extra.get("newLayer"):
            classes.append("layer")
        title = html.escape(e.label + f" [{x:.0f},{y:.0f} {w:.0f}x{h:.0f}]", quote=True)
        self.out.append(f'<div class="{" ".join(classes)}" title="{title}" style="{";".join(style)}">')
        state = e.state
        local = (0.0, 0.0)
        rect = (x, y, w, h)
        if upper == "INGAMEMAP":
            bg = self.scenario.get("map", {})
            fill = bg.get("color", "#2f4f2a")
            image = bg.get("image")
            css = f"background:{fill}"
            if image:
                src = os.path.relpath(resolve_path(image, DEFAULT_REFERENCE), OUTPUT).replace("\\", "/")
                css += f";background-image:url('{src}');background-size:cover"
            self.out.append(f'<div class="o map" style="left:0;top:0;width:{w:.2f}px;height:{h:.2f}px;{css}"></div>')
        elif upper == "THREEPARTBITMAP":
            self.three_part(e, state, w, h)
        elif upper == "ROUNDCORNER":
            colors = e.extra["colors"]
            color = colors.get(state) or colors[""]
            radius = min(e.extra["cornerSize"] * 20 * self.screen.ui_scale, w / 2, h / 2)
            if max(c[3] for c in corner_colors(color)) > 0:
                self.out.append(f'<div class="o" style="left:0;top:0;width:{w:.2f}px;height:{h:.2f}px;'
                                f'{css_fill(color)};border-radius:{radius:.2f}px"></div>')
        elif upper == "BUTTON":
            # ButtonElement renders its image with self.size (not the stretched absSize)
            bw = e.size[0] * self.screen.width
            bh = e.size[1] * self.screen.height
            self.out.append(self.overlay_html(e.extra.get("image"), state, 0, h - bh, bw, bh))
        elif upper == "SLIDER":
            self.slider(e, state, w, h)
        elif upper in g.BITMAP_TYPES and "image" in e.extra:
            self.out.append(self.overlay_html(e.extra["image"], state, 0, 0, w, h))
        if upper == "TEXT":
            self.out.append(self.text_html(e, rect))
        elif upper == "BUTTON":
            self.button_content(e, state, rect)
        elif upper == "INPUTGLYPH":
            key = e.extra.get("glyphKey") or self.builder.keys.get(e.extra.get("inputAction") or "", "")
            if key:
                gw = g.key_glyph_width(self.builder, key, e.abs_size[1], self.screen) * self.screen.width
                gx = 0 if e.extra.get("isLeftAligned") else w - gw
                bg = e.extra.get("glyphBackgroundColor") or [0.00913, 0.01033, 0.00651, 1.0]
                self.out.append(self.key_glyph_html(key, gx, 0, gw, h,
                                                    e.extra.get("glyphColor") or [1, 1, 1, 1], bg))
        for child in e.children:
            self.element(child, rect)
        self.out.append("</div>")

    def three_part(self, e, state, w, h):
        start, end = e.extra["startSize"], e.extra["endSize"]
        s = self.screen
        if e.extra["isHorizontal"]:
            sw, ew = start[0] * s.width, end[0] * s.width
            self.out.append(self.overlay_html(e.extra["startImage"], state, 0, 0, sw, h))
            self.out.append(self.overlay_html(e.extra["image"], state, sw, 0, w - sw - ew, h))
            self.out.append(self.overlay_html(e.extra["endImage"], state, w - ew, 0, ew, h))
        else:
            sh, eh = start[1] * s.height, end[1] * s.height
            self.out.append(self.overlay_html(e.extra["startImage"], state, 0, 0, w, sh))
            self.out.append(self.overlay_html(e.extra["image"], state, 0, sh, w, h - sh - eh))
            self.out.append(self.overlay_html(e.extra["endImage"], state, 0, h - eh, w, eh))

    def slider(self, e, state, w, h):
        """SliderElement:draw: background, then the bar only when the list needs scrolling."""
        bw, bh = e.size[0] * self.screen.width, e.size[1] * self.screen.height
        self.out.append(self.overlay_html(e.extra.get("image"), state, 0, 0, bw, bh))
        target = None
        if e.extra.get("dataElementId"):
            for element in self.root.iter():
                if element.id == e.extra["dataElementId"]:
                    target = element
                    break
        if target is None or target.upper != "SMOOTHLIST":
            return
        content = target.extra.get("contentSize", 0.0)
        view = target.abs_size[1]
        if content <= view or content <= 0:
            return
        ratio = view / content
        s = self.screen
        size = max(h * ratio, (e.extra["startSize"][1] + e.extra["endSize"][1]) * s.height, h * 0.025)
        if e.extra["isThreePartBitmap"]:
            sh, eh = e.extra["startSize"][1] * s.height, e.extra["endSize"][1] * s.height
            self.out.append(self.overlay_html(e.extra["startImage"], state, 0, 0, w, sh))
            self.out.append(self.overlay_html(e.extra["slider"], state, 0, sh, w, size - sh - eh))
            self.out.append(self.overlay_html(e.extra["endImage"], state, 0, size - eh, w, eh))
        else:
            self.out.append(self.overlay_html(e.extra["slider"], state, 0, 0, w, size))

    def button_content(self, e, state, rect):
        """ButtonElement:draw: text, then icon or keyboard key glyph left of the text."""
        s = self.screen
        icon_w, icon_h = g.button_icon_size(self.builder, e)
        ito = norm_xy(e.attr("iconTextOffset"), s)
        align = e.extra["textAlignment"]
        text = g.text_display(e)
        text_w = self.builder.measurer.width(text, e.extra["textSize"], g.text_bold(e), s) if text else 0.0
        if e.extra.get("textMaxWidth") is None and not e.extra.get("textAutoWidth"):
            text_w = min(text_w, e.abs_size[0])
        # getIconModifiedTextOffset
        mod_x = 0.0
        if align == "left":
            mod_x = -ito[0] + icon_w
        elif align == "center":
            mod_x = (icon_w - ito[0]) * 0.5
        self.out.append(self.text_html(e, rect, extra_x=mod_x * s.width))
        # icon position: text position + text offset + icon offset (getIconOffset)
        x = e.abs_pos[0]
        if align == "center":
            x += e.abs_size[0] * 0.5
        elif align == "right":
            x += e.abs_size[0]
        size = e.extra["textSize"]
        line_h = size if text else 0.0
        va = e.extra["textVerticalAlignment"]
        if va == "top":
            y = e.abs_pos[1] + e.abs_size[1] - line_h
        elif va == "middle":
            y = e.abs_pos[1] + e.abs_size[1] * 0.5 - (line_h if text else 0.0) * 0.5
        else:
            y = e.abs_pos[1]
        ox, oy = g.text_offset(e)
        ox += mod_x
        xo, yo = ito
        if align == "left":
            xo -= icon_w
        elif align == "center":
            xo -= text_w * 0.5 + icon_w
        elif align == "right":
            xo -= text_w + icon_w
        text_h = line_h
        if va == "top":
            yo -= text_h
        elif va == "middle":
            yo += (text_h - icon_h) * 0.5
        ix = (x + ox + xo) * s.width - rect[0]
        iy_bottom = y + oy + yo
        iw, ih = icon_w * s.width, icon_h * s.height
        iy = (1 - iy_bottom - icon_h) * s.height - rect[1]
        key = g.button_key(self.builder, e)
        if key is not None and not e.attr_bool("hideKeyboardGlyph", False):
            text_color = g.overlay_color(e.extra["icon"], state)
            bg = g.overlay_color(e.extra["iconBg"], state)
            self.out.append(self.key_glyph_html(key, ix, iy, iw, ih, text_color, bg))
        elif e.extra.get("icon") and e.extra["icon"]["slices"]:
            rotation = e.attr_num("iconRotation", 0.0) or 0.0
            # The game turns overlays counter-clockwise (setOverlayRotation, maths convention);
            # CSS rotate() turns clockwise.
            extra = f"transform:rotate({-rotation:.0f}deg)" if rotation else ""
            self.out.append(self.overlay_html(e.extra["icon"], state, ix, iy, iw, ih, extra))

    def page(self, title: str) -> str:
        s = self.screen
        background = self.scenario.get("background", "#000")
        body = "".join(self.out)
        return PAGE.format(title=html.escape(title), w=s.width, h=s.height, bg=background,
                           font=FONT_STACK, body=body,
                           scale=f"{self.screen.ui_scale:.4f}")


def norm_xy(text, screen):
    values = g.norm_values(text, screen, [0.0, 0.0], 2) if text else [0.0, 0.0]
    return values[0], values[1]


PAGE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;700&display=swap" rel="stylesheet">
<style>
:root {{ color-scheme: dark; }}
html, body {{ margin: 0; background: #111; }}
#screen {{ position: relative; width: {w}px; height: {h}px; overflow: hidden; background: {bg};
  font-family: {font}; }}
.el {{ position: absolute; box-sizing: border-box; }}
.o {{ position: absolute; background-size: 100% 100%; background-repeat: no-repeat; pointer-events: none; }}
.o {{ z-index: 1; }}
/* GIANTS draws text after the overlays of its layer, so text sits above every bitmap */
.tl {{ position: absolute; white-space: pre; line-height: 1; pointer-events: none; z-index: 2; }}
.layer {{ z-index: 3; isolation: isolate; }}
.kg {{ position: absolute; display: flex; align-items: center; justify-content: center;
  line-height: 1; font-weight: 700; white-space: pre; pointer-events: none; z-index: 2; }}
.el.outline::after, .el.unknown::after, .el:hover::after {{ content: ""; position: absolute; inset: 0;
  z-index: 4; pointer-events: none; }}
.el.outline::after {{ outline: 1px solid rgba(0, 200, 255, .45); outline-offset: -1px; }}
.el.unknown::after {{ outline: 2px dashed #ff00d4; outline-offset: -2px; }}
.el:hover::after {{ outline: 1px solid #ffd400; outline-offset: -1px; }}
</style>
</head>
<body>
<div id="screen" data-ui-scale="{scale}">{body}</div>
<script>
// Put each text line's baseline exactly where the engine draws it (data-b, element-relative).
function placeBaselines() {{
  for (const line of document.querySelectorAll('.tl')) {{
    const marker = document.createElement('span');
    marker.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    line.appendChild(marker);
    const offset = marker.offsetTop;
    marker.remove();
    line.style.top = (parseFloat(line.dataset.b) - offset) + 'px';
  }}
}}
(document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve()).then(placeBaselines);
</script>
</body>
</html>
"""


# ------------------------------------------------------------------ main

def screenshot(html_path: Path, png_path: Path, width: int, height: int) -> bool:
    candidates = [
        shutil.which("msedge"), shutil.which("chrome"),
        "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
        "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
        "C:/Program Files/Google/Chrome/Application/chrome.exe",
    ]
    browser = next((c for c in candidates if c and Path(c).exists()), None)
    if browser is None:
        print("no Edge/Chrome found for --screenshot", file=sys.stderr)
        return False
    started = time.time() - 1
    if png_path.exists():
        png_path.unlink()
    subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", f"--window-size={width},{height}",
                    "--virtual-time-budget=4000", f"--screenshot={png_path}",
                    html_path.resolve().as_uri()], check=False, capture_output=True, timeout=120)
    # msedge.exe hands over to a running broker and may return before the file exists
    deadline = time.time() + 60
    while time.time() < deadline:
        if png_path.exists() and png_path.stat().st_mtime >= started:
            time.sleep(0.5)
            return True
        time.sleep(0.5)
    return False


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scenario", type=Path)
    parser.add_argument("--out", type=Path, help="HTML path (default outputs/gui-lab/<name>.html)")
    parser.add_argument("--screenshot", action="store_true", help="also save a PNG via headless Edge/Chrome")
    parser.add_argument("--dump", action="store_true", help="print every visible element with its pixel rect")
    args = parser.parse_args(argv)

    scenario = json.loads(args.scenario.read_text(encoding="utf-8"))
    name = scenario.get("name") or args.scenario.stem
    root, builder, reference, missing = build(scenario, args.scenario.parent)

    atlases = {}
    for prefix, rel in BASE_TEXTURE_CONFIGS.items():
        path = reference / rel
        if path.exists():
            atlases[prefix] = Atlas(prefix, path)
    for spec in scenario.get("textureConfigs", []):
        atlases[spec["prefix"]] = Atlas(spec["prefix"], resolve_path(spec["xml"], reference))

    html_path = args.out or OUTPUT / f"{name}.html"
    html_path.parent.mkdir(parents=True, exist_ok=True)
    writer = HtmlWriter(scenario, builder, SliceCache(atlases, html_path.parent), root)
    s = builder.screen
    writer.element(root, (0.0, 0.0, s.width, s.height))
    html_path.write_text(writer.page(scenario.get("title", name)), encoding="utf-8")
    print(f"wrote {html_path.relative_to(ROOT) if html_path.is_relative_to(ROOT) else html_path}")
    for key in missing:
        print(f"warning: override/list target '{key}' not found", file=sys.stderr)
    if builder.unknown_types:
        print("unknown element types (dashed outline): " + ", ".join(sorted(builder.unknown_types)))
    if args.dump:
        for e in root.iter():
            if e.is_visible_rec():
                x, y, w, h = e.rect_px()
                print(f"{x:7.1f} {y:7.1f} {w:7.1f} {h:7.1f}  {e.label}")
    if args.screenshot:
        png = html_path.with_suffix(".png")
        if screenshot(html_path, png, s.width, s.height):
            print(f"wrote {png.relative_to(ROOT) if png.is_relative_to(ROOT) else png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
