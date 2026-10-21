"""Self-test of the GUI preview lab core (tools/gui_lab/gui_engine.py), standard library only."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gui_lab"))
import gui_engine as g  # noqa: E402

PROFILES = """
<GUIProfiles>
  <Presets>
    <Preset name="colorA" value="0.1 0.2 0.3 1"/>
    <Preset name="colorB" value="$preset_colorA"/>
  </Presets>
  <Traits>
    <Trait name="anchorTopLeft"><anchors value="0 0 1 1"/><pivot value="0 1"/></Trait>
    <Trait name="anchorTopStretchingX"><anchors value="0 1 1 1"/><pivot value="0.5 1"/></Trait>
    <Trait name="anchorBottomRight"><anchors value="1 1 0 0"/><pivot value="1 0"/></Trait>
  </Traits>
  <Profile name="baseReference">
    <size value="100% 100%"/>
    <anchors value="0 0 0 0"/>
    <pivot value="0 0"/>
    <imageColor value="1 1 1 1"/>
  </Profile>
  <Profile name="parent" extends="baseReference" with="anchorTopLeft">
    <size value="200px 100px"/>
    <imageColor value="$preset_colorB"/>
  </Profile>
  <Profile name="child" extends="parent" with="anchorBottomRight">
    <position value="-10px 5px"/>
  </Profile>
  <Profile name="childOwnAnchors" extends="parent" with="anchorBottomRight">
    <anchors value="0 1 0 1"/>
  </Profile>
</GUIProfiles>
"""


def store() -> g.ProfileStore:
    s = g.ProfileStore()
    s.load_profiles_file(g.parse_xml(PROFILES, is_text=True))
    return s


def build(gui_xml: str, screen=(1920, 1080)):
    builder = g.GuiBuilder(store(), g.Screen(*screen))
    root = builder.load_gui(g.parse_xml(gui_xml, is_text=True))
    g.finish_layout(builder, root)
    return root


class ProfileTests(unittest.TestCase):
    def test_inheritance_and_presets(self):
        child = store().get_profile("child")
        self.assertEqual(child.get("size"), "200px 100px")          # from parent
        self.assertEqual(child.get("imageColor"), "0.1 0.2 0.3 1")  # nested preset
        self.assertEqual(child.get("position"), "-10px 5px")        # own value

    def test_traits_override_parent_and_own_values_override_traits(self):
        s = store()
        self.assertEqual(s.get_profile("child").get("anchors"), "1 1 0 0")
        self.assertEqual(s.get_profile("child").get("pivot"), "1 0")
        self.assertEqual(s.get_profile("childOwnAnchors").get("anchors"), "0 1 0 1")
        self.assertEqual(s.get_profile("childOwnAnchors").get("pivot"), "1 0")

    def test_unknown_profile_falls_back_to_base_reference(self):
        self.assertEqual(store().get_profile("missing").name, "baseReference")


class GeometryTests(unittest.TestCase):
    def test_pixel_values_scale_uniformly_on_16_10(self):
        screen = g.Screen(2000, 1250)
        self.assertAlmostEqual(g.norm_value("192px", True, screen) * 2000, 200.0)
        self.assertAlmostEqual(g.norm_value("108px", False, screen) * 1250, 112.5)
        self.assertAlmostEqual(screen.ui_scale, 2000 / 1920)

    def test_anchor_pivot_position_math(self):
        root = build("""<GUI>
          <GuiElement profile="parent" id="box">
            <GuiElement profile="child" id="corner" size="20px 10px"/>
            <GuiElement profile="baseReference" id="bar" anchors="0 1 1 1" pivot="0 1"
                        size="100% 10px" absoluteSizeOffset="40px 0px" position="20px -5px"/>
          </GuiElement></GUI>""")
        box, corner, bar = root.find("box"), root.find("corner"), root.find("bar")
        self.assertEqual([round(v) for v in box.rect_px()], [0, 0, 200, 100])
        # bottom-right anchored with pivot 1 0, moved 10px left and 5px up
        self.assertEqual([round(v) for v in corner.rect_px()], [170, 85, 20, 10])
        # 100% width minus absoluteSizeOffset, top anchored, 20px in and 5px down
        self.assertEqual([round(v) for v in bar.rect_px()], [20, 5, 160, 10])

    def test_box_layout_vertical_flow_with_margin_and_spacing(self):
        root = build("""<GUI>
          <BoxLayout profile="parent" id="list" flowDirection="vertical" elementSpacing="4px">
            <GuiElement profile="baseReference" id="a" size="50px 20px"/>
            <GuiElement profile="baseReference" id="b" size="60px 30px" margin="5px 6px 0px 0px"/>
            <GuiElement profile="baseReference" id="hidden" size="60px 30px" visible="false"/>
            <GuiElement profile="baseReference" id="c" size="70px 10px"/>
          </BoxLayout></GUI>""")
        rects = {key: [round(v) for v in root.find(key).rect_px()] for key in "abc"}
        self.assertEqual(rects["a"], [0, 0, 50, 20])
        self.assertEqual(rects["b"], [5, 30, 60, 30])   # 20 + 4 spacing + 6 top margin
        self.assertEqual(rects["c"], [0, 64, 70, 10])   # hidden element takes no space

    def test_box_layout_horizontal_right_alignment(self):
        root = build("""<GUI>
          <BoxLayout profile="parent" id="row" alignmentX="right" alignmentY="middle">
            <GuiElement profile="baseReference" id="a" size="50px 20px"/>
            <GuiElement profile="baseReference" id="b" size="30px 40px"/>
          </BoxLayout></GUI>""")
        self.assertEqual([round(v) for v in root.find("a").rect_px()], [120, 40, 50, 20])
        self.assertEqual([round(v) for v in root.find("b").rect_px()], [170, 30, 30, 40])


if __name__ == "__main__":
    unittest.main()
