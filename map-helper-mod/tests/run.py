# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa==2.6"]
# ///
"""Run original Lua behavior tests without loading or executing game files."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from lupa import LuaRuntime
from multiplayer import run_multiplayer

root = Path(__file__).resolve().parents[1]
SCRIPTS = ("MapHelper", "QueueEvents", "DrawerDialog", "MapFrameExtension", "Register")


def check_texts():
    """Every Mod text the scripts ask for exists in modDesc.xml for all 27 languages."""
    desc = ET.parse(root / "modDesc.xml").getroot()
    texts = {node.attrib["name"]: node for node in desc.findall("l10n/text")}
    languages = [child.tag for child in desc.find("title")]
    assert len(languages) == 27, languages
    used = set()
    for name in SCRIPTS:
        source = (root / f"scripts/{name}.lua").read_text(encoding="utf-8")
        used.update(re.findall(r'(?:MH|MapHelper)\.text\("([a-zA-Z_]+)"\)', source))
    for action in desc.findall("actions/action"):
        used.add("input_" + action.attrib["name"])
    missing = used - set(texts)
    assert not missing, f"missing l10n keys: {sorted(missing)}"
    for key, node in texts.items():
        assert [child.tag for child in node] == languages, f"{key} does not cover all languages in order"
        for child in node:
            assert child.text and child.text.strip(), f"{key}/{child.tag} is empty"
            english = node.find("en").text
            assert child.text.count("%") == english.count("%"), f"{key}/{child.tag} format arguments differ"
    print(f"PASS l10n: {len(used)} keys used, {len(texts)} defined in {len(languages)} languages")


def load_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
    for name in SCRIPTS:
        lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
    return lua


check_texts()
lua = load_runtime()
# Simulate a second map load: hooks must not stack and the map page must not get duplicate buttons.
lua.execute((root / "scripts/Register.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests/behavior.lua").read_text(encoding="utf-8"))

# A game version without the map frame or AI system only disables the matching feature.
missing = LuaRuntime(unpack_returned_tuples=True)
missing.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
missing.execute("InGameMenuMapFrame = nil; AISystem = nil")
for name in SCRIPTS:
    missing.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
missing.execute("""
    assert(not MapHelper.features.drawer and not MapHelper.features.queue)
    assert(#logged.warnings == 2, #logged.warnings)
    assert(logged.warnings[1]:find('AISystem', 1, true) and logged.warnings[2]:find('InGameMenuMapFrame', 1, true))
    FSBaseMission.onStartMission(g_currentMission)
    assert(#g_messageCenter.subscribers == 0 and next(g_currentMission.updateables) == nil)
    assert(not MapHelper.handleRequest(MapHelper.ACTION.CLEAR, nil, nil, nil, localConnection))
""")
print("PASS missing game functions disable only their feature and log once")
run_multiplayer(root)
