import sys; sys.path.insert(0,'.')
from gen import board
from polish import polish
from data import W, I, works, SHELF
B=[]
def add(name,title,comp,attrs,data,h=844,**kw): attrs,data=polish(name,attrs,data); board(name,title,comp,attrs,data,h,**kw); B.append((name,title,h))

# Library › a shelf (list and grid)
add('Shelf-List','Library › Finished (list)','ListScreen',{'title':'Finished','subtitle':'74 works · most recently finished first','back':'Back to Library'},{
 'tools':[{'label':'Filters','icon':'filter'},{'label':'More: List or Grid, Sort, Select','icon':'more'}],
 'chips':[{'label':'All','on':True},{'label':'Read twice'},{'label':'Kudos given'},{'label':'Downloaded'}],
 'sections':[{'header':'October','count':'6','works':works('letters','baker','moor','map')}]},1000)
add('Shelf-Grid','Library › Finished (grid)','ListScreen',{'title':'Finished','subtitle':'74 works · Grid','back':'Back to Library'},{
 'tools':[{'label':'Filters','icon':'filter'},{'label':'More: List or Grid, Sort, Select','icon':'more'}],
 'chips':[{'label':'All','on':True},{'label':'Read twice'},{'label':'Kudos given'},{'label':'Downloaded'}],
 'sections':[{'kind':'grid','works':works('letters','baker','moor','map')}]},1000)
EDIT_SHELVES = {
 'sections':[{'header':'On the Library page','rows':[
   {'label':'Favourites','kind':'segments','options':['Carousel','List'],'selected':0,'edit':'remove','handle':'trailing','dot':SHELF['Favourites'][0],'dotD':SHELF['Favourites'][1]},
   {'label':'Collections','kind':'segments','options':['Carousel','List'],'selected':0,'edit':'remove','handle':'trailing','dot':SHELF['Collections'][0],'dotD':SHELF['Collections'][1]},
   {'label':'Downloaded','kind':'segments','options':['Carousel','List'],'selected':0,'edit':'remove','handle':'trailing','dot':SHELF['Downloaded'][0],'dotD':SHELF['Downloaded'][1]}]},
  {'header':'As shelf buttons','rows':[
   {'label':'Want to Read','kind':'value','detail':'31','edit':'add','handle':'trailing','dot':SHELF['Want to Read'][0],'dotD':SHELF['Want to Read'][1]},
   {'label':'Reading Now','kind':'value','detail':'6','edit':'add','handle':'trailing','dot':SHELF['Reading Now'][0],'dotD':SHELF['Reading Now'][1]},
   {'label':'Finished','kind':'value','detail':'74','edit':'add','handle':'trailing','dot':SHELF['Finished'][0],'dotD':SHELF['Finished'][1]},
   {'label':'Queues','kind':'value','detail':'3','edit':'add','handle':'trailing','dot':SHELF['Queues'][0],'dotD':SHELF['Queues'][1]},
   {'label':'History','kind':'value','detail':'412','edit':'add','handle':'trailing','dot':SHELF['History'][0],'dotD':SHELF['History'][1]},
   {'label':'Imported','kind':'value','detail':'12','edit':'add','handle':'trailing','dot':SHELF['Imported'][0],'dotD':SHELF['Imported'][1]}]},
  {'rows':[{'label':'All Works','sub':'Always in the Library header','kind':'value','detail':'214','dot':SHELF['All Works'][0],'dotD':SHELF['All Works'][1]}]}]}
add('Edit-Shelves','Library › Edit Shelves (sheet)','FormScreen',{'title':'Edit Shelves','mode':'sheet','confirm':'Done'},EDIT_SHELVES)
add('Library-Edit','Library › Edit (over Library)','FormScreen',{'title':'Edit Shelves','mode':'sheet','confirm':'Done'},EDIT_SHELVES,backdrop='Library')

