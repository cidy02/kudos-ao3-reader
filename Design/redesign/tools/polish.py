"""Polish pass for the plainer subscreens (owner, 2026-10-29: "bring these subscreens to the
level of polish of the rest of the app").

Each entry adds what the richer boards already have: a card for the thing being edited
(`context`), a figures strip where counts matter (`stats`), Settings-style symbol tiles on
rows (`tiles`, matched by row label; never on rows that already lead with something),
generated covers on work rows (`covers`), and include/exclude colours on chips (`tones`).
`drop` lists attrs the context card replaces (usually the subtitle). The generators call
polish() in their add(), so base data stays where it was.
"""
from data import I

art = lambda h: 'linear-gradient(155deg, hsl(%d, 46%%, 27%%), hsl(%d, 50%%, 41%%))' % (h, (h + 22) % 360)
ink = lambda h: 'hsl(%d, 56%%, 33%%)' % h
OW, PER, PP, NA, SH, HP = 188, 335, 150, 290, 32, 44

P = {
    'disk': 'M4 7h16v10H4zM4 12h16M8 9.5h.01',
    'pin': 'M14 4l6 6M15.5 5.5 11 10l-4-1-2 2 8 8 2-2-1-4 4.5-4.5M9 15l-5 5',
    'collection': 'M6 8h12v12H6zM8 5h8',
    'search': 'M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.5 15.5l5 5',
    'home': 'M3.5 10.5 12 3.5l8.5 7M5.5 9v11h5v-6h3v6h5V9',
    'cellular': 'M5 18v-3M9.5 18v-6M14 18V9M18.5 18V6',
    'shelves': 'M4 5h4v14H4zM10 5h4v14h-4zM16.2 6l3.2-.8 2.4 13-3.2.8z',
    'sort': 'M7 4v16M3.5 16.5 7 20l3.5-3.5M17 20V4M13.5 7.5 17 4l3.5 3.5',
    'trash': 'M5 7h14M10 4h4M7 7l1 13h8l1-13',
    'shieldcheck': 'M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6zM9 12l2 2 4-4',
    'shield': 'M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z',
    'rebuild': 'M4 12a8 8 0 0 1 13.7-5.6L20 9M20 4v5h-5M20 12a8 8 0 0 1-13.7 5.6L4 15M4 20v-5h5',
    'eyeoff': 'M3 3l18 18M10.6 6.1A9.8 9.8 0 0 1 12 6c5 0 8.5 4.5 9.5 6-.4.7-1.3 1.9-2.6 3.1M6.6 7.6C4.6 8.9 3.2 10.8 2.5 12c1 1.5 4.5 6 9.5 6 1.6 0 3-.4 4.3-1.1',
    'blur': 'M4 4h16v16H4zM8 8h.01M12 8h.01M16 8h.01M8 12h.01M12 12h.01M16 12h.01M8 16h.01M12 16h.01M16 16h.01',
    'faceid': 'M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3M9 9.5v1M15 9.5v1M12 9.5v3.5h-1M9.5 15.5c1.5 1 3.5 1 5 0',
    'prefs': 'M4 7h10M18 7h2M4 17h4M12 17h8M14 4v6M8 14v6',
    'code': 'M8 6l-5 6 5 6M16 6l5 6-5 6',
    'info': 'M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17zM12 11v5.5M12 7.8v.1',
    'calendar': 'M5 6h14v14H5zM5 10h14M9 3.5v4M15 3.5v4',
    'bell': 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5h4',
    'paint': 'M12 3a9 9 0 1 0 0 18c1 0 1.5-.8 1.5-1.6 0-1.4-1.4-1.6-1.4-2.9 0-1 .8-1.5 1.9-1.5h2.5A4.5 4.5 0 0 0 21 10.5C21 6.4 17 3 12 3zM7.5 12h.01M9.5 8h.01M14.5 8h.01',
    'title': 'M5 6h14M12 6v13M9 19h6',
    'warn': 'M12 4 2.8 19.5h18.4zM12 10v4.5M12 17.2v.1',
    'wave': 'M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2',
    'mail': 'M4 6h16v12H4zM4 7l8 6 8-6',
}
BLUE, GREEN, ORANGE, PURPLE, GREY, INDIGO, PINK, YELLOW, TEAL = '#1E63C8', '#2F8F3A', '#E07000', '#7B3FA0', '#8E8E93', '#5856D6', '#B3127A', '#E0A100', '#2F6D6A'
RED = '#821019'

