# GUI preview lab

Renders Farming Simulator 25 GUI XML (GIANTS Engine) into a static HTML page, so a layout can be
checked in a browser without starting the game. It reads the vanilla GUI files from the ignored
`work/reference/1.25.0.0/dataS-archive/`, applies a scenario (screen size, visible containers,
texts, list rows, Mod XML injected under an element) and writes `outputs/gui-lab/<name>.html`.

This is a layout check, not in-game testing.

## Run

```powershell
uv run tools/gui_lab/render.py tools/gui_lab/scenarios/calibration-active-workers.json
uv run tools/gui_lab/render.py <scenario.json> --screenshot   # also <name>.png via headless Edge/Chrome
uv run tools/gui_lab/render.py <scenario.json> --dump         # print every visible element's pixel rect
```

Needs the extracted game files in `work/reference/1.25.0.0/dataS-archive/` and
`work/tools/directxtex/texconv.exe` (DDS to PNG). Converted atlases and tinted slices are cached
in `work/gui-lab/cache/`; delete that folder to rebuild them. Pages load Noto Sans SC from Google
Fonts and fall back to Microsoft YaHei. Hover an element to see its type, profile, id/name,
source file and pixel rect.

## Files

- `gui_engine.py`: profiles (presets, traits, `extends`), element loading and layout. Standard
  library only; `tools/tests/test_gui_lab.py` tests it.
- `render.py`: scenario handling, textures and HTML output (Pillow and NumPy through uv).
- `scenarios/`: `calibration-active-workers.json` (vanilla map page, 2000x1250) and
  `example-injection.json` with `example-panel.xml` (an injected sidebar page).

## Scenario format

```json
{
  "name": "my-page",                       // output name (default: file name)
  "screen": [2000, 1250],                  // pixels; 16:10 and 16:9 scale like the game
  "language": "cs",                        // loads $ref/l10n/l10n_<language>.xml for $l10n_ texts
  "l10n": {"myKey": "My text"},            // extra or replaced texts
  "keys": {"MENU_EXTRA_1": "X"},           // key glyph per input action (defaults in render.py)
  "background": "#000000",
  "map": {"color": "#33502c", "image": "path.png"},  // what InGameMap elements show
  "base": "$ref/gui/InGameMenu.xml",       // root GUI file
  "injections": [                          // loadProfileSet + loadGuiRec under an element
    {"file": "$ref/gui/InGameMenuMapFrame.xml", "parent": "pagingElement"},
    {"file": "map-helper-mod/gui/Page.xml", "parent": "filterBox", "index": 0}
  ],
  "textureConfigs": [{"prefix": "myMod", "xml": "my-mod/gui/ui.xml"}],  // extra slice atlases
  "overrides": {                           // keys: id, name, id[n] (n-th child), outer/inner
    "filterListContainer": {"visible": false},
    "mapOverviewSelector": {"texts": ["A", "B"], "state": 2},
    "subCategoryDotBox[2]": {"selected": true},
    "currentBalanceText": {"text": "437,370 €"},
    "myPanel": {"absolute": {"x": 1500, "y": 180, "width": 400, "height": 300}}
  },
  "lists": {"activeWorkerList": [{"title": "FASTRAC 2135 4WS", "text": "Field work"}]},
  "listSelection": {"activeWorkerList": 1},
  "cellOverrides": {"activeWorkerList/title": {"selected": false}},
  "fontScale": 1.0,
  "outline": false                         // thin outline around every element
}
```

(The comments are for this README only; scenario files are plain JSON.)

- Paths starting with `$ref/` point into the reference `dataS` folder; other paths are relative
  to the repository root.
- Override values: `visible`, `text`, `texts`, `state`, `selected`, `focused`, `disabled`,
  `position` / `size` (GUI units such as `"20px -5px"`), `absolute` (top-down screen pixels, for
  things Lua positions), `imageSliceId`, `iconSliceId`, `imageColor`, `key` (glyph text for a
  Button or InputGlyph). A plain string means `text`.
