"""Writes thin wrapper boards that feed data into FormScreen / ListScreen."""
import json, sys, html
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "project")
def board(name, title, component, attrs, data, height=844):
    obj_attrs = ''.join(' %s="{{%s}}"' % (k, k) for k in data)
    plain = ''.join(' %s="%s"' % (k, html.escape(str(v), quote=True)) for k, v in attrs.items())
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
<div style="width: 390px; height: {height}px; position: relative; overflow: hidden">
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
