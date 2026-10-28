"""Posting, collection and challenge screens (Subscreens page, rows 3 and 4).

Each screen leads with what it is about (the work being posted, the series, the
collection or the challenge) and carries the figures AO3 shows for it; moderation
and claiming happen on the row.
"""
import sys; sys.path.insert(0, '.')
from gen import board
from data import I
B = []
def add(name, title, comp, attrs, data, h=844): board(name, title, comp, attrs, data, h); B.append((name, title, h))

art = lambda h: 'linear-gradient(155deg, hsl(%d, 46%%, 27%%), hsl(%d, 50%%, 41%%))' % (h, (h + 22) % 360)
ink = lambda h: 'hsl(%d, 56%%, 33%%)' % h
OW, PER, PP, SH, SS = 188, 335, 150, 32, 262
AMBER = {'badgeBg': '#FFF4E5', 'badgeFg': '#6B3A00'}
GREY = {'badgeBg': '#EFEFF4', 'badgeFg': '#3A3A3C'}
BLUE = {'badgeBg': '#E5EEFB', 'badgeFg': '#1E4E9A'}
ship = lambda t: {'label': t, 'bg': 'rgba(153,0,0,0.10)', 'fg': '#990000'}

# What each screen is about
NEW = {'kicker': 'Original Work · new work', 'kickerColour': ink(OW), 'title': 'Untitled lighthouse piece', 'meta': '3,240 words · 1 chapter · not posted yet', 'cover': art(OW)}
TIDE = {'kicker': 'Original Work · work in progress', 'kickerColour': ink(OW), 'title': 'What the Tide Keeps', 'meta': '3 of 8 chapters posted · 9,800 words · 412 kudos', 'cover': art(OW)}
LANTERN = {'kicker': 'Original Work · series', 'kickerColour': '#1E63C8', 'title': 'Lantern Season', 'meta': '3 parts · 47,260 words · updated Oct 20', 'tile': '#1E63C8', 'icon': I['series']}
WEEK = {'kicker': 'Collection · moderated', 'kickerColour': '#2F6D6A', 'title': 'Lighthouse Week 2026', 'meta': 'Open until Nov 7 · you own it', 'tile': '#2F6D6A', 'icon': 'M6 8h12v12H6zM8 5h8'}
EXCH = {'kicker': 'Gift exchange · moderated', 'kickerColour': '#7B3FA0', 'title': 'Austen Exchange 2026', 'meta': 'Sign-ups close Nov 1 · works due Nov 12', 'tile': '#7B3FA0', 'icon': I['gift']}
MEME = {'kicker': 'Prompt meme · Persuasion', 'kickerColour': '#7B3FA0', 'title': 'Persuasion Prompt Meme', 'meta': 'Open for prompts until Dec 31', 'tile': '#7B3FA0', 'icon': I['chat']}
stats = lambda *pairs: [{'n': n, 'label': l, **({'colour': c} if c else {})} for n, l, c in [(p + (None,))[:3] for p in pairs]]

# Posting a work
add('Post-Tags', 'Post a work › Tags', 'FormScreen', {'title': 'Tags', 'back': 'Back to Post', 'search': 'Add a tag'}, {
 'context': NEW,
 'sections': [
  {'header': 'Fandoms · required', 'rows': [{'label': 'Fandoms', 'kind': 'chips', 'chips': ['Original Work']}]},
  {'header': 'Relationships', 'rows': [{'label': 'Relationships', 'kind': 'chips', 'chips': ['Original Female Character/Original Female Character']}]},
  {'header': 'Characters', 'rows': [{'label': 'Characters', 'kind': 'chips', 'chips': ['Original Characters', 'Lighthouse Keeper']}]},
  {'header': 'Additional tags', 'rows': [{'label': 'Tags', 'kind': 'chips', 'chips': ['Lighthouses', 'Slow Burn', 'Found Family']}]},
  {'header': 'Suggestions for “light”', 'rows': [
   {'label': 'Lighthouse Keepers', 'sub': '2,904 works', 'meta': 'Canonical tag', 'kind': 'nav'},
   {'label': 'Lighthouses', 'sub': '6,120 works', 'meta': 'Added', 'metaColour': '#990000', 'kind': 'check', 'on': True},
   {'label': 'Light Angst', 'sub': '98k works', 'meta': 'Canonical tag', 'kind': 'nav'}]},
  {'header': 'Tags you often use', 'rows': [
   {'label': 'Weather as Metaphor', 'sub': 'On 3 of your works', 'kind': 'circle'},
   {'label': 'Epistolary', 'sub': 'On 2 of your works', 'kind': 'circle'},
   {'label': 'Quiet Romance', 'sub': 'On 2 of your works', 'kind': 'circle'}]}]}, 1300)
