import sys; sys.path.insert(0,'.')
from gen import board
from polish import polish
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): attrs,data=polish(name,attrs,data); board(name,title,comp,attrs,data,h); B.append((name,title,h))
COL=['#C25E00','#1E63C8','#2F8F3A','#7B3FA0','#B3127A','#6C6C70']

# Queues and collections
add('Queue-Edit','Queue › Edit Queue (sheet)','FormScreen',{'title':'Edit Queue','mode':'sheet','confirm':'Save'},{
 'sections':[{'header':'Name','rows':[{'kind':'field','text':'Summer Reading'}]},
  {'header':'Description','rows':[{'kind':'textarea','text':'Short, warm things for the train.','rows':2}]},
  {'rows':[{'label':'Colour','kind':'swatches','colours':COL,'selected':0},{'label':'Tags','kind':'chips','chips':['fluff','under 20k']}]},
  {'header':'Reading','rows':[{'label':'When I finish a work','kind':'segments','options':['Remove','Keep'],'selected':0},{'label':'Pin to Home','kind':'toggle','on':True}]},
  {'header':'Offline','footer':'Queued works download on Wi‑Fi and stay until you remove them.','rows':[{'label':'Keep works offline','kind':'toggle','on':True,'sub':'6 of 8 downloaded · 41 MB'},{'label':'Storage','kind':'nav','detail':'41 MB'}]},
  {'rows':[{'label':'Delete Queue','kind':'destructive'}]}]},1120)
add('Queue-Tags','Queues › Manage Tags','FormScreen',{'title':'Queue Tags','back':'Back to Queues','trailing':'Edit'},{
 'sections':[{'header':'Tags on your queues','rows':[{'label':'fluff','kind':'nav','detail':'3 queues'},{'label':'under 20k','kind':'nav','detail':'2 queues'},{'label':'comfort','kind':'nav','detail':'1 queue'},{'label':'rereads','kind':'nav','detail':'1 queue'},{'label':'long haul','kind':'nav','detail':'unused'}]},
  {'rows':[{'label':'New Tag…','kind':'button'}]}]})
add('Collection-New','Collections › New Collection (sheet)','FormScreen',{'title':'New Collection','mode':'sheet','confirm':'Create'},{
 'sections':[{'header':'Name','rows':[{'kind':'field','placeholder':'Collection name'}]},
  {'header':'Description','rows':[{'kind':'textarea','placeholder':'Optional','rows':2}]},
  {'rows':[{'label':'Colour','kind':'swatches','colours':['#9C2F6B','#B8892A','#2F7A4A','#1E63C8','#7B3FA0','#6C6C70'],'selected':3},{'label':'Pin to Home','kind':'toggle','on':False}]},
  {'rows':[{'label':'Add Works…','kind':'nav','detail':'None yet'}]}]})
add('Collection-AddWorks','Collection › Add Works (sheet)','FormScreen',{'title':'Add Works','subtitle':'Austen Variations','mode':'sheet','confirm':'Add 2','search':'Search your library'},{
 'sections':[{'header':'In your library','rows':[
   {'label':'A Map of Small Hours','sub':'quietharbor · Pride and Prejudice','kind':'circle','on':True},
   {'label':'Letters Never Sent','sub':'marginalia · Persuasion','kind':'circle','on':True},
   {'label':'Half Agony, Half Hope','sub':'anne_at_lyme · Persuasion · already in it','kind':'info','colour':'#8E8E93'},
   {'label':'Northanger Nights','sub':'gothicnovelist · Northanger Abbey','kind':'circle','on':False},
   {'label':'Five Times Elizabeth Laughed','sub':'quietharbor · Pride and Prejudice','kind':'circle','on':False},
   {'label':'The Bath Letters','sub':'marginalia · Persuasion','kind':'circle','on':False}]}]})
add('Collection-Reorder','Collection › Reorder','FormScreen',{'title':'Reorder','subtitle':'Austen Variations','back':'Back to Austen Variations','trailing':'Done'},{
 'sections':[{'rows':[{'label':t,'sub':s,'kind':'info','handle':'trailing'} for t,s in [('A Map of Small Hours','quietharbor'),('Northanger Nights','gothicnovelist'),('Letters Never Sent','marginalia'),('Half Agony, Half Hope','anne_at_lyme'),('Five Times Elizabeth Laughed','quietharbor'),('The Bath Letters','marginalia'),('A Fortnight at Uppercross','quietharbor')]]}]})
add('Bulk-Edit','Library › Edit 3 Works (sheet)','FormScreen',{'title':'Edit 3 Works','mode':'sheet','confirm':'Done'},{
 'sections':[{'header':'Organise','rows':[{'label':'Add to Queue','kind':'nav','icon':I['queue']},{'label':'Add to Collection','kind':'nav','icon':'M6 8h12v12H6zM8 5h8'},{'label':'Want to Read','kind':'toggle','on':False}]},
  {'header':'Your tags','rows':[{'label':'comfort','kind':'circle','on':True,'sub':'all 3'},{'label':'slow burn','kind':'circle','on':False,'sub':'1 of 3'},{'label':'reread','kind':'circle','on':False,'sub':'none'}]},
  {'header':'Reading','rows':[{'label':'Mark as Finished','kind':'button'},{'label':'Mark as Unread','kind':'button'},{'label':'Download All','kind':'button'}]},
  {'footer':'1 of these 3 can’t be downloaded again: it is no longer on AO3.','rows':[{'label':'Delete 3 Works','kind':'destructive'}]}]},1000)

