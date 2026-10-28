# Board generator

The Subscreens page's form and list screens are thin wrappers that feed data into
`project/FormScreen.dc.html` and `project/ListScreen.dc.html`. Edit the data here and
regenerate rather than editing the generated boards by hand:

    cd Design/redesign/tools && python3 -I group1.py   # or drill / group2a / group2b / group3

`gen.py` writes one `project/<Name>.dc.html` per `add(...)`; `data.py` holds the shared
sample works and icon paths. Canvas placement lives in `project/canvas.json`.