- List rows map element names inside the ListItem template to values (string or override
  object); `"cell": "<template name>"` picks a template, `"section": "Title"` adds a header row.
  The selected row (default 1) is drawn in its selected state, as with `selectedWithoutFocus`.

### Injecting a Mod page under `filterBox`

```json
{
  "name": "map-helper-page",
  "screen": [2000, 1250],
  "language": "cs",
  "base": "$ref/gui/InGameMenu.xml",
  "injections": [
    {"file": "$ref/gui/InGameMenuMapFrame.xml", "parent": "pagingElement"},
    {"file": "map-helper-mod/gui/<page>.xml", "parent": "filterBox"}
  ],
  "overrides": {
    "buttonsPanel": {"visible": false},
    "ingameMap": {"absolute": {"x": 130, "y": 0, "width": 1870, "height": 1208}},
    "filterListContainer": {"visible": false},
    "createJobContainer": {"visible": false},
    "createJobEmptyText": {"visible": false},
    "workerListContainer": {"visible": false},
    "mapOverviewSelector": {"texts": ["地图助手"], "state": 1}
  }
}
```

The map frame is injected under the in-game menu's `pagingElement`, which places it right of the
tab column like the game's FrameReference. Hide `buttonsPanel` because the map frame has its own
button bar. If the Mod uses its own texture atlas, add it under `textureConfigs`.

## Supported elements

GuiElement/emptyPanel, Bitmap, ThreePartBitmap (horizontal and vertical), RoundCorner, Text,
Button (image, icon, keyboard key glyph, `fitToContent`), BoxLayout and ScrollingLayout (flow
direction, alignment, fill direction, margins, spacing, several flows), SmoothList (ListItem
templates filled from the scenario, sections, item spacing and alignment, clippers, empty
indicator), MultiTextOption/OptionToggle (default left/right buttons, text and background from
the `defaultProfile*` values, state), Slider (track; the bar only when the list overflows),
InputGlyph (key box), InGameMap (placeholder), Paging and FrameReference (containers). Other
types are laid out as GuiElement and drawn with a dashed magenta outline; `render.py` lists them.

## What follows the game and what is approximated

Follows the 1.25.0.0 scripts: profile resolution (`with` traits, then own values, then
`extends`; first definition wins), px/dp/% values with the aspect scaling of `main.lua`
(16:10 scales by width), size strings, `absoluteSizeOffset`, anchors and pivot via anchor
deltas, BoxLayout cell placement, SmoothList offsets, overlay state colours and slices,
ThreePartBitmap colour copying, text alignment and baseline (`textSize * 0.1`), and colours
converted from the game's linear values to sRGB. Textures are multiplied by the colour in
linear space.

Approximated:

- Fonts: web fonts instead of the game's bitmap fonts. Text widths for auto-sized texts and
  buttons are measured with a local font (Microsoft YaHei) or a heuristic, so widths can differ
  by a few pixels. Long texts are truncated or shrunk roughly like the game; scrolling text is
  static.
- Lua behaviour is not run. Anything a frame sets in code (texts, visibility, list data,
  positions, selected dots) has to come from the scenario.
- Input glyphs show key text in a key box; mouse and gamepad icons are not drawn.
- Four-corner colour gradients on plain colour fills are averaged per edge.
- Focus, highlight, animations, masks, rotations other than whole degrees on icons, `newLayer`
  ordering beyond "draw above earlier content", and the safe frame are not modelled.

## Calibration

`calibration-active-workers.json` renders the map page's Active workers view at 2000x1250 and
was compared with an in-game screenshot (16:10, Chinese). Measured on the render: tab column
0-130, sidebar 130-563, selector arrows centred at x 181 and 506 and y 79, title centred at x
343, page dots at y 114 (last one green), worker row 156-234 with the icon box at 160-238 and the green bar from 238, slider
track x 529-535 from y 151 to 1177, button bar from y 1208. All within 7 px of the screenshot.