add('Post-Creators', 'Post a work › Co-creators', 'FormScreen', {'title': 'Creators', 'back': 'Back to Post', 'search': 'Invite a co-creator by name'}, {
 'context': NEW,
 'sections': [
  {'header': 'Creators', 'rows': [
   {'label': 'saltwindow', 'sub': 'You · this pseud', 'kind': 'check', 'on': True, 'avatar': True, 'tile': '#23506B'},
   {'label': 'tidewright', 'sub': 'Invited Oct 27', 'meta': 'Shows once they accept on AO3', 'kind': 'info', 'avatar': True, 'tile': '#2F6D6A', 'badge': 'Invited', **GREY}]},
  {'header': 'People you’ve written with', 'rows': [
   {'label': 'quietharbor', 'sub': 'Co-created Small Weathers · 2025', 'kind': 'info', 'avatar': True, 'tile': '#3E5B3A', 'badge': 'Invite', 'badgeBg': 'rgba(153,0,0,0.10)', 'badgeFg': '#990000'},
   {'label': 'anne_at_lyme', 'sub': 'Beta-read Lantern Season', 'kind': 'info', 'avatar': True, 'tile': '#6B4E23', 'badge': 'Invite', 'badgeBg': 'rgba(153,0,0,0.10)', 'badgeFg': '#990000'}]},
  {'rows': [{'label': 'Post under another pseud', 'kind': 'nav', 'detail': 'saltwindow'}]}]}, 844)
add('Post-Series', 'Post a work › Series', 'FormScreen', {'title': 'Series', 'back': 'Back to Post'}, {
 'context': NEW,
 'sections': [
  {'header': 'Add to a series', 'rows': [
   {'label': 'None', 'kind': 'check'},
   {'label': 'Lantern Season', 'sub': '3 parts · 47,260 words', 'meta': 'Becomes part 4', 'metaColour': '#990000', 'kind': 'check', 'on': True, 'tile': '#1E63C8', 'icon': I['series']},
   {'label': 'Small Weathers', 'sub': 'Persuasion · 2 parts · 7,120 words', 'kind': 'check', 'tile': '#9C2F6B', 'icon': I['series']}]},
  {'header': 'Lantern Season after posting', 'rows': [
   {'label': '1. Keeper of the Northern Light', 'sub': '22,410 words · complete', 'kind': 'info', 'cover': art(OW)},
   {'label': '2. Lantern Season', 'sub': '15,050 words · complete', 'kind': 'info', 'cover': art(203)},
   {'label': '3. What the Tide Keeps', 'sub': '9,800 words · 3/8', 'kind': 'info', 'cover': art(176)},
   {'label': '4. Untitled lighthouse piece', 'sub': '3,240 words', 'meta': 'This work', 'metaColour': '#990000', 'kind': 'info', 'cover': art(OW)}]},
  {'rows': [{'label': 'New Series…', 'kind': 'button'}]}]}, 940)
add('Post-Parent', 'Post a work › Inspired by', 'FormScreen', {'title': 'Inspired By', 'back': 'Back to Post'}, {
 'context': NEW,
 'sections': [
  {'header': 'Parent works', 'rows': [
   {'label': 'The Lighthouse Keepers', 'sub': 'tidewright · Original Work · 40,900 words', 'meta': 'Found on AO3', 'metaColour': '#2F8F3A', 'kind': 'check', 'on': True, 'cover': art(OW)},
   {'label': 'AO3 link', 'kind': 'field', 'placeholder': 'archiveofourown.org/works/…'}],
   'footer': 'AO3 tells the parent’s creator, unless they turned that off.'},
  {'header': 'From your reading', 'rows': [
   {'label': 'Salt & Starlight', 'sub': 'wrenfield · Original Work · read this month', 'kind': 'circle', 'cover': art(196)},
   {'label': 'Under the Same Stars', 'sub': 'wrenfield · Original Work · finished Oct 19', 'kind': 'circle', 'cover': art(240)}]},
  {'header': 'Not on AO3', 'rows': [
   {'label': 'Title', 'kind': 'field', 'placeholder': 'Title'},
   {'label': 'Link', 'kind': 'field', 'placeholder': 'https://'},
   {'label': 'Translation of this work', 'kind': 'toggle', 'on': False}]}]}, 900)
