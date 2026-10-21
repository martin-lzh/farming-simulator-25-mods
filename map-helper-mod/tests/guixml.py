"""Hand the Mod's GUI XML files to the Lua doubles as plain tables.

The doubles build their element trees from the real files, so ids, names, callbacks and
profiles in the tests are the ones the game loads. Nothing from the game is read here.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

GUI_FILES = ("gui/MapHelperPage.xml", "gui/DrawerToggle.xml")


def _element(node):
    return {
        "type": node.tag,
        "attributes": dict(node.attrib),
        "children": [_element(child) for child in node if child.tag != "GUIProfiles"],
    }


def _profiles(root):
    profiles = {}
    for profile in root.iter("Profile"):
        values = {child.tag: child.attrib.get("value", "") for child in profile}
        profiles[profile.attrib["name"]] = {"extends": profile.attrib.get("extends", ""), "values": values}
    return profiles


def load_gui_files(root):
    result = {}
    for name in GUI_FILES:
        tree = ET.parse(Path(root) / name).getroot()
        result[name] = {"tree": _element(tree), "profiles": _profiles(tree)}
    return result


def to_lua(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: to_lua(lua, item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(lua, item) for item in value])
    return value


def install(lua, root):
    lua.globals().guiFiles = to_lua(lua, load_gui_files(root))