# Subscriptions tabs
sub_tools=[{'label':'More: Mark All as Seen, Follow a Tag…, Manage on AO3','icon':'more'}]
add('Subscriptions-Works','Subscriptions › Works','ListScreen',{'title':'Subscriptions','large':False,'subtitle':'18 works · 2 with new chapters','back':'Back to Library'},{
 'tools':sub_tools,'chips':[{'label':'Updates'},{'label':'Works 18','on':True},{'label':'Series 4'},{'label':'Authors 5'},{'label':'Tags 3'}],
 'sections':[{'works':works('salt','north','hound','stars')}]})
add('Subscriptions-Series','Subscriptions › Series','ListScreen',{'title':'Subscriptions','large':False,'subtitle':'4 series · 1 with a new part','back':'Back to Library'},{
 'tools':sub_tools,'chips':[{'label':'Updates'},{'label':'Works 18'},{'label':'Series 4','on':True},{'label':'Authors 5'},{'label':'Tags 3'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Bath & Barouche','kicker':'Persuasion','kickerColour':'hsl(335, 56%, 38%)','sub':'quietharbor · 4 parts · 61,200 words · updated yesterday','tone':'#1E63C8','glyph':I['series'],'square':True,'badge':'New part'},
  {'title':'The Baker Street Casebook','kicker':'Sherlock Holmes','kickerColour':'hsl(32, 56%, 33%)','sub':'fogandlamplight · 7 parts · 88,400 words · Oct 9','tone':'#1E63C8','glyph':I['series'],'square':True},
  {'title':'Lantern Keepers','kicker':'Original Work','kickerColour':'hsl(188, 56%, 33%)','sub':'tidewright · 3 parts · complete','tone':'#1E63C8','glyph':I['series'],'square':True},
  {'title':'Thornfield Letters','kicker':'Jane Eyre','kickerColour':'hsl(262, 46%, 40%)','sub':'brontebird · 2 parts · August','tone':'#1E63C8','glyph':I['series'],'square':True}]}]})
add('Subscriptions-Tags','Subscriptions › Tags (followed in Kudos)','ListScreen',{'title':'Subscriptions','large':False,'subtitle':'3 tags followed in Kudos · checked 10 min ago','back':'Back to Library'},{
 'tools':sub_tools,'chips':[{'label':'Updates'},{'label':'Works 18'},{'label':'Series 4'},{'label':'Authors 5'},{'label':'Tags 3','on':True}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Pride and Prejudice','kicker':'Fandom','kickerColour':'#2F7A4A','sub':'6 new this week · Complete only · on Home','tone':'#2F7A4A','glyph':I['tag'],'square':True,'badge':'6'},
  {'title':'Anne Elliot/Frederick Wentworth','kicker':'Relationship','kickerColour':'#2F7A4A','sub':'2 new this week · on Home','tone':'#2F7A4A','glyph':I['tag'],'square':True,'badge':'2'},
  {'title':'Lighthouses','kicker':'Freeform','kickerColour':'#2F7A4A','sub':'Nothing new since Oct 20 · Hide Explicit','tone':'#2F7A4A','glyph':I['tag'],'square':True}]},
  {'kind':'rows','rows':[{'title':'Follow a Tag…','light':True,'sub':'Fandoms, relationships, characters, freeform tags','tone':'#821019','glyph':'M12 5v14M5 12h14','square':True,'chevron':False}]}]})

# Writing drill-ins
add('Writing-Drafts','Writing › Drafts','ListScreen',{'title':'Drafts','subtitle':'2 on AO3 · 1 in Kudos only','back':'Back to Writing','tab':'writing'},{
 'tools':[{'label':'New Work','icon':'plus'},{'label':'More: Select, Sort','icon':'more'}],
 'sections':[{'header':'On AO3','count':'2','kind':'rows','rows':[
   {'title':'What the Tide Keeps · Chapter 4','kicker':'Original Work','kickerColour':'hsl(188, 56%, 33%)','sub':'1,240 words · edited yesterday · AO3 deletes it Nov 19','tone':'#2F6D6A','glyph':I['pen'],'square':True,'badge':'22 days','badgeBg':'#FFF4E5','badgeFg':'#6B3A00'},
   {'title':'Small Weathers II','kicker':'Persuasion','kickerColour':'hsl(335, 56%, 38%)','sub':'3,980 words · edited Oct 2 · AO3 deletes it Nov 1','tone':'#7A4040','glyph':I['pen'],'square':True,'badge':'4 days','badgeBg':'#FDE2E2','badgeFg':'#8E0E1C'}]},
  {'header':'In Kudos only','count':'1','kind':'rows','rows':[
   {'title':'Untitled lighthouse piece','kicker':'Original Work','kickerColour':'hsl(188, 56%, 33%)','sub':'640 words · not posted · on this iPhone','tone':'#8E8E93','glyph':I['pen'],'square':True}]}]})