add('Post-CollectionsGifts', 'Post a work › Collections and gifts', 'FormScreen', {'title': 'Collections & Gifts', 'back': 'Back to Post'}, {
 'context': NEW,
 'sections': [
  {'header': 'Collections', 'rows': [
   {'label': 'Lighthouse Week 2026', 'sub': 'Moderated · open until Nov 7 · 41 works', 'kind': 'check', 'on': True, 'tile': '#2F6D6A', 'icon': 'M6 8h12v12H6zM8 5h8', 'badge': 'Needs approval', **AMBER},
   {'label': 'Original Work Fortnight', 'sub': 'Open · 312 works', 'kind': 'circle', 'tile': '#C25E00', 'icon': 'M6 8h12v12H6zM8 5h8'},
   {'label': 'Add a Collection…', 'kind': 'button'}]},
  {'header': 'Challenge', 'rows': [
   {'label': 'For your assignment', 'sub': 'Austen Exchange 2026 · for quietharbor', 'meta': 'Due Nov 12', 'metaColour': '#C25E00', 'kind': 'circle', 'tile': '#7B3FA0', 'icon': I['gift']}]},
  {'header': 'Gift for', 'rows': [
   {'label': 'quietharbor', 'sub': 'On AO3', 'kind': 'check', 'on': True, 'avatar': True, 'tile': '#3E5B3A'},
   {'label': 'Add a Recipient…', 'kind': 'button'}],
   'footer': 'A gift can go to an AO3 user or to a name off AO3.'}]}, 880)
add('Series-Edit', 'Writing › Edit Series', 'FormScreen', {'title': 'Edit Series', 'back': 'Back', 'confirm': 'Save'}, {
 'context': LANTERN,
 'stats': stats(('3', 'Parts'), ('47.3k', 'Words'), ('1,712', 'Kudos'), ('48', 'Subscribers')),
 'sections': [
  {'header': 'Title', 'rows': [{'kind': 'field', 'text': 'Lantern Season'}]},
  {'header': 'Summary', 'rows': [{'kind': 'textarea', 'text': 'Three keepers, three winters, one light.', 'rows': 2}, {'label': 'Notes', 'kind': 'nav', 'detail': 'None'}]},
  {'header': 'Parts', 'rows': [
   {'label': 'Keeper of the Northern Light', 'sub': 'Part 1 · 22,410 words · complete', 'kind': 'info', 'handle': True, 'cover': art(OW)},
   {'label': 'Lantern Season', 'sub': 'Part 2 · 15,050 words · complete', 'kind': 'info', 'handle': True, 'cover': art(203)},
   {'label': 'What the Tide Keeps', 'sub': 'Part 3 · 9,800 words · 3/8', 'meta': 'Work in progress', 'metaColour': '#C25E00', 'kind': 'info', 'handle': True, 'cover': art(176)}]},
  {'rows': [{'label': 'Complete', 'kind': 'toggle', 'on': False}, {'label': 'Creators', 'kind': 'nav', 'detail': 'saltwindow'}]},
  {'rows': [{'label': 'Delete Series', 'kind': 'destructive'}], 'footer': 'The works stay; only the series goes.'}]}, 1100)
add('Chapter-Add', 'Writing › Add Chapter (form)', 'FormScreen', {'title': 'New Chapter', 'subtitle': 'Chapter 5 of 8', 'mode': 'sheet', 'trailing': 'Post…'}, {
 'context': TIDE,
 'sections': [
  {'rows': [{'label': 'Title', 'kind': 'field', 'placeholder': 'Chapter title (optional)'}, {'label': 'Number', 'kind': 'value', 'detail': '5 of 8'}, {'label': 'Published', 'kind': 'nav', 'detail': 'When posted'}]},
  {'header': 'Text', 'rows': [
   {'label': 'Write Chapter', 'sub': 'Draft · 1,180 words · edited today', 'kind': 'nav', 'icon': I['pen']},
   {'label': 'Import from a File…', 'kind': 'nav', 'icon': I['import']}]},
  {'header': 'Summary', 'rows': [{'kind': 'textarea', 'placeholder': 'Optional', 'rows': 2}]},
  {'header': 'Notes', 'rows': [{'label': 'Beginning notes', 'kind': 'nav', 'detail': 'None'}, {'label': 'End notes', 'kind': 'nav', 'detail': 'None'}]},
  {'rows': [{'label': 'Preview', 'kind': 'button'}, {'label': 'Save as Draft', 'kind': 'button'}]}]}, 1040)
