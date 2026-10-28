# Board generator

The Subscreens page's form and list screens are thin wrappers that feed data into
`project/FormScreen.dc.html` and `project/ListScreen.dc.html`. Edit the data here and
regenerate rather than editing the generated boards by hand:

    cd Design/redesign/tools && python3 -I group1.py   # or drill / group2a / group2b / group3 / group4

`gen.py` writes one `project/<Name>.dc.html` per `add(...)`; `data.py` holds the shared
sample works and icon paths. Canvas placement lives in `project/canvas.json`.

`themes.py` draws every phone screen in Dark, OLED and Sepia: three
`project/Skin-<Theme>.dc.html` stylesheets and one `project/Themes-<Board>.dc.html`
triptych per screen, on the "Dark · OLED · Sepia" canvas page. Run it again after
changing a Light board's height or position, or after adding a screen.
