import sys; sys.path.insert(0,'.')
from gen import board
from polish import polish
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): attrs,data=polish(name,attrs,data); board(name,title,comp,attrs,data,h); B.append((name,title,h))

# AO3 collections, challenges and posting screens live in group4.py.

# Reader
add('Reader-PageJump','Reader › Go to Page (sheet)','FormScreen',{'title':'Go to Page','subtitle':'Chapter 7 · The Salt Road','mode':'sheet','confirm':'Go'},{
 'sections':[{'rows':[{'label':'Page','kind':'field','text':'4'},{'label':'of 18 in this chapter','kind':'info','colour':'#6C6C70'}]},
  {'header':'Or a chapter','rows':[{'label':'6. The Inland Sea','kind':'nav','detail':'p. 1'},{'label':'7. The Salt Road','kind':'check','on':True},{'label':'8. Shingle','kind':'nav','detail':'p. 1'}]},
  {'rows':[{'label':'Back to Where I Was','kind':'button'}]}]})
add('Reader-CustomizeTheme','Reader › Customize Theme','FormScreen',{'title':'Customize Theme','subtitle':'Sepia','back':'Back to Themes','confirm':'Save'},{
 'hero':{'title':'Aa · The road to the coast','sub':'Preview in New York, 19 pt','colour':'#9A6732','icon':'M4 19 9 5l5 14M6 14h6M15 19l3-8 3 8M16 16.5h4'},
 'sections':[{'header':'Colours','rows':[{'label':'Paper','kind':'swatches','colours':['#FBF0D9','#F4ECD8','#EDE3CC','#FFFFFF'],'selected':0},{'label':'Text','kind':'swatches','colours':['#5B4636','#3B2F1E','#1F1B16'],'selected':0},{'label':'Links','kind':'swatches','colours':['#9A6732','#821019','#1E63C8'],'selected':0}]},
  {'header':'Highlights','rows':[{'label':'Highlight','kind':'swatches','colours':['#F5D76E','#9ED8A0','#9CC6F0','#F4A6C0'],'selected':0}]},
  {'rows':[{'label':'Reset to Sepia','kind':'button'}]}]})
add('Reader-Pronunciation','Read Aloud › Pronunciations','FormScreen',{'title':'Pronunciations','back':'Back to Read Aloud','trailing':'Edit'},{
 'sections':[{'header':'This work','rows':[{'label':'Wentworth','sub':'Said as “WENT-wurth”','kind':'nav'},{'label':'Uppercross','sub':'Said as “UP-per-cross”','kind':'nav'}]},
  {'header':'All works','rows':[{'label':'AU','sub':'Said as “alternate universe”','kind':'nav'},{'label':'POV','sub':'Said as “point of view”','kind':'nav'},{'label':'Mx.','sub':'Said as “mix”','kind':'nav'}]},
  {'rows':[{'label':'Add a Pronunciation…','kind':'button'}]}]})

# Sync
add('Sync-Pair','Settings › Add a Device (sheet)','FormScreen',{'title':'Add a Device','mode':'sheet'},{
 'hero':{'title':'Sync with another device','sub':'Through your iCloud Drive folder; nothing goes through a Kudos server.','colour':'#2F8F3A','icon':'M4 12a8 8 0 0 1 13.7-5.6L20 9M20 4v5h-5M20 12a8 8 0 0 1-13.7 5.6L4 15M4 20v-5h5'},
 'sections':[{'rows':[{'label':'Show a Code on This iPhone','kind':'nav','tile':'#1E63C8','icon':'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2zM14 18h2v2h-2zM18 14h2v2h-2z'},{'label':'Scan the Other Device’s Code','kind':'nav','tile':'#2F8F3A','icon':'M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4M4 12h16'},{'label':'Type a Key Instead','kind':'nav','tile':'#6C6C70','icon':'M7 15a4 4 0 1 1 3.9-5H21v3h-2v2h-3v-2h-5.1A4 4 0 0 1 7 15z'}]},
  {'rows':[{'label':'I got this key from my own device','kind':'toggle','on':False}],'footer':'Only pair devices you own: a paired device can read your whole library.'}]})
add('Sync-Devices','Settings › Synced devices','FormScreen',{'title':'Devices','back':'Back to Sync'},{
 'sections':[{'header':'Syncing with','rows':[{'label':'This iPhone','sub':'iPhone 17 · synced just now','kind':'info','tile':'#1E63C8','icon':'M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2'},{'label':'iPad','sub':'iPad Air · synced 2 h ago','kind':'nav','tile':'#1E63C8','icon':'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2'},{'label':'Mac','sub':'MacBook Air · synced yesterday','kind':'nav','tile':'#1E63C8','icon':'M4 5h16v10H4zM2 19h20'}]},
  {'rows':[{'label':'Add a Device…','kind':'button'}]},
  {'rows':[{'label':'Remove This iPhone from Sync','kind':'destructive'}],'footer':'Your library stays on this iPhone; it just stops syncing.'}]})
add('Backup-Replace','Settings › Restore from a backup (sheet)','FormScreen',{'title':'Restore Backup','mode':'sheet'},{
 'hero':{'title':'Kudos backup, Oct 21','sub':'214 works · 6 queues · 4 collections · 31 MB','colour':'#C25E00','icon':'M12 4v11M7.5 10.5 12 15l4.5-4.5M4 19.5h16'},
 'sections':[{'rows':[{'label':'Merge with This Library','sub':'Keeps both; newer progress and edits win','kind':'circle','on':True},{'label':'Replace This Library','sub':'This library becomes the backup exactly','kind':'circle','on':False}]},
  {'rows':[{'label':'Restore','kind':'button'}],'footer':'Replacing moves today’s library to Recently Deleted for 90 days first.'}]})
add('Availability-Check','Settings › What’s still on AO3','ListScreen',{'title':'Still on AO3?','subtitle':'Checking 214 works · 38 done · one at a time','back':'Back to Storage'},{
 'sections':[{'kind':'rows','rows':[{'title':'Checking…','sub':'38 of 214 · about 6 min left · stops if you leave','light':True,'tone':'#2F8F3A','glyph':'M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17zM12 7.5V12l3 2','square':True,'bar':18,'barColour':'#2F8F3A','barLabel':'38 of 214 checked','chevron':False}]},
  {'header':'Gone from AO3','count':'2','kind':'rows','rows':[
   {'title':'Thornfield, Rebuilt','kicker':'Jane Eyre','kickerColour':'hsl(262, 46%, 40%)','sub':'Deleted or made private · your copy is safe','tone':'#C25E00','glyph':'M12 4 2.8 19.5h18.4zM12 10v4.5M12 17.2v.1','square':True},
   {'title':'The Quiet Year','kicker':'Original Work','kickerColour':'hsl(188, 56%, 33%)','sub':'Locked to AO3 users · log in to check','tone':'#6C6C70','glyph':I['lock'],'square':True}]}]})
open('group2b.list','w').write('\n'.join(f'{n}|{t}|{h}' for n,t,h in B)); print(len(B))