add('Writing-Chapters', 'Writing › a work’s chapters', 'ListScreen', {'title': 'Chapters', 'back': 'Back to Your Works', 'tab': 'writing', 'large': False}, {
 'context': TIDE,
 'stats': stats(('3/8', 'Posted'), ('9,800', 'Words'), ('4,108', 'Hits'), ('63', 'Comment threads')),
 'tools': [{'label': 'Add Chapter', 'icon': 'plus'}, {'label': 'More: Reorder, Edit Work', 'icon': 'more'}],
 'sections': [{'kind': 'rows', 'rows': [
  {'title': '1. Low Water', 'sub': '3,210 words · posted Sep 28', 'meta': '29 comment threads', 'handle': True},
  {'title': '2. The Lamp Room', 'sub': '3,350 words · posted Oct 9', 'meta': '21 comment threads', 'handle': True},
  {'title': '3. Fog Bell', 'sub': '3,240 words · posted Oct 20', 'meta': '13 comment threads · 2 new', 'metaColour': '#990000', 'handle': True},
  {'title': '4. Slack Water', 'sub': '1,240 words · edited yesterday', 'meta': 'Draft on AO3 · deleted Nov 19 unless posted', 'metaColour': '#C25E00', 'handle': True, 'badge': 'Draft', **GREY}]},
  {'header': 'Planned', 'count': '4', 'kind': 'rows', 'rows': [
   {'title': '5. Spring Tide', 'sub': 'Outline only', 'light': True, 'chevron': False},
   {'title': '6–8', 'sub': 'Not started', 'light': True, 'chevron': False}]}]}, 980)
# AO3 collections
add('AO3-Collection-Page', 'AO3 collection page', 'ListScreen', {'title': 'Austen Exchange 2026', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': {**EXCH, 'meta': 'Maintained by elinor_d and 2 others · reveal Dec 1'},
 'stats': stats(('214', 'Works'), ('57', 'Bookmarks'), ('98', 'Participants'), ('7', 'Fandoms')),
 'tools': [{'label': 'Join', 'text': 'Join'}, {'label': 'More: Profile, Rules, Share', 'icon': 'more'}],
 'chips': [{'label': 'Works', 'on': True}, {'label': 'Bookmarks'}, {'label': 'Prompts'}, {'label': 'Participants'}, {'label': 'Profile'}],
 'sections': [{'header': 'Recent', 'count': '214', 'works': [
  {'title': 'A Map of Small Hours', 'author': 'quietharbor', 'fandom': 'Pride and Prejudice', 'rating': 'G', 'category': 'FM', 'warnings': 'none', 'status': 'complete', 'words': '32,050', 'chapters': '9/9', 'kudos': '1,212', 'hits': '15.4k', 'updated': 'Gift for elinor_d · Oct 26', 'summary': 'Elizabeth keeps a ledger of the hours she cannot sleep at Pemberley.'},
  {'title': 'Letters Never Sent', 'author': 'marginalia', 'fandom': 'Persuasion', 'rating': 'T', 'category': 'FM', 'warnings': 'none', 'status': 'complete', 'words': '21,880', 'chapters': '4/4', 'kudos': '1,530', 'hits': '17.0k', 'updated': 'Gift for lizzy_reads · Oct 25', 'summary': 'Anne writes to Wentworth every year on the same date, and never sends a single letter.'},
  {'title': 'The Bath Letters', 'author': 'anne_at_lyme', 'fandom': 'Persuasion', 'rating': 'G', 'category': 'Gen', 'warnings': 'none', 'status': 'complete', 'words': '6,400', 'chapters': '1/1', 'kudos': '388', 'hits': '3.9k', 'updated': 'Gift for quietharbor · Oct 24', 'summary': 'Mrs Smith reads the post aloud, and edits as she goes.'}], 'summary': True}]}, 1040)