add('Writing-Series','Writing › Series','ListScreen',{'title':'Series','subtitle':'1 series','back':'Back to Writing','tab':'writing'},{
 'tools':[{'label':'New Series','icon':'plus'}],
 'sections':[{'kind':'rows','rows':[{'title':'Lantern Season','kicker':'Original Work','kickerColour':'hsl(188, 56%, 33%)','sub':'3 parts · 37,250 words · 1,712 kudos','tone':'#1E63C8','glyph':I['series'],'square':True}]},
  {'header':'Lantern Season','count':'3 parts','kind':'rows','rows':[
   {'title':'1. Keeper of the Northern Light','sub':'22,410 words · complete','handle':'trailing'},
   {'title':'2. Lantern Season','sub':'15,050 words · complete','handle':'trailing'},
   {'title':'3. What the Tide Keeps','sub':'9,800 words · 3/8 · draft chapter 4','handle':'trailing'}]}]})

# Account sheet pages
add('AO3-Preferences','Account › AO3 Preferences','FormScreen',{'title':'AO3 Preferences','back':'Back to Account'},{
 'sections':[
  {'header':'Reading on AO3','rows':[{'label':'Show adult content without asking','kind':'toggle','on':False},{'label':'Hide warnings','kind':'toggle','on':False},{'label':'Hide additional tags','kind':'toggle','on':False},{'label':'Show whole work by default','kind':'toggle','on':True}]},
  {'header':'Your profile','rows':[{'label':'Time zone','kind':'nav','detail':'Europe/London'},{'label':'Skin','kind':'nav','detail':'Default'},{'label':'Browser title','kind':'nav','detail':'Default'}]},
  {'header':'Notifications by email','footer':'These are AO3’s own settings, saved to your AO3 account. Kudos never sends email.','rows':[{'label':'Comments on your works','kind':'toggle','on':True},{'label':'Kudos on your works','kind':'toggle','on':False},{'label':'Subscription updates','kind':'toggle','on':True},{'label':'Gift notifications','kind':'toggle','on':True}]},
  {'header':'Privacy on AO3','rows':[{'label':'Allow others to invite your works to collections','kind':'toggle','on':True},{'label':'Hide your email','kind':'toggle','on':True}]}]},1100)
add('Open-AO3','Account › Open AO3','FormScreen',{'title':'Open AO3','back':'Back to Account'},{
 'sections':[
  {'header':'Your account','rows':[{'label':'Dashboard','kind':'out','tile':'#821019','icon':I['dash']},{'label':'Gifts','kind':'out','tile':'#B3127A','icon':I['gift']},{'label':'Claims','kind':'out','tile':'#C25E00','icon':I['book']},{'label':'Co-creator requests','kind':'out','tile':'#7B3FA0','icon':I['users'],'badge':'1'},{'label':'Invitations','kind':'out','tile':'#1E63C8','icon':I['mail']},{'label':'Import works','kind':'out','tile':'#2F8F3A','icon':I['import']}]},
  {'header':'AO3','rows':[{'label':'FAQ','kind':'out','tile':'#6C6C70','icon':I['help']},{'label':'Terms of Service','kind':'out','tile':'#6C6C70','icon':I['doc']},{'label':'Content Policy','kind':'out','tile':'#6C6C70','icon':I['doc']},{'label':'Donate to the OTW','kind':'out','tile':'#821019','icon':I['heart']}],'footer':'These open AO3 in the in-app browser.'}]})
open('group1.list','w').write('\n'.join(f'{n}|{t}|{h}' for n,t,h in B))
print(len(B),'boards')
