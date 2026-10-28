import sys; sys.path.insert(0,'.')
from gen import board
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): board(name,title,comp,attrs,data,h); B.append((name,title,h))
COL=['#C25E00','#1E63C8','#2F8F3A','#7B3FA0','#B3127A','#6C6C70']

# Queues and collections
add('Queue-Edit','Queue › Edit Queue (sheet)','FormScreen',{'title':'Edit Queue','mode':'sheet','confirm':'Save'},{
 'sections':[{'header':'Name','rows':[{'kind':'field','text':'Summer Reading'}]},
  {'header':'Description','rows':[{'kind':'textarea','text':'Short, warm things for the train.','rows':2}]},
  {'rows':[{'label':'Colour','kind':'swatches','colours':COL,'selected':0},{'label':'Tags','kind':'chips','chips':['fluff','under 20k']}]},
  {'header':'Reading','rows':[{'label':'When I finish a work','kind':'segments','options':['Remove','Keep'],'selected':0},{'label':'Pin to Home','kind':'toggle','on':True}]},
  {'header':'Offline','footer':'Queued works download on Wi‑Fi and stay until you remove them.','rows':[{'label':'Keep works offline','kind':'toggle','on':True,'sub':'6 of 8 downloaded · 41 MB'},{'label':'Storage','kind':'nav','detail':'41 MB'}]},
  {'rows':[{'label':'Delete Queue','kind':'destructive'}]}]},1000)
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
 'sections':[{'rows':[{'label':t,'sub':s,'kind':'info','handle':True} for t,s in [('A Map of Small Hours','quietharbor'),('Northanger Nights','gothicnovelist'),('Letters Never Sent','marginalia'),('Half Agony, Half Hope','anne_at_lyme'),('Five Times Elizabeth Laughed','quietharbor'),('The Bath Letters','marginalia'),('A Fortnight at Uppercross','quietharbor')]]}]})
add('Bulk-Edit','Library › Edit 3 Works (sheet)','FormScreen',{'title':'Edit 3 Works','mode':'sheet','confirm':'Done'},{
 'sections':[{'header':'Organise','rows':[{'label':'Add to Queue','kind':'nav','icon':I['queue']},{'label':'Add to Collection','kind':'nav','icon':'M6 8h12v12H6zM8 5h8'},{'label':'Want to Read','kind':'toggle','on':False}]},
  {'header':'Your tags','rows':[{'label':'comfort','kind':'circle','on':True,'sub':'all 3'},{'label':'slow burn','kind':'circle','on':False,'sub':'1 of 3'},{'label':'reread','kind':'circle','on':False,'sub':'none'}]},
  {'header':'Reading','rows':[{'label':'Mark as Finished','kind':'button'},{'label':'Mark as Unread','kind':'button'},{'label':'Download All','kind':'button'}]},
  {'footer':'1 of these 3 can’t be downloaded again: it is no longer on AO3.','rows':[{'label':'Delete 3 Works','kind':'destructive'}]}]},1000)

# Search
add('Search-Saved','Search › Saved Searches','ListScreen',{'title':'Saved Searches','subtitle':'4 searches · new results since you last ran each','back':'Back to Search','tab':'none'},{
 'tools':[{'label':'Edit','text':'Edit'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Persuasion · Anne/Wentworth · complete','sub':'Fandom, relationship, complete only · sorted by kudos','tone':'#990000','glyph':I['tag'],'square':True,'badge':'12 new'},
  {'title':'Holmes casefic under 20k','sub':'Sherlock Holmes · Gen · under 20,000 words','tone':'#990000','glyph':I['tag'],'square':True,'badge':'3 new'},
  {'title':'Lighthouses (any fandom)','sub':'Freeform tag · English','tone':'#990000','glyph':I['tag'],'square':True},
  {'title':'“epistolary” in summaries','sub':'Text search · Teen and below','tone':'#990000','glyph':'M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.5 15.5l5 5','square':True}]}]})
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
