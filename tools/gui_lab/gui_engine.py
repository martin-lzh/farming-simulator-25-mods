"""Offline model of the GIANTS Engine GUI loader and layout (Farming Simulator 25).

Standard library only, so tools/tests can import it without the lab's dependencies.
It mirrors these game scripts (1.25.0.0): Gui.loadProfileSet/loadGuiRec, GuiProfile,
GuiUtils.getNormalizedValue(s), GuiElement (size strings, anchors, pivot, anchor deltas),
BoxLayoutElement (updateLayoutCells/applyCellPositions), SmoothListElement
(buildSectionInfo/updateCellPosition), TextElement (alignment and baseline) and the
overlay state colours. Positions are kept in the engine's normalised, bottom-up screen
space and converted to top-down pixels only for output.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import copy
import re
import xml.etree.ElementTree as ET

REFERENCE_WIDTH = 1920
REFERENCE_HEIGHT = 1080

STATES = ("", "Focused", "Pressed", "Selected", "Highlighted", "Disabled")


# --------------------------------------------------------------------------- XML

def parse_xml(path_or_text: str, is_text: bool = False) -> ET.Element:
    """Parse GIANTS XML; tolerates a UTF-8 BOM."""
    if is_text:
        return ET.fromstring(path_or_text.lstrip("\ufeff"))
    with open(path_or_text, "rb") as handle:
        data = handle.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return ET.fromstring(data)


def child_by_tag(node: ET.Element, tag: str) -> ET.Element | None:
    for child in node:
        if isinstance(child.tag, str) and child.tag.lower() == tag.lower():
            return child
    return None


# ------------------------------------------------------------------ profiles

class Profile:
    """GuiProfile: trait values first, then own values; missing keys go to `extends`."""

    def __init__(self, store: "ProfileStore", name: str, parent: str | None, values: dict,
                 is_variant: bool = False):
        self.store = store
        self.name = name
        self.parent = parent
        self.values = values
        self.is_variant = is_variant

    def get(self, key: str, default=None):
        seen = set()
        profile = self
        while profile is not None and profile.name not in seen:
            seen.add(profile.name)
            value = profile.values.get(key)
            if value is not None and value != "nil":
                return value
            if profile.parent is None:
                break
            profile = (self.store.profiles.get(profile.parent) if profile.is_variant
                       else self.store.profiles.get(profile.parent))
        return default

    def get_bool(self, key: str, default=None):
        value = self.get(key)
        if value is None:
            return default
        return value.lower() == "true"


class ProfileStore:
    BASE = "baseReference"

    def __init__(self):
        self.presets: dict[str, str] = {}
        self.traits: dict[str, dict] = {}
        self.profiles: dict[str, Profile] = {}
        self.warnings: list[str] = []

    # Gui:loadPresets
    def load_presets(self, node: ET.Element) -> None:
        for preset in node:
            if not isinstance(preset.tag, str) or preset.tag != "Preset":
                continue
            name, value = preset.get("name"), preset.get("value")
            if name is None or value is None:
                continue
            if value.startswith("$preset_"):
                value = self.presets.get(value[len("$preset_"):], value)
            self.presets[name] = value

    def _values(self, node: ET.Element) -> dict:
        values = {}
        for child in node:
            if not isinstance(child.tag, str):
                continue
            if child.tag == "Variant":
                break
            value = child.get("value")
            if value is None:
                break
            if value.startswith("$preset_"):
                key = value[len("$preset_"):]
                if key in self.presets:
                    value = self.presets[key]
                else:
                    self.warnings.append(f"preset {key} not defined")
            values[child.tag] = value
        return values

    def load_traits(self, node: ET.Element) -> None:
        for trait in node:
            if isinstance(trait.tag, str) and trait.tag == "Trait" and trait.get("name"):
                self.traits[trait.get("name")] = self._values(trait)

    def _profile_from(self, node: ET.Element, is_variant: bool = False) -> Profile:
        values = {}
        for trait_name in (node.get("with") or "").split():
            trait = self.traits.get(trait_name)
            if trait is None:
                self.warnings.append(f"trait {trait_name} not found for {node.get('name')}")
                continue
            values.update(trait)
        values.update(self._values(node))
        return Profile(self, node.get("name"), node.get("extends"), values, is_variant)

    # Gui:loadProfileSet (first definition wins, like the game outside of reloads)
    def load_profile_set(self, node: ET.Element, override: bool = False) -> None:
        for child in node:
            if not isinstance(child.tag, str) or child.tag != "Profile" or not child.get("name"):
                continue
            profile = self._profile_from(child)
            if profile.name in self.profiles and not override:
                self.warnings.append(f"profile {profile.name} already defined")
                continue
            self.profiles[profile.name] = profile
            for variant in child:
                if isinstance(variant.tag, str) and variant.tag == "Variant" and variant.get("name"):
                    vp = self._profile_from(variant, is_variant=True)
                    vp.parent = vp.parent or profile.name
                    vp.name = f"{variant.get('name')}_{profile.name}"
                    self.profiles.setdefault(vp.name, vp)

    # Gui:loadProfiles
    def load_profiles_file(self, root: ET.Element) -> None:
        presets = child_by_tag(root, "Presets")
        if presets is not None:
            self.load_presets(presets)
        traits = child_by_tag(root, "Traits")
        if traits is not None:
            self.load_traits(traits)
        self.load_profile_set(root)
        for child in root:
            if isinstance(child.tag, str) and child.tag == "Category":
                self.load_profile_set(child)

    def get_profile(self, name: str | None) -> Profile:
        if name and name in self.profiles:
            return self.profiles[name]
        if name:
            self.warnings.append(f"profile {name} not found, using {self.BASE}")
        return self.profiles.get(self.BASE) or Profile(self, self.BASE, None, {})


# ------------------------------------------------------------- normalisation

@dataclass
class Screen:
    width: int = 1920
    height: int = 1080

    @property
    def aspect_scale(self) -> tuple[float, float]:
        """main.lua updateAspectRatio (safe frame ratio 1)."""
        reference = REFERENCE_WIDTH / REFERENCE_HEIGHT
        aspect = self.width / self.height
        if reference < aspect:
            return reference / aspect, 1.0
        return 1.0, aspect / reference

    @property
    def ui_scale(self) -> float:
        """Screen pixels per reference pixel."""
        sx, sy = self.aspect_scale
        return self.width * sx / REFERENCE_WIDTH


def norm_value(text, is_x: bool, screen: Screen, default=None):
    """GuiUtils.getNormalizedValue: px -> reference pixels scaled by aspect, dp -> screen pixels."""
    if text is None:
        return default
    if isinstance(text, (int, float)):
        return float(text)
    text = text.strip()
    scale_x, scale_y = screen.aspect_scale
    try:
        if "px" in text:
            value = float(text.replace("px", ""))
            return value / (REFERENCE_WIDTH if is_x else REFERENCE_HEIGHT) * (scale_x if is_x else scale_y)
        if "dp" in text:
            value = float(text.replace("dp", ""))
            return value / (screen.width if is_x else screen.height)
        return float(text)
    except ValueError:
        return default


def norm_values(text, screen: Screen, default=None, count: int | None = None):
    """GuiUtils.getNormalizedScreenValues; odd positions are X values. Missing entries
    fall back to the default (or the repeated pattern when no default exists)."""
    if text is None:
        return copy.copy(default)
    parts = text.split()
    values = []
    for i, part in enumerate(parts):
        fallback = default[i] if isinstance(default, list) and i < len(default) else None
        values.append(norm_value(part, i % 2 == 0, screen, fallback))
    target = count or (len(default) if isinstance(default, list) else len(values))
    while len(values) < target:
        i = len(values)
        if isinstance(default, list) and i < len(default) and default[i] is not None:
            values.append(default[i])
        else:
            values.append(values[i % max(len(parts), 1)] if parts else 0.0)
    return values


def vector(text, count: int, default=None):
    if text is None:
        return copy.copy(default)
    try:
        parts = [float(p) for p in text.split()]
    except ValueError:
        return copy.copy(default)
    if len(parts) < count:
        return copy.copy(default)
    return parts[:count]


def color_array(text, default=None):
    """getColorGradientArray: 4 values, or 16 for corner colours (BL, TL, BR, TR)."""
    if text is None:
        return copy.copy(default)
    try:
        parts = [float(p) for p in text.split()]
    except ValueError:
        return copy.copy(default)
    if len(parts) not in (4, 16):
        return copy.copy(default)
    return parts


# ------------------------------------------------------------------ elements

KNOWN_TYPES = {
    "GUIELEMENT", "BITMAP", "THREEPARTBITMAP", "ROUNDCORNER", "TEXT", "BUTTON", "BOXLAYOUT",
    "SCROLLINGLAYOUT", "SMOOTHLIST", "LISTITEM", "MULTITEXTOPTION", "OPTIONTOGGLE",
    "BINARYOPTION", "SLIDER", "INPUTGLYPH", "FRAMEREFERENCE", "PAGING", "INGAMEMAP",
}
BITMAP_TYPES = {"BITMAP", "THREEPARTBITMAP", "BOXLAYOUT", "SCROLLINGLAYOUT", "LISTITEM",
                "BUTTON", "SLIDER", "INGAMEMAP", "TERRAINLAYER"}
TEXT_TYPES = {"TEXT", "BUTTON"}
LAYOUT_TYPES = {"BOXLAYOUT", "SCROLLINGLAYOUT"}


@dataclass
class Element:
    type: str
    xml: dict
    profile: Profile
    screen: Screen
    parent: "Element | None" = None
    children: list = field(default_factory=list)
    id: str | None = None
    name: str | None = None
    profile_name: str = ""
    source: str = ""
    # GuiElement state
    position: list = field(default_factory=lambda: [0.0, 0.0])
    size: list = field(default_factory=lambda: [1.0, 1.0])
    anchors: list = field(default_factory=lambda: [0.0, 1.0, 0.0, 1.0])
    pivot: list = field(default_factory=lambda: [0.0, 0.0])
    margin: list = field(default_factory=lambda: [0.0, 0.0, 0.0, 0.0])
    abs_offset: list | None = None
    anchor_deltas: list = field(default_factory=list)
    abs_pos: list = field(default_factory=lambda: [0.0, 0.0])
    abs_size: list = field(default_factory=lambda: [1.0, 1.0])
    visible: bool = True
    selected: bool = False
    focused: bool = False
    highlighted: bool = False
    disabled: bool = False
    clipping: bool = False
    update_children_state: bool = True
    absolute_override: dict | None = None
    extra: dict = field(default_factory=dict)

    # -- attribute access: XML attribute wins over profile value (loadFromXML after loadProfile)
    def attr(self, key: str, default=None):
        if key in self.xml:
            return self.xml[key]
        return self.profile.get(key, default)

    def attr_bool(self, key: str, default=None):
        value = self.attr(key)
        if value is None:
            return default
        return str(value).lower() == "true"

    def attr_num(self, key: str, default=None):
        value = self.attr(key)
        try:
            return float(value) if value is not None else default
        except ValueError:
            return default

    @property
    def upper(self) -> str:
        return self.type.upper()

    @property
    def label(self) -> str:
        bits = [self.type]
        if self.profile_name:
            bits.append(f"profile={self.profile_name}")
        if self.id:
            bits.append(f"id={self.id}")
        if self.name:
            bits.append(f"name={self.name}")
        if self.source:
            bits.append(f"src={self.source}")
        return " ".join(bits)

    def iter(self):
        yield self
        for child in self.children:
            yield from child.iter()

    def find(self, key: str) -> "Element | None":
        for element in self.iter():
            if element.id == key:
                return element
        for element in self.iter():
            if element.name == key:
                return element
        return None

    def find_all(self, key: str) -> list:
        return [e for e in self.iter() if e.id == key or e.name == key]

    def is_visible_rec(self) -> bool:
        element = self
        while element is not None:
            if not element.visible:
                return False
            element = element.parent
        return True

    # -- GuiElement:getOverlayState
    @property
    def state(self) -> str:
        if self.disabled:
            return "Disabled"
        if self.selected:
            return "Selected"
        if self.focused:
            return "Focused"
        if self.highlighted:
            return "Highlighted"
        return ""

    def set_selected(self, selected: bool) -> None:
        if self.upper == "LISTITEM" and (self.attr_bool("hideSelection", False)
                                         or not self.attr_bool("allowSelected", True)):
            selected = False
        self.selected = selected
        if self.update_children_state:
            for child in self.children:
                child.set_selected(selected)

    def set_focused(self, focused: bool) -> None:
        self.focused = focused
        if self.update_children_state:
            for child in self.children:
                child.set_focused(focused)

    # ----------------------------------------------------------- geometry
    def parent_original_borders(self):
        if self.parent is None:
            return 0.0, 0.0, 1.0, 1.0
        p = self.parent
        return p.position[0], p.position[1], p.position[0] + p.size[0], p.position[1] + p.size[1]

    def parent_borders(self):
        if self.parent is None:
            return 0.0, 0.0, 1.0, 1.0
        p = self.parent
        return p.abs_pos[0], p.abs_pos[1], p.abs_pos[0] + p.abs_size[0], p.abs_pos[1] + p.abs_size[1]

    def resolve_size(self) -> None:
        """GuiElement:resolveSizeString."""
        def resolve(text: str, index: int) -> bool:
            if "%" in text:
                try:
                    percent = float(text.replace("%", "")) / 100
                except ValueError:
                    return False
                offset = self.abs_offset[index] if self.abs_offset and len(self.abs_offset) > index else 0.0
                offset = offset or 0.0
                if self.parent is None:
                    self.size[index] = 1 - offset
                else:
                    self.size[index] = percent * self.parent.size[index] - offset
            else:
                value = norm_value(text, index == 0, self.screen)
                if value is not None:
                    self.size[index] = value
            return True

        for i, part in enumerate(self.extra["sizeStr"].split()[:2]):
            if not resolve(part, i % 2):
                break
        if self.extra.get("widthStr") is not None:
            resolve(self.extra["widthStr"], 0)
        if self.extra.get("heightStr") is not None:
            resolve(self.extra["heightStr"], 1)
        self.update_anchor_deltas()

    def update_anchor_deltas(self) -> None:
        """GuiElement:updateAnchorDeltas (relative to the parent's original borders)."""
        min_x, min_y, max_x, max_y = self.parent_original_borders()
        pw, ph = max_x - min_x, max_y - min_y
        pos_x = min_x + self.pivot[0] * (pw - self.size[0]) + self.position[0]
        pos_y = min_y + self.pivot[1] * (ph - self.size[1]) + self.position[1]
        self.anchor_deltas = [
            pos_x - (min_x + pw * self.anchors[0]),
            pos_y - (min_y + ph * self.anchors[2]),
            pos_x + self.size[0] - (min_x + pw * self.anchors[1]),
            pos_y + self.size[1] - (min_y + ph * self.anchors[3]),
        ]

    def update_absolute_position(self) -> None:
        """GuiElement:updateAbsolutePosition, plus BoxLayout:applyCellPositions."""
        if not self.anchor_deltas:
            self.update_anchor_deltas()
        min_x, min_y, max_x, max_y = self.parent_borders()
        ax1 = min_x + (max_x - min_x) * self.anchors[0]
        ax2 = min_x + (max_x - min_x) * self.anchors[1]
        ay1 = min_y + (max_y - min_y) * self.anchors[2]
        ay2 = min_y + (max_y - min_y) * self.anchors[3]
        self.abs_pos = [ax1 + self.anchor_deltas[0], ay1 + self.anchor_deltas[1]]
        self.abs_size = [ax2 + self.anchor_deltas[2] - self.abs_pos[0],
                         ay2 + self.anchor_deltas[3] - self.abs_pos[1]]
        if self.absolute_override:
            self._apply_absolute_override()
        for child in self.children:
            child.update_absolute_position()
        if self.upper in LAYOUT_TYPES and self.extra.get("cells") is not None:
            apply_cell_positions(self)

    def _apply_absolute_override(self) -> None:
        o = self.absolute_override
        s = self.screen
        if "x" in o:
            self.abs_pos[0] = o["x"] / s.width
        if "width" in o:
            self.abs_size[0] = o["width"] / s.width
        if "height" in o:
            self.abs_size[1] = o["height"] / s.height
        if "y" in o:  # top-down pixel of the element's top edge
            self.abs_pos[1] = 1 - o["y"] / s.height - self.abs_size[1]

    def set_position(self, x: float, y: float) -> None:
        self.position = [x, y]
        self.update_anchor_deltas()
        self.update_absolute_position()

    def set_size(self, w: float | None, h: float | None) -> None:
        if w is not None:
            self.size[0] = w
        if h is not None:
            self.size[1] = h
        self.update_anchor_deltas()
        self.update_absolute_position()

    # top-down screen pixels
    def rect_px(self):
        s = self.screen
        x = self.abs_pos[0] * s.width
        w = self.abs_size[0] * s.width
        h = self.abs_size[1] * s.height
        y = (1 - self.abs_pos[1] - self.abs_size[1]) * s.height
        return x, y, w, h


# ---------------------------------------------------------------- loading

class TextMeasurer:
    """Width of a single text line in normalised X units. Heuristic by default; the
    renderer can replace `width_px` with a real font measurement."""

    def width_px(self, text: str, size_px: float, bold: bool) -> float:
        width = 0.0
        for ch in text:
            if ord(ch) > 0x2E7F:
                width += 1.0
            elif ch == " ":
                width += 0.28
            elif ch.isupper() or ch.isdigit():
                width += 0.64
            else:
                width += 0.54
        return width * size_px * (1.04 if bold else 1.0)

    def width(self, text: str, text_size: float, bold: bool, screen: Screen) -> float:
        size_px = text_size * screen.height
        return self.width_px(text, size_px, bold) / screen.width


class GuiBuilder:
    def __init__(self, store: ProfileStore, screen: Screen, l10n: dict | None = None,
                 measurer: TextMeasurer | None = None, keys: dict | None = None):
        self.store = store
        self.screen = screen
        self.l10n = l10n or {}
        self.measurer = measurer or TextMeasurer()
        self.keys = keys or {}
        self.unknown_types: set[str] = set()

    # Gui:loadGui
    def load_gui(self, root_node: ET.Element, source: str = "") -> Element:
        profiles = child_by_tag(root_node, "GUIProfiles")
        if profiles is not None:
            self.store.load_profile_set(profiles)
        root = self.create(root_node, None, source, force_type="GuiElement")
        self.load_rec(root_node, root, source)
        return root

    def load_rec(self, node: ET.Element, parent: Element, source: str) -> None:
        for child in node:
            if not isinstance(child.tag, str) or child.tag.upper() == "GUIPROFILES":
                continue
            element = self.create(child, parent, source)
            self.load_rec(child, element, source)
            self.after_children(element)

    def create(self, node: ET.Element, parent: Element | None, source: str,
               force_type: str | None = None) -> Element:
        type_name = force_type or node.tag
        profile_name = node.get("profile") or ""
        profile = self.store.get_profile(profile_name) if profile_name else \
            Profile(self.store, "", None, {})
        element = Element(type_name, dict(node.attrib), profile, self.screen, parent=parent,
                          profile_name=profile_name, source=source)
        if element.upper not in KNOWN_TYPES and element.upper not in BITMAP_TYPES:
            self.unknown_types.add(type_name)
        if parent is not None:
            parent.children.append(element)
            if parent.upper in LAYOUT_TYPES:
                element.anchors = [0.0, 0.0, 0.0, 0.0]
                element.pivot = [0.0, 0.0]
        self.load_element(element)
        return element

    def text(self, value: str | None) -> str:
        if value is None:
            return ""
        def repl(match):
            key = match.group(1)
            return self.l10n.get(key, key)
        return re.sub(r"\$l10n_([A-Za-z0-9_]+)", repl, value)

    def load_element(self, e: Element) -> None:
        s = self.screen
        e.id = e.xml.get("id")
        e.name = e.xml.get("name") or e.profile.get("name")
        pivot = vector(e.attr("pivot"), 2)
        if pivot is not None:
            e.pivot = pivot
        e.position = norm_values(e.attr("position"), s, e.position, 2)
        e.extra["sizeStr"] = e.attr("size", "100% 100%")
        e.extra["widthStr"] = e.attr("width")
        e.extra["heightStr"] = e.attr("height")
        offset = e.attr("absoluteSizeOffset")
        if offset is not None:
            e.abs_offset = norm_values(offset, s, None)
        e.margin = norm_values(e.attr("margin"), s, e.margin, 4)
        anchors = vector(e.attr("anchors"), 4)
        if anchors is not None:
            e.anchors = anchors
        e.visible = e.attr_bool("visible", True)
        e.disabled = e.attr_bool("disabled", False)
        e.clipping = e.attr_bool("clipping", e.upper in ("SMOOTHLIST", "SCROLLINGLAYOUT"))
        e.update_children_state = e.attr_bool("updateChildrenState", e.upper != "SMOOTHLIST")
        e.extra["layoutIgnore"] = e.attr_bool("layoutIgnore", False)
        e.extra["newLayer"] = e.attr_bool("newLayer", False)
        upper = e.upper
        if upper in BITMAP_TYPES or upper in ("THREEPARTBITMAP",):
            e.extra["image"] = load_overlay(e, "image")
        if upper == "THREEPARTBITMAP":
            e.extra["startImage"] = load_overlay(e, "startImage")
            e.extra["endImage"] = load_overlay(e, "endImage")
            e.extra["startSize"] = norm_values(e.attr("startImageSize"), s, [0.0, 0.0], 2)
            e.extra["endSize"] = norm_values(e.attr("endImageSize"), s, [0.0, 0.0], 2)
            e.extra["isHorizontal"] = e.attr_bool("isHorizontal", True)
            # ThreePartBitmapElement:loadFromXML ends with setImageColor(nil, <image colour>),
            # which copies the image's normal colour onto the start and end parts
            normal = e.extra["image"]["colors"].get("", [1.0, 1.0, 1.0, 1.0])
            e.extra["startImage"]["colors"][""] = list(normal)
            e.extra["endImage"]["colors"][""] = list(normal)
        if upper == "ROUNDCORNER":
            colors = {}
            for state in STATES:
                c = color_array(e.attr(f"color{state}"))
                if c is not None:
                    colors[state] = c
            colors.setdefault("", [1, 1, 1, 1])
            e.extra["colors"] = colors
            e.extra["cornerSize"] = e.attr_num("cornerSize", 1.0)
        if upper in TEXT_TYPES:
            load_text(self, e)
        if upper == "BUTTON":
            e.extra["icon"] = load_overlay(e, "icon")
            e.extra["iconBg"] = load_overlay(e, "iconBg")
            e.extra["iconSize"] = norm_values(e.attr("iconSize"), s, None, 2) if e.attr("iconSize") else None
            e.extra["inputAction"] = e.attr("inputAction")
        if upper == "SLIDER":
            e.extra["slider"] = load_overlay(e, "sliderImage")
            e.extra["startImage"] = load_overlay(e, "startImage")
            e.extra["endImage"] = load_overlay(e, "endImage")
            e.extra["sliderSize"] = norm_values(e.attr("sliderSize"), s, [0.0, 0.0], 2)
            e.extra["startSize"] = norm_values(e.attr("startImageSize"), s, [0.0, 0.0], 2)
            e.extra["endSize"] = norm_values(e.attr("endImageSize"), s, [0.0, 0.0], 2)
            e.extra["isThreePartBitmap"] = e.attr_bool("isThreePartBitmap", False)
            e.extra["direction"] = e.attr("direction") or "y"
            e.extra["dataElementId"] = e.attr("dataElementId")
        if upper == "INPUTGLYPH":
            e.extra["glyphColor"] = color_array(e.attr("glyphColor"), [1.0, 1.0, 1.0, 1.0])
            e.extra["glyphBackgroundColor"] = color_array(e.attr("glyphBackgroundColor"))
            e.extra["isLeftAligned"] = e.attr_bool("isLeftAligned", False)
            e.extra["inputAction"] = e.attr("inputAction")
        if upper == "BOXLAYOUT" or upper == "SCROLLINGLAYOUT":
            load_box_layout(e)
        if upper == "SMOOTHLIST":
            e.extra["listItemSpacing"] = norm_value(e.attr("listItemSpacing"), False, s, 0.0) or 0.0
            e.extra["listSectionSpacing"] = norm_value(e.attr("listSectionSpacing"), False, s, 0.0) or 0.0
            e.extra["numLateralItems"] = int(e.attr_num("numLateralItems", 1))
            e.extra["listItemLateralSpacing"] = norm_value(e.attr("listItemLateralSpacing"), True, s, 0.0) or 0.0
            e.extra["sectionHeader"] = e.attr("listSectionHeader")
            alignment = (e.attr("listItemAlignment") or "start").lower()
            e.extra["alignment"] = {"end": 1.0, "middle": 0.5}.get(alignment, 0.0)
            e.extra["selectedWithoutFocus"] = e.attr_bool("selectedWithoutFocus", True)
        e.resolve_size()

    def after_children(self, e: Element) -> None:
        upper = e.upper
        if upper == "SMOOTHLIST":
            # SmoothListElement:buildCellDatabase unlinks every child; templates kept by name
            templates = {}
            for i, child in enumerate(e.children, start=1):
                if child.upper == "LISTITEM":
                    templates[child.name or f"autoCell{i}"] = child
            e.extra["templates"] = templates
            e.children = []
        if upper in ("MULTITEXTOPTION", "OPTIONTOGGLE", "BINARYOPTION"):
            texts = e.xml.get("texts") or e.profile.get("texts")
            e.extra["texts"] = [self.text(t) for t in texts.split("|") if t] if texts else []
            e.extra["state"] = 1
            self.add_default_option_elements(e)

    def create_from_profile(self, type_name: str, profile_name: str | None, parent: Element,
                            name: str) -> Element:
        """Element created in Lua with applyProfile (no XML node)."""
        profile = self.store.get_profile(profile_name) if profile_name else \
            Profile(self.store, "", None, {})
        element = Element(type_name, {}, profile, self.screen, parent=parent,
                          profile_name=profile_name or "", source=parent.source)
        parent.children.append(element)
        self.load_element(element)
        element.name = name
        return element

    def add_default_option_elements(self, e: Element) -> None:
        """MultiTextOptionElement:addDefaultElements + setElementsByName."""
        if e.attr_bool("autoAddDefaultElements", False):
            names = {c.name for c in e.iter() if c is not e}
            if "background" not in names:
                for key, kind in (("defaultProfileBgRound", "RoundCorner"),
                                  ("defaultProfileBgThreePart", "ThreePartBitmap"),
                                  ("defaultProfileBg", "Bitmap")):
                    value = e.attr(key)
                    if value is not None and (value != "" or kind == "Bitmap"):
                        bg = self.create_from_profile(kind, value, e, "background")
                        bg.size[0] = e.size[0]
                        bg.update_anchor_deltas()
                        break
            if "left" not in names:
                self.create_from_profile("Button", e.attr("defaultProfileButtonLeft"), e, "left")
            if "right" not in names:
                self.create_from_profile("Button", e.attr("defaultProfileButtonRight"), e, "right")
            if "text" not in names:
                self.create_from_profile("Text", e.attr("defaultProfileText"), e, "text")
        hide = e.attr_bool("hideLeftRightButtons", False)
        for child in e.children:
            if child.name in ("left", "right"):
                child.visible = not hide
        update_option_content(e)


def update_option_content(e: Element) -> None:
    """MultiTextOptionElement:updateContentElement."""
    texts = e.extra.get("texts") or []
    state = max(1, min(int(e.extra.get("state", 1)), max(len(texts), 1)))
    e.extra["state"] = state
    value = texts[state - 1] if texts else ""
    for child in e.children:
        if child.name == "text" and "text" in child.extra:
            child.extra["text"] = value
    if e.attr_bool("disableButtonsOnSingleText", False):
        set_disabled(e, len(texts) <= 1)
    if e.attr_bool("hideButtonOnLimitReached", False) and not e.attr_bool("wrap", True):
        for child in e.children:
            if child.name == "left":
                child.visible = state != 1
            if child.name == "right":
                child.visible = state != len(texts)


def set_disabled(e: Element, disabled: bool) -> None:
    e.disabled = disabled
    if e.update_children_state:
        for child in e.children:
            set_disabled(child, disabled)


def load_overlay(e: Element, name: str) -> dict:
    """GuiOverlay.loadOverlay: slices, colours and UVs per state."""
    overlay = {"filename": e.attr(f"{name}Filename"), "slices": {}, "colors": {}, "uvs": {}}
    for state in STATES:
        slice_id = e.attr(f"{name}{state}SliceId")
        if slice_id is not None and slice_id != "noSlice":
            overlay["slices"][state] = slice_id
            overlay["invertX"] = e.attr_bool(f"{name}{state}InvertX", False)
            overlay["rotation"] = e.attr_num(f"{name}{state}UVRotation")
        elif e.attr(f"{name}{state}UVs") is not None:
            overlay["uvs"][state] = e.attr(f"{name}{state}UVs")
        color = color_array(e.attr(f"{name}{state}Color"))
        if color is not None:
            overlay["colors"][state] = color
    overlay["imageSize"] = vector(e.attr("imageSize"), 2, [2048, 2048])
    return overlay


def overlay_color(overlay: dict, state: str):
    colors = overlay["colors"]
    color = colors.get(state)
    if color is None and state == "Pressed":
        color = colors.get("Focused")
    return color or colors.get("") or [1.0, 1.0, 1.0, 1.0]


def overlay_slice(overlay: dict, state: str):
    slices = overlay["slices"]
    if state in slices:
        return slices[state]
    if state == "Pressed" and "Focused" in slices:
        return slices["Focused"]
    return slices.get("")


def load_text(builder: GuiBuilder, e: Element) -> None:
    s = builder.screen
    colors = {"": color_array(e.attr("textColor"), [1.0, 1.0, 1.0, 1.0])}
    for state in ("Selected", "Focused", "Highlighted", "Disabled", "FocusedSelected",
                  "HighlightedSelected"):
        c = color_array(e.attr(f"text{state}Color"))
        if c is not None:
            colors[state] = c
    e.extra["textColors"] = colors
    e.extra["textOffset"] = norm_values(e.attr("textOffset"), s, [0.0, 0.0], 2)
    for state in ("Focused", "Selected", "Highlighted", "Pressed"):
        value = e.attr(f"text{state}Offset")
        e.extra[f"text{state}Offset"] = norm_values(value, s, [0.0, 0.0], 2) if value else None
    e.extra["textSize"] = norm_value(e.attr("textSize"), False, s, 0.03)
    e.extra["text2Size"] = norm_value(e.attr("text2Size"), False, s, 0.0)
    e.extra["text2Color"] = color_array(e.attr("text2Color"), [1.0, 1.0, 1.0, 1.0])
    e.extra["text2Offset"] = norm_values(e.attr("text2Offset"), s, [0.0, 0.0], 2)
    e.extra["textBold"] = e.attr_bool("textBold", False)
    e.extra["textSelectedBold"] = e.attr_bool("textSelectedBold", False)
    e.extra["textUpperCase"] = e.attr_bool("textUpperCase", False)
    e.extra["textMaxWidth"] = norm_value(e.attr("textMaxWidth"), True, s)
    e.extra["textMinWidth"] = norm_value(e.attr("textMinWidth"), True, s, 0.0)
    e.extra["textMaxNumLines"] = int(e.attr_num("textMaxNumLines", 1))
    e.extra["textAutoWidth"] = e.attr_bool("textAutoWidth", False)
    e.extra["textAutoHeight"] = e.attr_bool("textAutoHeight", False)
    e.extra["textLineHeightScale"] = e.attr_num("textLineHeightScale", 1.0)
    e.extra["textAlignment"] = (e.attr("textAlignment") or "center").lower()
    e.extra["textVerticalAlignment"] = (e.attr("textVerticalAlignment") or "middle").lower()
    e.extra["textLayoutMode"] = (e.attr("textLayoutMode") or "truncate").lower()
    e.extra["text"] = builder.text(e.xml.get("text") or e.profile.get("text"))


def load_box_layout(e: Element) -> None:
    s = e.screen
    ax = (e.attr("alignmentX") or "left").lower()
    ay = (e.attr("alignmentY") or "top").lower()
    flow = e.attr("flowDirection") or "horizontal"
    e.extra["alignment"] = [{"right": 1.0, "center": 0.5}.get(ax, 0.0),
                            {"bottom": 0.0, "middle": 0.5}.get(ay, 1.0)]
    fx = e.attr("fillDirectionX")
    fy = e.attr("fillDirectionY")
    e.extra["fill"] = [-1 if fx == "rightToLeft" else 1, 1 if fy == "bottomToTop" else -1]
    e.extra["flow"] = flow
    e.extra["numFlows"] = int(e.attr_num("numFlows", 1))
    is_x = flow == "horizontal"
    e.extra["spacing"] = norm_value(e.attr("elementSpacing"), is_x, s, 0.0) or 0.0
    e.extra["lateralFlowSize"] = norm_value(e.attr("lateralFlowSize"), not is_x, s, 0.0) or 0.0
    e.extra["fitFlowToElements"] = e.attr_bool("fitFlowToElements", e.extra["lateralFlowSize"] == 0)
    e.extra["useFullVisibility"] = e.attr_bool("useFullVisibility", True)
    e.extra["autoValidateLayout"] = e.attr_bool("autoValidateLayout", False)


# ---------------------------------------------------------------- box layout

LAYOUT_TOLERANCE = 0.1


def update_layout_cells(box: Element) -> None:
    """BoxLayoutElement:updateLayoutCells."""
    s = box.screen
    flow = box.extra["flow"]
    if flow not in ("vertical", "horizontal"):
        box.extra["cells"] = None
        return
    size_i = 1 if flow == "vertical" else 0
    lat_i = 0 if flow == "vertical" else 1
    # margin indices: left 0, top 1, right 2, bottom 3
    m_lower, m_upper = (1, 3) if flow == "vertical" else (0, 2)
    l_lower, l_upper = (0, 2) if flow == "vertical" else (1, 3)
    tol_x, tol_y = LAYOUT_TOLERANCE / s.width, LAYOUT_TOLERANCE / s.height
    flow_tol = tol_y if flow == "vertical" else tol_x
    spacing = box.extra["spacing"]
    cells = [[]]
    flow_sizes, lateral_sizes = {}, {}
    current, max_lateral, current_flow = 0.0, 0.0, 1
    for child in box.children:
        visible = child.is_visible_rec() if box.extra["useFullVisibility"] else child.visible
        if child.extra.get("layoutIgnore") or not visible:
            continue
        flow_size = child.abs_size[size_i] + child.margin[m_lower] + child.margin[m_upper]
        lateral = child.abs_size[lat_i] + child.margin[l_lower] + child.margin[l_upper]
        num_flows = box.extra["numFlows"]
        if (current + flow_size + spacing - flow_tol > box.abs_size[size_i]
                and (num_flows == 0 or current_flow < num_flows)):
            current_flow += 1
            current, max_lateral = 0.0, 0.0
            cells.append([])
        cells[current_flow - 1].append(child)
        current += flow_size
        flow_sizes[current_flow] = current
        current += spacing
        lat = lateral if box.extra["fitFlowToElements"] else box.extra["lateralFlowSize"]
        max_lateral = max(max_lateral, lat)
        lateral_sizes[current_flow] = max_lateral
    box.extra["cells"] = cells
    box.extra["flowSizes"] = flow_sizes
    box.extra["lateralSizes"] = lateral_sizes
    box.extra["totalLateral"] = sum(lateral_sizes.values())
    box.extra["maxFlowSize"] = max(flow_sizes.values()) if flow_sizes else 0.0


def apply_cell_positions(box: Element) -> None:
    """BoxLayoutElement:applyCellPositions."""
    cells = box.extra.get("cells")
    if not cells:
        return
    flow_dir = 1 if box.extra["flow"] == "vertical" else 0
    lat_dir = 0 if flow_dir == 1 else 1
    align = box.extra["alignment"]
    spacing = box.extra["spacing"]
    flow_offset = align[lat_dir] * (box.abs_size[lat_dir] - box.extra["totalLateral"])
    indices = list(range(len(cells)))
    if box.extra["fill"][lat_dir] == -1:
        indices.reverse()
    for fi in indices:
        flow = cells[fi]
        if not flow:
            break
        order = list(range(len(flow)))
        if box.extra["fill"][flow_dir] == -1:
            order.reverse()
        cell_offset = align[flow_dir] * (box.abs_size[flow_dir] - box.extra["flowSizes"][fi + 1])
        for ci in order:
            cell = flow[ci]
            cell.anchors = [0.0, 0.0, 0.0, 0.0]
            cell.pivot = [0.0, 0.0]
            lateral_offset = flow_offset
            if box.extra["fitFlowToElements"]:
                lat_size = cell.abs_size[lat_dir] + cell.margin[lat_dir] + cell.margin[lat_dir + 2]
                lateral_offset = flow_offset + align[lat_dir] * (box.extra["lateralSizes"][fi + 1] - lat_size)
            pos = [0.0, 0.0]
            pos[flow_dir] = cell_offset
            pos[lat_dir] = lateral_offset
            cell.set_position(pos[0] + cell.margin[0], pos[1] + cell.margin[3])
            cell_offset += cell.abs_size[flow_dir] + spacing + cell.margin[flow_dir] + cell.margin[flow_dir + 2]
        flow_offset += box.extra["lateralSizes"][fi + 1]


def invalidate_layout(box: Element) -> None:
    update_layout_cells(box)
    apply_cell_positions(box)


# ----------------------------------------------------------------- text

def text_display(e: Element) -> str:
    text = e.extra.get("text") or ""
    if e.extra.get("textUpperCase"):
        text = text.upper()
    return text


def text_bold(e: Element) -> bool:
    return bool(e.extra.get("textBold") or (e.extra.get("textSelectedBold") and e.selected))


def text_color(e: Element):
    colors = e.extra["textColors"]
    state = e.state
    if e.selected and e.focused and "FocusedSelected" in colors:
        return colors["FocusedSelected"]
    if e.selected and e.highlighted and "HighlightedSelected" in colors:
        return colors["HighlightedSelected"]
    return colors.get(state) or colors[""]


def text_offset(e: Element):
    state = e.state
    value = e.extra.get(f"text{state}Offset") if state else None
    return value or e.extra["textOffset"]


KEY_GLYPH_TEXT_FACTOR = 0.55      # ButtonOverlay.textSizeFactor
KEY_GLYPH_PADDING_FACTOR = 12 / 25  # ButtonOverlay.leftRightPaddingHeightRatio


def key_glyph_width(builder: "GuiBuilder", key: str, height: float, screen: Screen) -> float:
    """ButtonOverlay:getButtonWidth in normalised X units for a glyph `height` (normalised Y)."""
    h_px = height * screen.height
    text_px = builder.measurer.width_px(key.upper(), h_px * KEY_GLYPH_TEXT_FACTOR, True)
    return (text_px + 2 * h_px * KEY_GLYPH_PADDING_FACTOR) / screen.width


def button_icon_size(builder: "GuiBuilder", e: Element):
    """ButtonElement:getIconSize; keyboard mode uses the key glyph size."""
    icon = e.extra.get("iconSize") or [0.0, 0.0]
    key = button_key(builder, e)
    if key is not None and not e.attr_bool("hideKeyboardGlyph", False):
        return key_glyph_width(builder, key, icon[1], e.screen), icon[1]
    return icon[0], icon[1]


def button_key(builder: "GuiBuilder", e: Element):
    if "glyphKey" in e.extra:
        return e.extra["glyphKey"]
    action = e.extra.get("inputAction")
    if action is None:
        return None
    return builder.keys.get(action)


def apply_text_auto_size(builder: GuiBuilder, e: Element) -> None:
    """TextElement:updateSize / ButtonElement:updateSize for auto width (single line)."""
    if e.upper == "INPUTGLYPH":
        # InputGlyphElementUI:setActions fits the element to the glyph it shows
        key = e.extra.get("glyphKey") or builder.keys.get(e.extra.get("inputAction") or "")
        if key:
            e.size[0] = key_glyph_width(builder, key, e.size[1], e.screen)
            e.update_anchor_deltas()
        return
    if e.upper == "BUTTON":
        if not (e.attr_bool("fitToContent", False) or e.extra.get("textAutoWidth")):
            return
        icon_w, _ = button_icon_size(builder, e)
        text_w = builder.measurer.width(text_display(e), e.extra["textSize"], text_bold(e), e.screen)
        fit_extra = norm_value(e.attr("fitExtraWidth"), True, e.screen, 0.0) or 0.0
        e.size[0] = icon_w + text_w + 0.001 + fit_extra
        e.update_anchor_deltas()
        return
    if not e.extra.get("textAutoWidth"):
        return
    width = builder.measurer.width(text_display(e), e.extra["textSize"], text_bold(e), e.screen)
    if e.extra.get("textMaxWidth") is not None:
        width = min(width, e.extra["textMaxWidth"])
    width = max(width, e.extra.get("textMinWidth") or 0.0)
    width += e.extra["textOffset"][0]
    height = e.extra["textSize"] if e.size[1] == 0 else None
    e.size[0] = width
    if height is not None:
        e.size[1] = height
    e.update_anchor_deltas()


def text_layout(e: Element, measurer: TextMeasurer):
    """Return text lines with baseline positions (top-down pixels). Mirrors
    TextElement:draw/getTextPosition: the baseline sits textSize*0.1 above the line bottom."""
    text = text_display(e)
    if not text:
        return None
    s = e.screen
    size = e.extra["textSize"]
    bold = text_bold(e)
    line_h = size * e.extra["textLineHeightScale"]
    max_width = e.abs_size[0]
    if e.extra.get("textMaxWidth") is not None:
        max_width = e.extra["textMaxWidth"]
    elif e.extra.get("textAutoWidth"):
        max_width = 1.0
    mode = e.extra["textLayoutMode"]
    max_lines = e.extra["textMaxNumLines"]
    lines = wrap_text(text, size, bold, max_width, max_lines, measurer, s)
    if mode == "resize" and len(lines) == 1:
        width = measurer.width(lines[0], size, bold, s)
        default = size
        while width > max_width and size > 0.01 + default * 0.05:
            size -= default * 0.05
            width = measurer.width(lines[0], size, bold, s)
        line_h = size * e.extra["textLineHeightScale"]
    if mode in ("truncate", "resize") and len(lines) > max_lines:
        lines = lines[:max_lines]
        lines[-1] = lines[-1].rstrip() + "..."
    if mode in ("truncate",) and len(lines) == 1:
        lines[0] = limit_to_width(lines[0], size, bold, max_width, measurer, s)
    total_h = line_h * len(lines)
    va = e.extra["textVerticalAlignment"]
    if va == "top":
        y = e.abs_pos[1] + e.abs_size[1] - line_h
    elif va == "middle":
        y = e.abs_pos[1] + (e.abs_size[1] + total_h) * 0.5 - line_h
    else:
        y = e.abs_pos[1] + total_h - line_h
    y += size * 0.1
    ox, oy = text_offset(e)
    align = e.extra["textAlignment"]
    x = e.abs_pos[0]
    if align == "center":
        x += e.abs_size[0] * 0.5
    elif align == "right":
        x += e.abs_size[0]
    out = []
    for i, line in enumerate(lines):
        base = y - i * line_h + oy
        out.append({"text": line, "x": (x + ox) * s.width, "baseline": (1 - base) * s.height})
    return {"lines": out, "size_px": size * s.height, "bold": bold, "align": align,
            "color": text_color(e), "maxWidthPx": max_width * s.width}


def wrap_text(text, size, bold, max_width, max_lines, measurer, screen):
    paragraphs = text.split("\n")
    if max_lines <= 1:
        return [" ".join(paragraphs)]
    lines = []
    for para in paragraphs:
        tokens = re.findall(r"[⺀-￿]|[^\s⺀-￿]+\s*|\s+", para)
        current = ""
        for tok in tokens:
            trial = current + tok
            if current and measurer.width(trial.rstrip(), size, bold, screen) > max_width:
                lines.append(current.rstrip())
                current = tok.lstrip()
            else:
                current = trial
        lines.append(current.rstrip())
    return lines


def limit_to_width(text, size, bold, max_width, measurer, screen):
    if measurer.width(text, size, bold, screen) <= max_width + 1e-9:
        return text
    while text and measurer.width(text + "...", size, bold, screen) > max_width:
        text = text[:-1]
    return text + "..."


# ------------------------------------------------------------- smooth list

def clone_element(template: Element, parent: Element) -> Element:
    clone = copy.copy(template)
    clone.parent = parent
    clone.extra = copy.deepcopy(template.extra)
    clone.position = list(template.position)
    clone.size = list(template.size)
    clone.anchors = list(template.anchors)
    clone.pivot = list(template.pivot)
    clone.margin = list(template.margin)
    clone.abs_pos = list(template.abs_pos)
    clone.abs_size = list(template.abs_size)
    clone.anchor_deltas = list(template.anchor_deltas)
    clone.xml = dict(template.xml)
    clone.children = [clone_element(child, clone) for child in template.children]
    return clone


def populate_list(builder: GuiBuilder, lst: Element, data: list, selected_index: int = 1,
                  view_offset: float = 0.0) -> None:
    """SmoothListElement:buildSectionInfo + updateView + updateCellPosition for one section.

    `data` items: {"cell": template name (optional), "section": title for a header row
    (optional), plus element name -> text, or {"text":..,"visible":..,"selected":..}}.
    """
    templates = lst.extra.get("templates") or {}
    header_name = lst.extra.get("sectionHeader")
    item_templates = [name for name in templates if name != header_name]
    spacing = lst.extra["listItemSpacing"]
    offset = 0.0
    lst.children = []
    index = 0
    placed = []
    for item in data:
        if "section" in item and header_name in templates:
            if placed:
                offset += lst.extra["listSectionSpacing"]
            template = templates[header_name]
            cell = clone_element(template, lst)
            fill_cell(builder, cell, {"title": item["section"], **item.get("fields", {})})
            placed.append((cell, offset))
            offset += template.size[1] + spacing
            continue
        index += 1
        name = item.get("cell") or (item_templates[0] if item_templates else None)
        if name is None:
            continue
        template = templates[name]
        cell = clone_element(template, lst)
        fill_cell(builder, cell, item)
        placed.append((cell, offset))
        cell.set_selected(index == selected_index if "selected" not in item else bool(item["selected"]))
        offset += template.size[1] + spacing
    lst.extra["contentSize"] = max(offset - spacing, 0.0)
    align_offset = 0.0
    content_offset = lst.abs_size[1] - lst.extra["contentSize"]
    if content_offset > 0:
        align_offset = content_offset * lst.extra["alignment"]
    for cell, item_offset in placed:
        lst.children.append(cell)
        cell.position = [0.0, view_offset - item_offset - align_offset]
        cell.update_anchor_deltas()
        cell.update_absolute_position()
    lst.extra["itemCount"] = index


def fill_cell(builder: GuiBuilder, cell: Element, item: dict) -> None:
    for key, value in item.items():
        if key in ("cell", "selected", "section", "fields"):
            continue
        targets = [e for e in cell.iter() if e.name == key or e.id == key]
        for target in targets:
            apply_override(builder, target, value)


def apply_override(builder: GuiBuilder, e: Element, value) -> None:
    if not isinstance(value, dict):
        value = {"text": value}
    for key, v in value.items():
        if key == "text" and "text" in e.extra:
            e.extra["text"] = builder.text(str(v))
        elif key == "text" and e.upper in ("MULTITEXTOPTION", "OPTIONTOGGLE", "BINARYOPTION"):
            e.extra["texts"] = [builder.text(str(v))]
            e.extra["state"] = 1
        elif key == "visible":
            e.visible = bool(v)
        elif key == "selected":
            e.set_selected(bool(v))
        elif key == "focused":
            e.set_focused(bool(v))
        elif key == "disabled":
            e.disabled = bool(v)
        elif key == "state":
            e.extra["state"] = int(v)
        elif key == "texts":
            e.extra["texts"] = [builder.text(str(t)) for t in v]
        elif key == "imageSliceId":
            e.extra.setdefault("image", {"slices": {}, "colors": {}, "uvs": {}})["slices"][""] = v
        elif key == "imageColor":
            e.extra.setdefault("image", {"slices": {}, "colors": {}, "uvs": {}})["colors"][""] = \
                [float(x) for x in str(v).split()]
        elif key == "iconSliceId":
            e.extra.setdefault("icon", {"slices": {}, "colors": {}, "uvs": {}})["slices"] = {"": v}
        elif key == "imageFilename":
            e.extra.setdefault("image", {"slices": {}, "colors": {}, "uvs": {}})["file"] = v
        elif key == "absolute":
            e.absolute_override = dict(v)
        elif key == "position":
            e.position = norm_values(v, e.screen, e.position, 2)
            e.update_anchor_deltas()
        elif key == "size":
            e.extra["sizeStr"] = v
            e.extra["widthStr"] = e.extra["heightStr"] = None
            e.resolve_size()
        elif key == "value":
            e.extra["value"] = float(v)
        elif key == "key":
            e.extra["glyphKey"] = str(v)
        elif key == "items":
            e.extra["listData"] = v


# ------------------------------------------------------------------ driver

def finish_layout(builder: GuiBuilder, root: Element) -> None:
    """updateAbsolutePosition from the root, then text auto sizes and box layouts
    (onGuiSetupFinished), innermost first."""
    for e in root.iter():
        if e.upper in TEXT_TYPES or e.upper == "INPUTGLYPH":
            apply_text_auto_size(builder, e)
    root.update_absolute_position()
    boxes = [e for e in root.iter() if e.upper in LAYOUT_TYPES]
    for box in reversed(boxes):
        invalidate_layout(box)
    for box in boxes:
        invalidate_layout(box)