add('AO3-Collection-Items', 'AO3 collections › Your items', 'ListScreen', {'title': 'Your Items', 'subtitle': '5 works and bookmarks in 3 collections', 'back': 'Back', 'tab': 'writing'}, {
 'stats': stats(('2', 'Awaiting you', '#C25E00'), ('1', 'With moderators'), ('2', 'Approved')),
 'chips': [{'label': 'All', 'on': True}, {'label': 'Awaiting 2'}, {'label': 'Approved 2'}, {'label': 'Rejected'}],
 'sections': [
  {'header': 'Awaiting you', 'count': '2', 'kind': 'rows', 'rows': [
   {'title': 'Small Weathers', 'kicker': 'Persuasion Prompt Meme', 'kickerColour': '#7B3FA0', 'sub': 'A maintainer invited it · Oct 24', 'cover': art(PER), 'buttons': [{'label': 'Approve', 'primary': True}, {'label': 'Decline'}]},
   {'title': 'Lantern Season', 'kicker': 'Original Work Fortnight', 'kickerColour': '#C25E00', 'sub': 'A maintainer invited it · Oct 22', 'cover': art(203), 'buttons': [{'label': 'Approve', 'primary': True}, {'label': 'Decline'}]}]},
  {'header': 'With moderators', 'count': '1', 'kind': 'rows', 'rows': [
   {'title': 'Keeper of the Northern Light', 'kicker': 'Lighthouse Week 2026', 'kickerColour': '#2F6D6A', 'sub': 'You submitted it · Oct 26', 'cover': art(OW), 'badge': 'Waiting', **GREY}]}]}, 844)
add('AO3-Collection-Form', 'AO3 collections › New or edit (form)', 'FormScreen', {'title': 'New Collection', 'subtitle': 'On AO3', 'mode': 'sheet', 'confirm': 'Create'}, {
 'context': {**WEEK, 'kicker': 'Preview', 'meta': 'archiveofourown.org/collections/lighthouse_week_2026'},
 'sections': [
  {'header': 'Names', 'rows': [{'label': 'Name', 'kind': 'field', 'text': 'lighthouse_week_2026'}, {'label': 'Title', 'kind': 'field', 'text': 'Lighthouse Week 2026'}], 'footer': 'The name is the address on AO3: letters, digits and underscores.'},
  {'header': 'About', 'rows': [{'kind': 'textarea', 'text': 'A week of lighthouses, keepers and the sea. Any fandom, any rating.', 'rows': 2}, {'label': 'Icon', 'kind': 'nav', 'detail': 'None', 'tile': '#2F6D6A', 'icon': 'M6 8h12v12H6zM8 5h8'}, {'label': 'Parent collection', 'kind': 'nav', 'detail': 'None'}, {'label': 'Contact email', 'kind': 'field', 'placeholder': 'Shown to members'}]},
  {'header': 'Settings', 'rows': [{'label': 'Moderated', 'kind': 'toggle', 'on': True, 'sub': 'You approve every work and bookmark'}, {'label': 'Closed', 'kind': 'toggle', 'on': False, 'sub': 'Nothing new can be added'}, {'label': 'Unrevealed', 'kind': 'toggle', 'on': False, 'sub': 'Works stay hidden until you reveal them'}, {'label': 'Anonymous', 'kind': 'toggle', 'on': False, 'sub': 'Creators stay hidden until you reveal them'}]},
  {'header': 'Type', 'rows': [{'label': 'Challenge', 'kind': 'segments', 'options': ['None', 'Gift exchange', 'Prompt meme'], 'selected': 0}]}]}, 1160)
add('AO3-Collection-Moderation', 'AO3 collections › Moderation', 'ListScreen', {'title': 'Moderation', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': WEEK,
 'stats': stats(('3', 'Waiting', '#C25E00'), ('41', 'Approved'), ('2', 'Rejected')),
 'chips': [{'label': 'Waiting 3', 'on': True}, {'label': 'Approved 41'}, {'label': 'Rejected 2'}],
 'sections': [{'kind': 'rows', 'rows': [
  {'title': 'Fog Signal', 'kicker': 'Original Work · T', 'kickerColour': ink(OW), 'sub': 'tidewright · 1,380 words · submitted 2 h ago', 'tags': [ship('Lighthouse Keeper/Original Character'), 'Fog', 'Hurt/Comfort'], 'cover': art(OW), 'buttons': [{'label': 'Approve', 'primary': True}, {'label': 'Reject', 'destructive': True}]},
  {'title': 'The Keeper’s Daughter', 'kicker': 'Original Work · G', 'kickerColour': ink(OW), 'sub': 'inkwell_moth · 4,700 words · yesterday', 'tags': ['Gen', 'Coming of Age', 'Lighthouses'], 'cover': art(214), 'buttons': [{'label': 'Approve', 'primary': True}, {'label': 'Reject', 'destructive': True}]},
  {'title': 'Bookmark of Salt & Starlight', 'kicker': 'Bookmark', 'kickerColour': '#6C6C70', 'sub': 'marginalia · Oct 25', 'meta': '“The lighthouse chapter is the whole reason I read this.”', 'cover': art(196), 'buttons': [{'label': 'Approve', 'primary': True}, {'label': 'Reject', 'destructive': True}]}]}]}, 960)
