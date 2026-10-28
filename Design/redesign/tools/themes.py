"""Theme variants: every phone screen in Dark, OLED and Sepia.

Boards hard-code Light colours, and the runtime writes every inline colour as
`rgb(...)`. So one stylesheet per theme (`project/Skin-<Theme>.dc.html`) recolours
any board by matching those values, and each variant board is a thin wrapper that
imports the Light board under that skin. Palettes are the Themes board's tokens.

    cd Design/redesign/tools && python3 -I themes.py

Writes the three skins, one `<Theme>-<Board>.dc.html` per screen and theme, and
the three canvas pages (boards keep their Light positions; Subscreens and Insights
sit below the iPhone rows).
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'project')

THEMES = {
 'Dark':  dict(plain='#16161B', card='#222228', ink='#F2F2F7', ink3='#D1D1D6', ink2='#AEAEB2', faint='#636366', sep='#38383E', chip='#2E2E35', fill='rgba(118,118,128,0.24)', track='#3A3A40', toggle='#39393D', glass='rgba(44,44,50,0.78)', link='#FF7A70', chev='#55555C', seg='#5A5A62', page='#16161B', pageInk='#CFCFD4', pageInk2='#9A9AA2', paperGlass='rgba(44,44,50,0.80)', paperFill='rgba(255,255,255,0.08)', rgb='22,22,27', grouped='22,22,27'),
 'OLED':  dict(plain='#000000', card='#1C1C1E', ink='#F2F2F7', ink3='#D1D1D6', ink2='#AEAEB2', faint='#636366', sep='#38383A', chip='#2C2C2E', fill='rgba(118,118,128,0.24)', track='#3A3A3C', toggle='#39393D', glass='rgba(36,36,38,0.80)', link='#FF7A70', chev='#545458', seg='#636366', page='#000000', pageInk='#CFCFD4', pageInk2='#9A9AA2', paperGlass='rgba(36,36,38,0.82)', paperFill='rgba(255,255,255,0.08)', rgb='0,0,0', grouped='0,0,0'),
 'Sepia': dict(plain='#FBF0D9', card='#F1E3C5', ink='#2E241B', ink3='#4A3B2C', ink2='#6B645A', faint='#A39580', sep='#E2D2B2', chip='#EADBBC', fill='rgba(60,40,10,0.08)', track='#E5D5B5', toggle='#E3D3B3', glass='rgba(251,240,217,0.80)', link='#990000', chev='#B8A88C', seg='#FFF9EC', page='#FBF0D9', pageInk='#5B4636', pageInk2='#7A6A58', paperGlass='rgba(251,240,217,0.82)', paperFill='rgba(60,40,10,0.07)', rgb='251,240,217', grouped='251,240,217'),
}

def bg(v): return '[style*="background: %s"]' % v
def fg(v): return ':is([style^="color: %s"], [style*="; color: %s"])' % (v, v)

def skin(t):
    # `.th` is the wrapper; `:not(#z)` lifts a rule over the context rules below it.
    page = ':is(%s[style*="bottom: 0px"], %s[style*="width: 390px"])' % (bg('rgb(242, 242, 247)'), bg('rgb(242, 242, 247)'))
    knob = '[style*="width: 27px"]'
    R = []
    # Generated covers, the Resume card and the draft card keep their colours.
    keep = ':not([style*="linear-gradient(155deg"] *)'
    def rule(sel, decl): R.append('%s%s { %s }' % (sel, keep, decl))
    # Surfaces: white is the canvas and #F2F2F7 the card, except on a grouped page,
    # where #F2F2F7 is the canvas and white the cell.
    R.append('.th { background: %s }' % t['plain'])
    rule('.th %s:not(%s)' % (bg('rgb(255, 255, 255)'), knob), 'background: %s !important' % t['plain'])
    rule('.th %s' % bg('rgb(242, 242, 247)'), 'background: %s !important' % t['card'])
    rule('.th %s' % page, 'background: %s !important' % t['plain'])
    rule('.th %s %s:not(%s)' % (page, bg('rgb(255, 255, 255)'), knob), 'background: %s !important' % t['card'])
    # Selected segment and menus.
    rule('.th %s[style*="box-shadow: rgba(0, 0, 0, 0.12) 0px 2px 6px"]:not(#z)' % bg('rgb(255, 255, 255)'), 'background: %s !important' % t['seg'])
    for v in ['rgba(255, 255, 255, 0.74)', 'rgba(255, 255, 255, 0.8)', 'rgba(255, 255, 255, 0.78)', 'rgba(250, 250, 252, 0.9)', 'rgba(255, 255, 255, 0.9)']:
        rule('.th %s' % bg(v), 'background: %s !important' % t['glass'])
    # Hairlines, chips, fills, tracks.
    for v in ['rgb(229, 229, 234)', 'rgb(209, 209, 214)', 'rgb(199, 199, 204)']:
        rule('.th %s' % bg(v), 'background: %s !important' % t['sep'])
        rule('.th [style*="solid %s"]' % v, 'border-color: %s !important' % t['sep'])
    rule('.th %s' % bg('rgb(239, 239, 244)'), 'background: %s !important' % t['chip'])
    rule('.th %s' % bg('rgb(230, 230, 235)'), 'background: %s !important' % t['track'])
    rule('.th %s' % bg('rgb(233, 233, 235)'), 'background: %s !important' % t['toggle'])
    rule('.th %s' % bg('rgba(118, 118, 128, 0.12)'), 'background: %s !important' % t['fill'])
    rule('.th %s' % bg('rgba(118, 118, 128, 0.08)'), 'background: %s !important' % t['fill'])
    # Fades behind the tab bar and toolbars.
    for src, stop in [('255, 255, 255', '72%'), ('242, 242, 247', '72%'), ('255, 255, 255', '70%')]:
        rule('.th [style*="rgba(%s, 0.94) %s"]' % (src, stop), 'background: linear-gradient(rgba(%s, 0), rgba(%s, 0.94) %s) !important' % (t['rgb'], t['rgb'], stop))
    # Text.
    for v in ['rgb(0, 0, 0)', 'rgb(28, 28, 30)']: rule('.th %s' % fg(v), 'color: %s !important' % t['ink'])
    rule('.th %s' % fg('rgb(58, 58, 60)'), 'color: %s !important' % t['ink3'])
    for v in ['rgb(108, 108, 112)', 'rgb(142, 142, 147)']: rule('.th %s' % fg(v), 'color: %s !important' % t['ink2'])
    for v in ['rgb(174, 174, 178)', 'rgb(199, 199, 204)']: rule('.th %s' % fg(v), 'color: %s !important' % t['faint'])
    rule('.th %s' % fg('rgb(153, 0, 0)'), 'color: %s !important' % t['link'])
    rule('.th a:not([style*="color"])', 'color: %s !important' % t['link'])
    # The reader's paper.
    rule('.th %s' % bg('rgb(250, 247, 240)'), 'background: %s !important' % t['page'])
    for v in ['rgba(255, 253, 248, 0.9)', 'rgba(255, 253, 248, 0.72)']:
        rule('.th %s' % bg(v), 'background: %s !important' % t['paperGlass'])
    for d, stop in [('to top, ', '60%'), ('', '65%')]:
        rule('.th [style*="background: linear-gradient(%srgba(250, 247, 240, 0), rgba(250, 247, 240, 0.95) %s)"]' % (d, stop), 'background: linear-gradient(%srgba(%s, 0), rgba(%s, 0.95) %s) !important' % (d, t['rgb'], t['rgb'], stop))
    rule('.th %s' % bg('rgba(31, 27, 22, 0.14)'), 'background: %s !important' % t['track'])
    rule('.th %s' % bg('rgba(60, 40, 10, 0.07)'), 'background: %s !important' % t['paperFill'])
    rule('.th %s' % fg('rgb(31, 27, 22)'), 'color: %s !important' % t['pageInk'])
    rule('.th %s' % fg('rgb(107, 100, 90)'), 'color: %s !important' % t['pageInk2'])
    # Drawn strokes and fills.
    rule('.th [stroke="#C7C7CC"]', 'stroke: %s' % t['chev'])
    for v in ['#6C6C70', '#8E8E93', '#AEAEB2']:
        rule('.th [stroke="%s"]' % v, 'stroke: %s' % t['ink2'])
        rule('.th [fill="%s"]' % v, 'fill: %s' % t['ink2'])
    rule('.th [stroke="#1C1C1E"]', 'stroke: %s' % t['ink'])
    rule('.th [stroke="#990000"]', 'stroke: %s' % t['link'])
    return '\n'.join(R)

def write_skin(name, t):
    src = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{name} skin (component)</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
{skin(t)}
</style>
</helmet>
<span hidden></span>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":10,"height":10}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''
    open(os.path.join(OUT, 'Skin-%s.dc.html' % name), 'w').write(src)

def write_variant(theme, board, h, title):
    base = board[:-len('.dc.html')]
    src = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{theme} · {title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div class="th" style="width: 390px; height: {h}px; position: relative; overflow: hidden">
  <dc-import name="Skin-{theme}" hint-size="0px,0px"></dc-import>
  <dc-import name="{base}" hint-size="390px,{h}px"></dc-import>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''
    open(os.path.join(OUT, '%s-%s' % (theme, board)), 'w').write(src)

if __name__ == '__main__':
    canvas_path = os.path.join(OUT, 'canvas.json')
    c = json.load(open(canvas_path))
    pages = ['iphone', 'subscreens', 'insights']
    src = {p: {k: v for k, v in c['boards'].items() if v.get('page') == p and v['w'] == 390 and not k.startswith(tuple(t + '-' for t in THEMES))} for p in pages}
    for name, t in THEMES.items():
        write_skin(name, t)
    # Stack the three pages: iPhone rows, then Subscreens, then Insights.
    offset, y0 = {}, 0
    for p in pages:
        if not src[p]: continue
        top = min(v['y'] for v in src[p].values())
        offset[p] = y0 - top
        y0 += max(v['y'] + v['h'] for v in src[p].values()) - top + 600
    n = 0
    section = {'iphone': 'iPhone screens', 'subscreens': 'Subscreens', 'insights': 'Reading Insights'}
    for name in THEMES:
        for p in pages:
            if p not in offset: continue
            top = min(v['y'] for v in src[p].values()) + offset[p]
            key = 'theme%s%s' % (name, p.capitalize())
            c['notes'][key] = {'x': 0, 'y': top - 260, 'text': '%s · %s' % (name, section[p]), 'kind': 'title1', 'page': 'theme-' + name.lower(), 'maxW': 6500}
            if key not in c['noteOrder']: c['noteOrder'].append(key)
        pid = 'theme-' + name.lower()
        if not any(p['id'] == pid for p in c['pages']):
            c['pages'].append({'id': pid, 'name': name})
        for p in pages:
            for board, v in src[p].items():
                write_variant(name, board, v['h'], v.get('title', board))
                key = '%s-%s' % (name, board)
                c['boards'][key] = {'h': v['h'], 'page': pid, 'title': '%s · %s' % (name, v.get('title', board)), 'w': 390, 'x': v['x'], 'y': v['y'] + offset[p]}
                if key not in c['order']: c['order'].append(key)
                n += 1
    json.dump(c, open(canvas_path, 'w'), ensure_ascii=False, indent=2)
    print(n, 'variant boards')
