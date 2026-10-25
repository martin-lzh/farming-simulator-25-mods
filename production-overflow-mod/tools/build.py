"""Build a reproducible release ZIP containing only the original runtime files."""
from pathlib import Path
import hashlib
import struct
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parent / "outputs/FS25_ProductionOverflow.zip"

def build():
    desc = ET.parse(ROOT / "modDesc.xml").getroot()
    icon_name = desc.findtext("iconFilename")
    assert icon_name == "icon_productionOverflow.dds", "Runtime icon must use the prepared DDS"
    icon = (ROOT / icon_name).read_bytes()
    assert icon[:4] == b"DDS " and len(icon) >= 128, "Invalid DDS icon"
    assert struct.unpack_from("<I", icon, 4)[0] == 124, "Invalid DDS header"
    height, width = struct.unpack_from("<II", icon, 12)
    mip_count = struct.unpack_from("<I", icon, 28)[0]
    # ModHub wants a 512x512 BC1 icon without mipmaps.
    assert (width, height) == (512, 512) and mip_count <= 1, "Icon must be 512x512 without mipmaps"
    assert icon[84:88] == b"DXT1", "Icon must use BC1 block compression"
    assert not struct.unpack_from("<I", icon, 108)[0] & 0x400000, "Icon must not carry mipmap caps"
    assert len(icon) == 128 + (width // 4) * (height // 4) * 8, "Truncated or unexpected icon payload"
    paths = {"modDesc.xml", icon_name}
    paths.update(node.attrib["filename"] for node in desc.findall("extraSourceFiles/sourceFile"))
    paths.update(node.attrib["filename"] for node in desc.findall("placeableSpecializations/specialization"))
    assert paths == {
        "modDesc.xml", "icon_productionOverflow.dds", "scripts/ProductionOverflow.lua", "scripts/ModeEvent.lua",
        "scripts/Register.lua", "scripts/ProductionOverflowPlaceable.lua",
    }, "Review runtime whitelist when adding files"
    for name in paths:
        path = ROOT / name
        assert path.resolve().is_relative_to(ROOT.resolve()), name
        assert path.is_file() and path.stat().st_size > 0, name
        assert path.suffix in {".lua", ".xml", ".dds"}, name
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(paths):
            info = ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, (ROOT / name).read_bytes())
    with ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == paths
        ET.fromstring(archive.read("modDesc.xml"))
    print(f"{OUTPUT}\nFiles: {len(paths)}\nSHA256: {hashlib.sha256(OUTPUT.read_bytes()).hexdigest()}")

if __name__ == "__main__":
    build()
