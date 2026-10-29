"""Reader Response sheet (Quality Signals page).

Why a ranked search result sits where it does: the work's kudos per hit beside
works of the same shape, how sure the figure is, and the other signals. The
numbers are one worked example (Keeper of the Northern Light, the Search board's
first result); the method is in notes/quality-signals-spec.md.
"""
import sys; sys.path.insert(0, '.')
from gen import board
from data import I

art = lambda h: 'linear-gradient(155deg, hsl(%d, 46%%, 27%%), hsl(%d, 50%%, 41%%))' % (h, (h + 22) % 360)
OW = 188
GREEN = {'badgeBg': '#E3F1E6', 'badgeFg': '#1E6B34'}

# 1,804 kudos / 19,200 hits = 9.4%; similar works 3.9%.
# Shrunk estimate (1,804 + 20) / (19,200 x 0.039 + 20) = 2.37x; cautious x exp(-1.28 / sqrt(1,824)) = 2.30x.
board('Quality-Response', 'Work › Reader Response (sheet)', 'FormScreen', {'title': 'Reader Response', 'mode': 'sheet'}, {
 'context': {'kicker': 'Hidden Gems · 1st of 40 loaded', 'kickerColour': '#990000', 'title': 'Keeper of the Northern Light',
             'meta': 'saltwindow · 22,410 words · 7/7 · complete', 'cover': art(OW)},
 'stats': [{'n': '2.4×', 'label': 'Kudos per hit vs similar', 'colour': '#990000'}, {'n': '1,804', 'label': 'Kudos'},
           {'n': '19.2k', 'label': 'Hits'}, {'n': '26%', 'label': 'Saved'}],
 'sections': [
  {'header': 'Kudos per Hit', 'rows': [
   {'label': 'This work', 'sub': '1,804 kudos ÷ 19,200 hits', 'detail': '9.4%', 'kind': 'info', 'bar': 100, 'barColour': '#990000'},
   {'label': 'Similar works', 'sub': '6 to 10 chapters · 15,000 to 30,000 words · complete · posted 2026', 'detail': '3.9%', 'kind': 'info', 'bar': 41, 'barColour': '#AEAEB2'}],
   'footer': 'AO3 counts one hit per reader per day, so long and serialized works collect more hits for each reader. Similar works share this one’s length, chapters, status and year.'},
  {'header': 'How Sure', 'rows': [
   {'label': 'Confidence', 'sub': 'Thousands of readers; the figure is unlikely to move much', 'badge': 'Steady', 'kind': 'info', **GREEN},
   {'label': 'Cautious estimate', 'sub': 'What the ranking uses', 'detail': '2.3×', 'kind': 'info'}]},
  {'header': 'Other Signals', 'rows': [
   {'label': 'Saves per kudos', 'sub': 'Similar works 14% · public bookmarks only', 'detail': '26%', 'kind': 'info'},
   {'label': 'Comments per kudos', 'sub': 'Similar works 3.0% · replies included', 'detail': '4.1%', 'kind': 'info'},
   {'label': 'Momentum', 'sub': 'Since you last saw it, 9 days ago', 'detail': '+46 kudos', 'kind': 'info'}]},
  {'header': 'Dates', 'rows': [
   {'label': 'Posted', 'sub': 'Estimated from the work’s number on AO3', 'detail': 'About Mar 2026', 'kind': 'info'},
   {'label': 'Last chapter', 'detail': 'Oct 12', 'kind': 'info'}]},
  {'rows': [{'label': 'How Reader Response Works', 'kind': 'nav', 'icon': I['help'], 'iconColour': '#990000'}]}]}, 1240)
print('1 board')