add('AO3-Collection-Maintainers', 'AO3 collections › Maintainers', 'ListScreen', {'title': 'Maintainers', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': WEEK,
 'stats': stats(('3', 'Maintainers'), ('41', 'Members'), ('44', 'Works')),
 'tools': [{'label': 'Invite', 'icon': 'plus'}],
 'sections': [
  {'header': 'Maintainers', 'count': '3', 'kind': 'rows', 'rows': [
   {'title': 'saltwindow', 'sub': 'You · created the collection Sep 2024', 'tone': '#23506B', 'badge': 'Owner', 'badgeBg': '#990000'},
   {'title': 'tidewright', 'sub': 'Since Sep 2024', 'meta': 'Approved 28 works', 'tone': '#2F6D6A', 'badge': 'Moderator', **BLUE},
   {'title': 'marginalia', 'sub': 'Invited Oct 20', 'meta': 'Hasn’t accepted yet', 'metaColour': '#C25E00', 'tone': '#7A4040', 'badge': 'Invited', **GREY}]},
  {'header': 'Most active members', 'count': '41', 'kind': 'rows', 'rows': [
   {'title': 'inkwell_moth', 'sub': '6 works in this collection', 'tone': '#1F4E5F'},
   {'title': 'quietharbor', 'sub': '4 works · 2 bookmarks', 'tone': '#3E5B3A'},
   {'title': 'anne_at_lyme', 'sub': '3 works', 'tone': '#6B4E23'}]}]}, 940)
# Challenges
add('Challenge-SignUp', 'Challenge › Sign up (form)', 'FormScreen', {'title': 'Sign Up', 'back': 'Back', 'confirm': 'Submit'}, {
 'context': {**EXCH, 'meta': 'Sign-ups close Nov 1 · 98 signed up · 1–3 requests'},
 'sections': [
  {'header': 'Request 1', 'rows': [
   {'label': 'Fandom', 'kind': 'chips', 'chips': ['Persuasion']},
   {'label': 'Relationship', 'kind': 'chips', 'chips': ['Anne Elliot/Frederick Wentworth']},
   {'label': 'Characters', 'kind': 'chips', 'chips': ['Anne Elliot', 'Admiral Croft']},
   {'kind': 'textarea', 'text': 'Letters, rain, a second chance that takes its time. Happy endings please.', 'rows': 2}]},
  {'rows': [{'label': 'Add Another Request', 'kind': 'button'}]},
  {'header': 'Offer 1', 'rows': [
   {'label': 'Fandom', 'kind': 'chips', 'chips': ['Pride and Prejudice']},
   {'label': 'Characters', 'kind': 'chips', 'chips': ['Elizabeth Bennet', 'Any']},
   {'label': 'Ratings I’ll write', 'kind': 'value', 'detail': 'G to M'}]},
  {'rows': [{'label': 'Add Another Offer', 'kind': 'button'}]},
  {'header': 'Your sign-up', 'rows': [{'label': 'Pseud', 'kind': 'nav', 'detail': 'saltwindow'}, {'label': 'Make sign-up public', 'kind': 'toggle', 'on': False}, {'label': 'Pinch hit if someone drops out', 'kind': 'toggle', 'on': True}]}]}, 1080)