POLISH = {
    'Queue-Edit': {
        'context': {'kicker': 'Queue · 8 works', 'kickerColour': '#C25E00', 'title': 'Summer Reading', 'meta': 'About 9 h 40 min · 2 finished · 6 offline', 'tile': '#C25E00', 'icon': I['queue']},
        'tiles': {'Keep works offline': (INDIGO, I['down']), 'Storage': (GREY, P['disk'])},
    },
    'Queue-Tags': {
        'stats': [{'n': '5', 'label': 'Tags'}, {'n': '3', 'label': 'Queues tagged'}, {'n': '1', 'label': 'Unused'}],
        'tiles': {l: (GREY, I['tag']) for l in ['fluff', 'under 20k', 'comfort', 'rereads', 'long haul']},
    },
    'Collection-New': {
        'context': {'kicker': 'New collection', 'kickerColour': BLUE, 'title': 'Untitled collection', 'meta': 'No works yet · only in Kudos', 'tile': BLUE, 'icon': P['collection']},
        'tiles': {'Add Works…': (BLUE, I['all'])},
    },
    'Collection-AddWorks': {
        'context': {'kicker': 'Collection · 12 works', 'kickerColour': '#9C2F6B', 'title': 'Austen Variations', 'meta': 'Adding 2 · 1 is already in it', 'tile': '#9C2F6B', 'icon': P['collection']},
        'drop': ['subtitle'],
        'covers': {'A Map of Small Hours': PP, 'Letters Never Sent': PER, 'Half Agony, Half Hope': PER, 'Northanger Nights': NA, 'Five Times Elizabeth Laughed': PP, 'The Bath Letters': PER},
    },
    'Collection-Reorder': {
        'context': {'kicker': 'Collection · 12 works', 'kickerColour': '#9C2F6B', 'title': 'Austen Variations', 'meta': 'Drag to set the reading order', 'tile': '#9C2F6B', 'icon': P['collection']},
        'drop': ['subtitle'],
        'covers': {'A Map of Small Hours': PP, 'Northanger Nights': NA, 'Letters Never Sent': PER, 'Half Agony, Half Hope': PER, 'Five Times Elizabeth Laughed': PP, 'The Bath Letters': PER, 'A Fortnight at Uppercross': PER},
    },
    'Bookmark-Edit': {
        'context': {'kicker': 'Pride and Prejudice', 'kickerColour': ink(PP), 'title': 'A Map of Small Hours', 'meta': 'quietharbor · 18,420 words · 6/6', 'cover': art(PP)},
        'drop': ['subtitle'],
        'tiles': {'Collections': ('#9C2F6B', P['collection']), 'Private': (GREY, I['lock']), 'Rec': (YELLOW, I['star'])},
    },
    'Search-Save': {
        'context': {'kicker': 'AO3 search · 1,284 works', 'kickerColour': RED, 'title': 'Persuasion · Anne/Wentworth', 'meta': 'Complete only · sorted by kudos', 'tile': RED, 'icon': P['search']},
        'tiles': {'Show new results on Home': (BLUE, P['home'])},
        'tones': {'Persuasion': 'in', 'Anne/Wentworth': 'in'},
    },
    'Inbox-Filter': {
        'tiles': {'All works': (GREY, I['all'])},
        'covers': {'Keeper of the Northern Light': OW, 'Lantern Season': 203, 'What the Tide Keeps': 176},
    },
    'Filter-Tags': {
        'tones': {'Slow Burn': 'in', 'Epistolary': 'in', 'Major Character Death': 'out'},
        'tiles': {l: (GREY, I['tag']) for l in ['Fluff', 'Fluff and Angst', 'Tooth-Rotting Fluff', 'Domestic Fluff']},
    },
    'Settings-Library': {
        'tiles': {'Open straight into the reader': (BLUE, I['reading']), 'Ask before downloading on cellular': (GREEN, P['cellular']),
                  'Edit Shelves': ('#C25E00', P['shelves']), 'Default sort': (BLUE, P['sort']), 'Keep deleted works for': (GREY, P['trash'])},
    },
    'Settings-Preservation': {
        'tiles': {'Keep a copy of every saved work': (GREEN, P['shieldcheck']), 'Check what’s still on AO3': (BLUE, I['globe']),
                  'Keep imported original files': (PURPLE, I['doc']), 'Rebuild works from originals': (ORANGE, P['rebuild']),
                  'Ask to save the whole series': (BLUE, I['series'])},
    },
    'Settings-Queues': {
        'tiles': {'Manage Tags': (GREY, I['tag'])},
    },
    'Settings-Account': {
        'tiles': {'AO3 Preferences': (GREY, P['prefs']), 'Hide mature content': (ORANGE, P['eyeoff']), 'Blur covers of Mature and Explicit': (INDIGO, P['blur']),
                  'Require Face ID to reveal': (GREEN, P['faceid']), 'Privacy and Local Data': (BLUE, P['shield'])},
    },
    'Legal-Notices': {
        'tiles': dict([('Kudos', (RED, I['heart']))] + [(l, (GREY, P['code'])) for l in ['Readium Swift Toolkit', 'SwiftSoup', 'FluidAudio', 'Kokoro TTS voices', 'MuPDF', 'Literata typeface (Android)']] + [('Not affiliated with the OTW', (BLUE, P['info']))]),
    },
    'Downloaded-Date': {
        'context': {'kicker': 'Imported · PDF', 'kickerColour': ink(HP), 'title': 'The Boy Who Lived Twice', 'meta': 'From FanFiction.net · Harry Potter', 'cover': art(HP)},
        'drop': ['subtitle'],
        'tiles': {'Date': (ORANGE, P['calendar']), 'Time': (ORANGE, I['clock'])},
    },
    'Local-Destination': {
        'context': {'kicker': 'PDF · 1.8 MB', 'kickerColour': PURPLE, 'title': 'The Boy Who Lived Twice', 'meta': 'The Boy Who Lived Twice.pdf · imported just now', 'tile': PURPLE, 'icon': I['doc']},
        'drop': ['subtitle'],
        'tiles': {'Library only': (GREY, I['all']), 'Want to Read': (BLUE, I['book']), 'A Queue…': ('#C25E00', I['queue']), 'A Collection…': ('#9C2F6B', P['collection']),
                  'Source': (BLUE, I['globe']), 'Fandom': (GREY, I['tag']), 'Rating': (YELLOW, P['shield'])},
    },
    'Reader-PageJump': {
        'context': {'kicker': 'The Cartographer’s Daughter', 'kickerColour': ink(OW), 'title': 'Chapter 7 · The Salt Road', 'meta': 'Page 4 of 18 · 21 min left in the chapter', 'cover': art(OW)},
        'drop': ['subtitle'],
    },
    'Reader-Pronunciation': {
        'context': {'kicker': 'Read Aloud · Persuasion', 'kickerColour': ink(PER), 'title': 'Letters Never Sent', 'meta': 'marginalia · 21,880 words', 'cover': art(PER)},
        'tiles': {l: (INDIGO, P['wave']) for l in ['Wentworth', 'Uppercross', 'AU', 'POV', 'Mx.']},
    },
    'AO3-Preferences': {
        'tiles': {'Show adult content without asking': (ORANGE, I['eye']), 'Hide warnings': (ORANGE, P['warn']), 'Hide additional tags': (GREY, I['tag']),
                  'Show whole work by default': (BLUE, I['reading']), 'Time zone': (INDIGO, I['globe']), 'Skin': (PURPLE, P['paint']),
                  'Browser title': (GREY, P['title']), 'Comments on your works': (GREEN, I['chat']), 'Kudos on your works': (RED, I['heart']),
                  'Subscription updates': ('#C25E00', P['bell']), 'Gift notifications': (PINK, I['gift']),
                  'Allow others to invite your works to collections': (TEAL, P['collection']), 'Hide your email': (GREY, P['mail'])},
    },
}

LEADS = ('tile', 'icon', 'cover', 'avatar', 'dot', 'edit', 'handle')


def polish(name, attrs, data):
    p = POLISH.get(name)
    if not p:
        return attrs, data
    attrs = {k: v for k, v in attrs.items() if k not in p.get('drop', [])}
    data = dict(data)
    for key in ('context', 'stats'):
        if key in p:
            data[key] = p[key]
    tiles, covers, tones = p.get('tiles', {}), p.get('covers', {}), p.get('tones', {})
    sections = []
    for s in data.get('sections', []):
        rows = []
        for r in s.get('rows', []):
            r = dict(r)
            label = r.get('label', '')
            if not any(r.get(k) for k in LEADS):
                if label in tiles:
                    r['tile'], r['icon'] = tiles[label]
                elif label in covers:
                    r['cover'] = art(covers[label])
            if r.get('kind') == 'chips' and tones:
                r['chips'] = [{'label': c, 'tone': tones[c]} if isinstance(c, str) and c in tones else c for c in r.get('chips', [])]
            rows.append(r)
        sections.append({**s, 'rows': rows})
    if sections:
        data['sections'] = sections
    return attrs, data
