"""Writes thin wrapper boards that feed data into FormScreen / ListScreen."""
import json, sys, html
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "project")
def board(name, title, component, attrs, data, height=844, backdrop=None):
    # Attributes are written as text, so a False would arrive as the truthy string
    # "False"; pass true/false settings as bound data instead.
    data = {**{k: v for k, v in attrs.items() if isinstance(v, bool)}, **data}
    attrs = {k: v for k, v in attrs.items() if not isinstance(v, bool)}
    obj_attrs = ''.join(' %s="{{%s}}"' % (k, k) for k in data)
    plain = ''.join(' %s="%s"' % (k, html.escape(str(v), quote=True)) for k, v in attrs.items())
    # A sheet can sit over the screen it opens from, scaled back and dimmed as iOS does.
    behind = ''
    if backdrop:
        data = {**data, 'over': True}
        obj_attrs = ''.join(' %s="{{%s}}"' % (k, k) for k in data)
        behind = f'''
  <div aria-hidden="true" style="position: absolute; left: 0; top: 0; width: 390px; height: {height}px; background: #000000"></div>
  <div aria-hidden="true" style="position: absolute; left: 0; top: 0; width: 390px; height: {height}px; transform: translateY(10px) scale(0.92); transform-origin: 50% 0; border-radius: 38px; overflow: hidden; pointer-events: none">
    <dc-import name="{backdrop}" hint-size="390px,{height}px"></dc-import>
    <div style="position: absolute; inset: 0; background: rgba(0,0,0,0.22)"></div>
  </div>'''
    src = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{html.escape(title)}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div style="width: 390px; height: {height}px; position: relative; overflow: hidden">{behind}
  <dc-import name="{component}"{plain} height="{height}"{obj_attrs} hint-size="390px,{height}px"></dc-import>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":{height}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {json.dumps(data, ensure_ascii=False, indent=2)};
  }}
}}
</script>
</body>
</html>
'''
    open(f'{OUT}/{name}.dc.html', 'w').write(src)
