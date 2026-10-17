"""Build a reproducible release ZIP containing only the original runtime files."""
from pathlib import Path
import hashlib
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parent / "outputs/FS25_AnimalProductDistribution.zip"

def build():
    desc = ET.parse(ROOT / "modDesc.xml").getroot()
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
        assert path.suffix in {".lua", ".xml", ".png"}, name
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