add('Challenge-SignUps', 'Challenge › Sign-ups (maintainer)', 'ListScreen', {'title': 'Sign-ups', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': EXCH,
 'stats': stats(('98', 'Sign-ups'), ('4', 'Incomplete', '#C25E00'), ('6', 'Pinch hitters'), ('4 days', 'Left')),
 'tools': [{'label': 'More: Export, Close Sign-ups', 'icon': 'more'}],
 'chips': [{'label': 'All', 'on': True}, {'label': 'Incomplete 4'}, {'label': 'Pinch hitters 6'}],
 'sections': [{'kind': 'rows', 'rows': [
  {'title': 'quietharbor', 'sub': 'Requests', 'tags': [ship('Anne Elliot/Frederick Wentworth')], 'meta': 'Offers Pride and Prejudice, Emma · signed up Oct 3', 'tone': '#3E5B3A'},
  {'title': 'anne_at_lyme', 'sub': 'Requests', 'tags': [ship('Louisa Musgrove/Captain Benwick'), 'Persuasion'], 'meta': 'Offers Northanger Abbey · signed up Oct 4', 'tone': '#6B4E23'},
  {'title': 'lizzy_reads', 'sub': 'Requests', 'tags': [ship('Elizabeth Bennet/Fitzwilliam Darcy')], 'meta': 'No offer yet', 'metaColour': '#C25E00', 'tone': '#7A4040', 'badge': 'Incomplete', **AMBER},
  {'title': 'elinor_d', 'sub': 'Requests', 'tags': [ship('Elinor Dashwood/Edward Ferrars')], 'meta': 'Offers Persuasion · pinch hitter', 'tone': '#4A3D6A', 'badge': 'Pinch hitter', **BLUE}]}]}, 980)
add('Challenge-Assignments', 'Challenge › Assignments', 'ListScreen', {'title': 'Assignments', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': {**EXCH, 'meta': 'Assignments sent Nov 2 · works due Nov 12'},
 'stats': stats(('92', 'Assigned'), ('31', 'Posted'), ('2', 'Defaulted', '#D70015'), ('15 days', 'To go')),
 'sections': [
  {'header': 'Yours', 'kind': 'rows', 'rows': [{'title': 'Writing for quietharbor', 'sub': 'Persuasion', 'tags': [ship('Anne Elliot/Frederick Wentworth')], 'meta': 'Draft: Untitled lighthouse piece · 3,240 of 5,000 words', 'cover': art(PER), 'badge': '15 days', **AMBER, 'bar': 65, 'barLabel': '3,240 of 5,000 words'}]},
  {'header': 'Pinch hits open', 'count': '2', 'kind': 'rows', 'rows': [
   {'title': 'For elinor_d', 'sub': 'Sense and Sensibility · original writer defaulted', 'tags': [ship('Elinor Dashwood/Edward Ferrars')], 'cover': art(SS), 'action': 'Claim'},
   {'title': 'For lizzy_reads', 'sub': 'Pride and Prejudice · due Nov 19', 'tags': [ship('Elizabeth Bennet/Fitzwilliam Darcy')], 'cover': art(PP), 'action': 'Claim'}]},
  {'header': 'Recently posted', 'count': '31', 'kind': 'rows', 'rows': [
   {'title': 'A Map of Small Hours', 'sub': 'quietharbor for elinor_d · Oct 26', 'cover': art(PP)},
   {'title': 'Letters Never Sent', 'sub': 'marginalia for lizzy_reads · Oct 25', 'cover': art(PER)}]}]}, 1020)
add('Challenge-Settings', 'Challenge › Settings (maintainer)', 'FormScreen', {'title': 'Challenge Settings', 'back': 'Back', 'confirm': 'Save'}, {
 'context': EXCH,
 'stats': stats(('98', 'Sign-ups'), ('214', 'Requests'), ('251', 'Offers')),
 'sections': [
  {'header': 'Schedule', 'rows': [
   {'label': 'Sign-ups open', 'kind': 'value', 'detail': 'Oct 1', 'meta': 'Done', 'metaColour': '#2F8F3A'},
   {'label': 'Sign-ups close', 'kind': 'value', 'detail': 'Nov 1', 'meta': 'In 4 days', 'metaColour': '#C25E00'},
   {'label': 'Assignments sent', 'kind': 'value', 'detail': 'Nov 2'},
   {'label': 'Works due', 'kind': 'value', 'detail': 'Nov 12'},
   {'label': 'Works revealed', 'kind': 'value', 'detail': 'Dec 1'}]},
  {'header': 'Sign-ups', 'rows': [{'label': 'Sign-up open', 'kind': 'toggle', 'on': True}, {'label': 'Requests per person', 'kind': 'value', 'detail': '1–3'}, {'label': 'Offers per person', 'kind': 'value', 'detail': '1–3'}, {'label': 'Tag set', 'kind': 'nav', 'detail': 'Austen Exchange 2026'}]},
  {'header': 'Matching', 'rows': [{'label': 'Match on', 'kind': 'segments', 'options': ['Fandom', 'Characters', 'Both'], 'selected': 2}, {'label': 'Allow pinch hitters', 'kind': 'toggle', 'on': True}, {'label': 'Generate Potential Matches', 'kind': 'button'}]}]}, 1120)
