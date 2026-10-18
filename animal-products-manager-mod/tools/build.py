"""Build a reproducible release ZIP containing only the original runtime files."""
from pathlib import Path
import hashlib
import struct
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parent / "outputs/FS25_AnimalProductsManager.zip"

def build():
    desc = ET.parse(ROOT / "modDesc.xml").getroot()
    assert desc.findtext("iconFilename") == "icon.dds", "Runtime icon must use the prepared DDS"
    icon = (ROOT / "icon.dds").read_bytes()
    assert icon[:4] == b"DDS " and len(icon) >= 128, "Invalid DDS icon"
    assert struct.unpack_from("<I", icon, 4)[0] == 124, "Invalid DDS header"
    height, width = struct.unpack_from("<II", icon, 12)
    mip_count = struct.unpack_from("<I", icon, 28)[0]
    assert (width, height, mip_count) == (512, 512, 10), "Icon needs the full 512-to-1 mip chain"
    assert icon[84:88] == b"DXT1", "Icon must use BC1 block compression"
    flags, caps = struct.unpack_from("<I", icon, 8)[0], struct.unpack_from("<I", icon, 108)[0]
    assert flags & 0x20000 and caps & 0x400000 and caps & 0x8, "Missing DDS mipmap flags"
    payload_size = sum(max(1, (width >> level) // 4) * max(1, (height >> level) // 4) * 8
                       for level in range(mip_count))
    assert len(icon) == 128 + payload_size, "Truncated or unexpected icon mip payload"
    paths = {"modDesc.xml", desc.findtext("iconFilename")}
    paths.update(node.attrib["filename"] for node in desc.findall("extraSourceFiles/sourceFile"))
    paths.update(node.attrib["filename"] for node in desc.findall("placeableSpecializations/specialization"))
    paths.add("gui/ProductDialog.xml")
    assert len(paths) == 8, "Review runtime whitelist when adding files"
    ET.parse(ROOT / "gui/ProductDialog.xml")
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