# Search
add('Search-Saved','Search › Saved Searches','ListScreen',{'title':'Saved Searches','subtitle':'4 searches · new results since you last ran each','back':'Back to Search','tab':'none'},{
 'tools':[{'label':'Edit','text':'Edit'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Persuasion · Anne/Wentworth · complete','sub':'Fandom, relationship, complete only · sorted by kudos','tone':'#821019','glyph':I['tag'],'square':True,'badge':'12 new'},
  {'title':'Holmes casefic under 20k','sub':'Sherlock Holmes · Gen · under 20,000 words','tone':'#821019','glyph':I['tag'],'square':True,'badge':'3 new'},
  {'title':'Lighthouses (any fandom)','sub':'Freeform tag · English','tone':'#821019','glyph':I['tag'],'square':True},
  {'title':'“epistolary” in summaries','sub':'Text search · Teen and below','tone':'#821019','glyph':'M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.5 15.5l5 5','square':True}]}]})
# Sort: ways to find (each sets both lists), AO3's own columns, then how Kudos ranks
# the works already loaded. Method and sources: notes/quality-signals-spec.md.
add('Search-Sort','Search filters › Sort By','FormScreen',{'title':'Sort By','back':'Back to Filters'},{
 'sections':[
  {'header':'Ways to Find','rows':[
   {'label':'Reader Favourites','sub':'Most kudos on AO3, at least 1,000 hits','kind':'check','tile':'#821019','icon':'M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.2a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z'},
   {'label':'New and Loved','sub':'Posted in the last 6 months, most kudos first','kind':'check','tile':'#E07000','icon':'M5 6h14v14H5zM5 10h14M9 3.5v4M15 3.5v4'},
   {'label':'Hidden Gems','sub':'300 to 5,000 hits, most kudos first','kind':'check','on':True,'tile':'#5856D6','icon':'M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18 15l.8 2.2 2.2.8-2.2.8L18 21l-.8-2.2-2.2-.8 2.2-.8z'},
   {'label':'Active WIPs','sub':'Updated in the last 60 days, on schedule first','kind':'check','tile':'#2F8F3A','icon':'M12 4a8 8 0 1 1 0 16 8 8 0 0 1 0-16zM12 8v4l3 2'}]},
  {'header':'Load from AO3 by','footer':'Hidden Gems adds “hits 300 to 5,000” to the search AO3 runs.','rows':[{'label':l,'kind':'check','on':l=='Kudos','tile':t,'icon':d} for l,t,d in [
   ('Best Match','#1E63C8','M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18 15l.8 2.2 2.2.8-2.2.8L18 21l-.8-2.2-2.2-.8 2.2-.8z'),
   ('Date Updated','#E07000','M4 12a8 8 0 1 0 2.3-5.6M4 4v4h4M12 8v4l3 2'),
   ('Date Posted','#E07000','M5 6h14v14H5zM5 10h14M9 3.5v4M15 3.5v4'),
   ('Title','#6C6C70','M5 6h14M12 6v13M9 19h6'),
   ('Creator','#6C6C70','M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8zM4.5 20c1.4-3.8 4.2-5.8 7.5-5.8s6.1 2 7.5 5.8'),
   ('Word Count','#7B3FA0','M5 6h14M5 12h14M5 18h9'),
   ('Hits','#5856D6','M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12zM12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6z'),
   ('Kudos','#821019','M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.2a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z'),
   ('Comments','#2F8F3A','M4 5h16v11H9l-5 4z'),
   ('Bookmarks','#C25E00','M7 4h10v16l-5-4-5 4z')]]},
  {'header':'Then Rank Loaded Works by','rows':[
   {'label':'AO3’s Order','sub':'As AO3 sent them','kind':'check','tile':'#6C6C70','icon':'M4 6h16M4 12h16M4 18h16'},
   {'label':'Kudos per Hit, Adjusted','sub':'Against works of the same length, chapters and age','meta':'Top loaded result: 2.4× typical','metaColour':'#821019','kind':'check','on':True,'tile':'#821019','icon':'M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.2a4.2 4.2 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z'},
   {'label':'Saves per Kudos','sub':'Public bookmarks ÷ kudos','kind':'check','tile':'#C25E00','icon':'M7 4h10v16l-5-4-5 4z'},
   {'label':'Comments per Kudos','sub':'Comments, replies included, ÷ kudos','kind':'check','tile':'#2F8F3A','icon':'M4 5h16v11H9l-5 4z'},
   {'label':'Momentum','sub':'Kudos gained since you last saw each work','kind':'check','tile':'#1E63C8','icon':'M4 16l5-5 4 4 7-7M15 8h5v5'},
   {'label':'Kudos per 1,000 Words','sub':'Kudos ÷ word count × 1,000','kind':'check','tile':'#7B3FA0','icon':'M5 6h14M5 12h14M5 18h9'}],
   'footer':'Ranks the works already loaded. More load as you scroll, or up to 100 at once with Rank Top 100.'},
  {'header':'Ranking','rows':[
   {'label':'Rank cautiously','kind':'toggle','on':True,'sub':'Works with few readers need more kudos to rank high'},
   {'label':'Set aside unusual stats','kind':'toggle','on':True,'sub':'More kudos than hits, or thousands of kudos and almost no bookmarks'},
   {'label':'Leave out works under','kind':'value','detail':'300 hits','sub':'Sent to AO3 with the search, so pages stay full'},
   {'label':'Show the signal on each result','kind':'toggle','on':True}]},
  {'rows':[{'label':'Order','kind':'segments','options':['Highest First','Lowest First'],'selected':0}]}]},1840)