add('Prompt-Meme', 'Challenge › Prompt meme', 'ListScreen', {'title': 'Prompts', 'back': 'Back', 'tab': 'writing'}, {
 'large': False,
 'context': MEME,
 'stats': stats(('142', 'Prompts'), ('38', 'Claimed'), ('21', 'Filled'), ('1', 'Yours', '#990000')),
 'tools': [{'label': 'New Prompt', 'icon': 'plus'}],
 'chips': [{'label': 'All', 'on': True}, {'label': 'Unclaimed'}, {'label': 'Claimed by me'}, {'label': 'Filled'}],
 'sections': [{'kind': 'rows', 'rows': [
  {'title': 'Anne, rain, a borrowed coat', 'sub': 'by quietharbor · Oct 12', 'tags': [ship('Anne Elliot/Frederick Wentworth')], 'meta': 'Claimed by you', 'metaColour': '#990000', 'tone': '#7B3FA0', 'glyph': I['chat'], 'square': True, 'badge': 'Claimed', 'badgeBg': '#990000'},
  {'title': 'The navy list, read aloud', 'sub': 'by anne_at_lyme · Oct 9', 'tags': ['Gen', 'Admiral Croft', 'Sophia Croft'], 'meta': '2 claims · 1 fill', 'tone': '#7B3FA0', 'glyph': I['chat'], 'square': True, 'action': 'Claim'},
  {'title': 'Lyme, the morning after', 'sub': 'Anonymous · Oct 8', 'tags': ['Louisa Musgrove', 'Anne Elliot'], 'meta': 'Unclaimed', 'tone': '#7B3FA0', 'glyph': I['chat'], 'square': True, 'action': 'Claim'},
  {'title': 'Kellynch, years later', 'sub': 'by elinor_d · Oct 2', 'tags': [ship('Anne Elliot/Frederick Wentworth'), 'Future Fic'], 'meta': '1 fill', 'tone': '#7B3FA0', 'glyph': I['chat'], 'square': True, 'action': 'Claim'}]}]}, 980)
add('Prompt-Tags', 'Challenge › Prompt tags (maintainer)', 'FormScreen', {'title': 'Tag Set', 'back': 'Back', 'confirm': 'Save'}, {
 'context': {**EXCH, 'kicker': 'Tag set', 'meta': 'Used by Austen Exchange 2026'},
 'stats': stats(('7', 'Fandoms'), ('44', 'Characters'), ('23', 'Relationships'), ('12', 'To review', '#C25E00')),
 'sections': [
  {'header': 'Fandoms', 'rows': [{'label': 'Allowed', 'kind': 'chips', 'chips': ['Persuasion', 'Pride and Prejudice', 'Emma', 'Northanger Abbey', '+3']}]},
  {'header': 'Characters', 'rows': [{'label': 'Allowed', 'kind': 'chips', 'chips': ['Anne Elliot', 'Frederick Wentworth', 'Elizabeth Bennet', '+41']}, {'label': 'Let participants nominate', 'kind': 'toggle', 'on': True}]},
  {'header': 'Nominations to review', 'rows': [
   {'label': 'Admiral Croft', 'sub': 'Character · Persuasion', 'meta': 'Nominated by 3', 'kind': 'nav', 'badge': 'New', **AMBER},
   {'label': 'Catherine Morland/Henry Tilney', 'sub': 'Relationship · Northanger Abbey', 'meta': 'Nominated by 5', 'kind': 'nav', 'badge': 'New', **AMBER},
   {'label': 'Mr Woodhouse', 'sub': 'Character · Emma', 'meta': 'Nominated by 1', 'kind': 'nav'},
   {'label': 'All 12 Nominations', 'kind': 'nav'}]}]}, 1060)

open('group4.list', 'w').write('\n'.join(f'{n}|{t}|{h}' for n, t, h in B)); print(len(B), 'boards')
