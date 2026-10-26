# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa==2.6"]
# ///
"""Run original Lua behavior tests without loading or executing game files.

When the ignored work/ references of the game exist, the GUI XML is also checked against
them (profiles, traits, image slices, game texts); without them that check is skipped.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from lupa import LuaRuntime
from guixml import GUI_FILES, install
from multiplayer import run_multiplayer

root = Path(__file__).resolve().parents[1]
SCRIPTS = ("MapHelper", "QueueEvents", "FieldNeeds", "MapHelperPage", "MapFrameExtension", "Register")
REFERENCE = root.parent / "work/reference/1.25.0.0/dataS-archive"


def check_texts():
    """Every Mod text the scripts and GUI files use exists in modDesc.xml for all 27 languages."""
    desc = ET.parse(root / "modDesc.xml").getroot()
    texts = {node.attrib["name"]: node for node in desc.findall("l10n/text")}
    languages = [child.tag for child in desc.find("title")]
    assert len(languages) == 27, languages
    profiles = set()
    for name in GUI_FILES:
        profiles.update(node.attrib["name"] for node in ET.parse(root / name).getroot().iter("Profile"))
    used = set()
    for name in SCRIPTS:
        source = (root / f"scripts/{name}.lua").read_text(encoding="utf-8")
        used.update(re.findall(r'(?:MH|MapHelper)\.text\("([a-zA-Z_]+)"\)', source))
        # Keys kept in tables (for example the empty texts per filter) are quoted literals;
        # quoted profile names are not texts.
        used.update(set(re.findall(r'"(mh_[a-zA-Z]+)"', source)) - profiles)
    for name in GUI_FILES:
        used.update(key for key in re.findall(r'\$l10n_([a-zA-Z0-9_]+)', (root / name).read_text(encoding="utf-8"))
                    if key.startswith("mh_"))
    for action in desc.findall("actions/action"):
        used.add("input_" + action.attrib["name"])
    missing = used - set(texts)
    assert not missing, f"missing l10n keys: {sorted(missing)}"
    unused = set(texts) - used
    assert not unused, f"unused l10n keys: {sorted(unused)}"
    for key, node in texts.items():
        assert [child.tag for child in node] == languages, f"{key} does not cover all languages in order"
        english = node.find("en").text
        for child in node:
            assert child.text and child.text.strip(), f"{key}/{child.tag} is empty"
            assert child.text.count("%") == english.count("%"), f"{key}/{child.tag} format arguments differ"
    descriptions = desc.find("description")
    assert [child.tag for child in descriptions] == languages, "description does not cover all languages in order"
    print(f"PASS l10n: {len(used)} keys used, {len(texts)} defined in {len(languages)} languages")


def check_gui_against_game():
    """Profiles, traits, slices and game texts used by the GUI files exist in 1.25."""
    if not REFERENCE.is_dir():
        print("SKIP GUI reference check: work/reference/1.25.0.0/dataS-archive not found")
        return
    native = ET.parse(REFERENCE / "guiProfiles.xml").getroot()
    profiles = {node.attrib["name"] for node in native.iter("Profile")}
    traits = {node.attrib["name"] for node in native.iter("Trait")}
    frame = ET.parse(REFERENCE / "gui/InGameMenuMapFrame.xml").getroot()
    profiles |= {node.attrib["name"] for node in frame.iter("Profile")}
    slices = set(re.findall(r'<slice id="([^"]+)"', (REFERENCE / "menu/gui.xml").read_text(encoding="utf-8")))
    game_texts = set(re.findall(r'<e k="([^"]+)"', (REFERENCE / "l10n/l10n_en.xml").read_text(encoding="utf-8")))
    script_texts = set()
    for name in SCRIPTS:
        script_texts.update(re.findall(r'g_i18n:getText\("([a-zA-Z0-9_]+)"\)', (root / f"scripts/{name}.lua").read_text(encoding="utf-8")))
        # Game text keys kept in tables (FieldNeeds work and ground texts).
        script_texts.update(re.findall(r'"((?:ui|contract|button)_[a-zA-Z0-9_]+)"', (root / f"scripts/{name}.lua").read_text(encoding="utf-8")))
    missing_texts = script_texts - game_texts
    assert not missing_texts, f"game texts not found: {sorted(missing_texts)}"
    checked = 0
    for name in GUI_FILES:
        tree = ET.parse(root / name).getroot()
        own = {node.attrib["name"] for node in tree.iter("Profile")}
        for node in tree.iter():
            profile = node.attrib.get("profile")
            if profile is not None:
                assert profile in own or profile in profiles, f"{name}: unknown profile {profile}"
                checked += 1
            for key in re.findall(r'\$l10n_([a-zA-Z0-9_]+)', node.attrib.get("text", "")):
                assert key.startswith("mh_") or key in game_texts, f"{name}: unknown game text {key}"
        for node in tree.iter("Profile"):
            parent = node.attrib.get("extends")
            assert parent is None or parent in own or parent in profiles, f"{name}: unknown parent profile {parent}"
            for trait in node.attrib.get("with", "").split():
                assert trait in traits, f"{name}: unknown trait {trait}"
            for value in node:
                text = value.attrib.get("value", "")
                if value.tag.endswith("SliceId") and text != "noSlice":
                    assert text.removeprefix("gui.") in slices, f"{name}: unknown slice {text}"
                if text.startswith("$preset_"):
                    preset = text.removeprefix("$preset_")
                    assert f'<Preset name="{preset}"' in (REFERENCE / "guiProfiles.xml").read_text(encoding="utf-8"), preset
    print(f"PASS GUI reference check: {checked} profile uses, traits, slices, presets and texts exist in 1.25")


def load_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
    install(lua, root)
    for name in SCRIPTS:
        lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
    return lua


check_texts()
check_gui_against_game()
lua = load_runtime()
# Simulate a second map load: hooks must not stack and the map page must not get duplicate controls.
lua.execute((root / "scripts/Register.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests/behavior.lua").read_text(encoding="utf-8"))

# A game version without the map frame or AI system only disables the matching feature.
missing = LuaRuntime(unpack_returned_tuples=True)
missing.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
install(missing, root)
missing.execute("InGameMenuMapFrame.setupMapOverview = nil; AISystem = nil")
for name in SCRIPTS:
    missing.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
missing.execute("""
    assert(not MapHelper.features.page and not MapHelper.features.queue and not MapHelper.features.hotkey)
    assert(#logged.warnings == 2, #logged.warnings)
    assert(logged.warnings[1]:find('AISystem', 1, true) and logged.warnings[2]:find('setupMapOverview', 1, true))
    FSBaseMission.onStartMission(g_currentMission)
    assert(#g_messageCenter.subscribers == 0 and next(g_currentMission.updateables) == nil)
    assert(not MapHelper.handleRequest(MapHelper.ACTION.CLEAR, nil, nil, nil, localConnection))
    local frame = mockFrame()
    InGameMenuMapFrame.onLoadMapFinished(frame)
    assert(frame.mapHelper == nil, 'no page without the map frame functions')
    FSBaseMission.delete(g_currentMission)
""")
hotkey = LuaRuntime(unpack_returned_tuples=True)
hotkey.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
install(hotkey, root)
hotkey.execute("InGameMenu.openMapOverview = nil")
for name in SCRIPTS:
    hotkey.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
hotkey.execute("""
    assert(MapHelper.features.page and MapHelper.features.queue and not MapHelper.features.hotkey)
    assert(#logged.warnings == 1 and logged.warnings[1]:find('hotkey', 1, true))
""")
print("PASS missing game functions disable only their feature and log once")
run_multiplayer(root)