add('Search-Save','Search › Save Search (sheet)','FormScreen',{'title':'Save Search','mode':'sheet','confirm':'Save'},{
 'sections':[{'header':'Name','rows':[{'kind':'field','text':'Persuasion · Anne/Wentworth · complete'}]},
  {'header':'This search','rows':[{'label':'Filters','kind':'chips','chips':['Persuasion','Anne/Wentworth','Complete','Kudos ↓']}]},
  {'footer':'New results are counted when you open Saved Searches; Kudos doesn’t check in the background.','rows':[{'label':'Show new results on Home','kind':'toggle','on':True}]}]})
add('Filter-Language','Search filters › Language','FormScreen',{'title':'Language','back':'Back to Filters','search':'Search languages'},{
 'sections':[{'header':'Recent','rows':[{'label':'English','kind':'check','on':True},{'label':'Deutsch','kind':'check'}]},
  {'header':'All languages','rows':[{'label':l,'kind':'check'} for l in ['Any language','العربية','Català','中文-普通话 國語','Español','Français','Italiano','日本語','Polski','Português brasileiro','Русский']]}]},1000)
add('Filter-Tags','Search filters › Tags','FormScreen',{'title':'Additional Tags','back':'Back to Filters','search':'fluff'},{
 'sections':[{'header':'Included','rows':[{'label':'Include','kind':'chips','chips':['Slow Burn','Epistolary']}]},
  {'header':'Excluded','rows':[{'label':'Exclude','kind':'chips','chips':['Major Character Death']}]},
  {'header':'Matching “fluff”','rows':[{'label':'Fluff','sub':'1.9M works','kind':'nav'},{'label':'Fluff and Angst','sub':'612k works','kind':'nav'},{'label':'Tooth-Rotting Fluff','sub':'88k works','kind':'nav'},{'label':'Domestic Fluff','sub':'71k works','kind':'nav'}]}]},900)

# Work
add('Bookmark-Edit','Work › Bookmark on AO3 (sheet)','FormScreen',{'title':'Edit Bookmark','subtitle':'A Map of Small Hours','mode':'sheet','confirm':'Save'},{
 'sections':[{'header':'Notes','rows':[{'kind':'textarea','text':'The insomnia ledger. Chapter 6 is the one.','rows':3}]},
  {'header':'Your tags','rows':[{'label':'Tags','kind':'chips','chips':['reread','pemberley']}]},
  {'rows':[{'label':'Collections','kind':'nav','detail':'None'},{'label':'Private','kind':'toggle','on':False},{'label':'Rec','kind':'toggle','on':True,'sub':'Shows as a recommendation on your AO3 bookmarks'}]},
  {'rows':[{'label':'Delete Bookmark','kind':'destructive'}]}]},900)
add('Series-SavePrompt','Work › Save the whole series? (sheet)','FormScreen',{'title':'Save Series?','mode':'sheet','confirm':'Save'},{
 'hero':{'title':'Bath & Barouche','sub':'Series by quietharbor · 4 parts · 61,200 words','colour':'#1E63C8','icon':I['series']},
 'sections':[{'rows':[{'label':'Just this work','sub':'Part 2, A Season at Bath','kind':'circle','on':False},{'label':'All 4 parts','sub':'Downloads 3 more works, about 2.4 MB','kind':'circle','on':True}]},
  {'rows':[{'label':'Keep new parts too','kind':'toggle','on':True,'sub':'Adds new parts when you open the series'}]}]})
add('Inbox-Filter','Inbox › Filter (sheet)','FormScreen',{'title':'Filter Inbox','mode':'sheet','confirm':'Apply'},{
 'sections':[{'rows':[{'label':'Show','kind':'segments','options':['All','Unread','Replied'],'selected':1},{'label':'Sort','kind':'segments','options':['Newest','Oldest'],'selected':0}]},
  {'header':'On','rows':[{'label':'All works','kind':'check','on':True},{'label':'Keeper of the Northern Light','kind':'check'},{'label':'Lantern Season','kind':'check'},{'label':'What the Tide Keeps','kind':'check'}]},
  {'rows':[{'label':'Reset Filters','kind':'button'}]}]})
open('group2a.list','w').write('\n'.join(f'{n}|{t}|{h}' for n,t,h in B)); print(len(B))
