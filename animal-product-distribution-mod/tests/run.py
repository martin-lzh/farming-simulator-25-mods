# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa==2.6"]
# ///
"""Run original Lua behavior tests without loading or executing game files."""
from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((root / "tests/engine_mock.lua").read_text(encoding="utf-8"))
for name in ("Distribution", "AnimalProductDistribution", "ModeEvent", "Register"):
    lua.execute((root / f"scripts/{name}.lua").read_text(encoding="utf-8"))
# Simulate a second map load: hooks must not produce duplicate menu buttons.
lua.execute((root / "scripts/Register.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests/behavior.lua").read_text(encoding="utf-8"))
