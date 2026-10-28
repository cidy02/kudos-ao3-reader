import sys; sys.path.insert(0,'.')
from gen import board
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): board(name,title,comp,attrs,data,h); B.append((name,title,h))

# AO3 collections
add('AO3-Collection-Page','AO3 collection page','ListScreen',{'title':'Austen Exchange 2026','subtitle':'Gift exchange · 214 works · 98 members · moderated','back':'Back'},{
 'tools':[{'label':'Join','text':'Join'},{'label':'More: Profile, Rules, Share','icon':'more'}],
 'chips':[{'label':'Works','on':True},{'label':'Bookmarks'},{'label':'Prompts'},{'label':'Participants'},{'label':'Profile'}],
 'sections':[{'header':'Recent','count':'214','works':works('map','letters',map={'updated':'Gift for elinor_d · Oct 26'},letters={'updated':'Gift for lizzy_reads · Oct 25'}), 'summary':True}]},1000)
add('AO3-Collection-Items','AO3 collections › Your items','ListScreen',{'title':'Your Items','subtitle':'5 works and bookmarks in collections','back':'Back','tab':'writing'},{
 'segments':{'options':['Awaiting','Approved','Rejected'],'selected':0},
 'sections':[{'kind':'rows','rows':[
  {'title':'Small Weathers','kicker':'Persuasion Prompt Meme','sub':'Invited by a maintainer · Oct 24','tone':'#7A4040','glyph':I['doc'],'square':True,'action':'Approve'},
  {'title':'Keeper of the Northern Light','kicker':'Lighthouse Week 2026','sub':'You submitted · waiting for a moderator','tone':'#2F6D6A','glyph':I['doc'],'square':True,'badge':'Waiting','badgeBg':'#EFEFF4','badgeFg':'#3A3A3C'}]}]})
add('AO3-Collection-Form','AO3 collections › New or edit (form)','FormScreen',{'title':'New Collection','subtitle':'On AO3','mode':'sheet','confirm':'Create'},{
 'sections':[{'header':'Names','rows':[{'label':'Name','kind':'field','text':'lighthouse_week_2026'},{'label':'Title','kind':'field','text':'Lighthouse Week 2026'}],'footer':'The name is the address on AO3: letters, digits and underscores.'},
  {'header':'About','rows':[{'kind':'textarea','placeholder':'Description','rows':3},{'label':'Parent collection','kind':'nav','detail':'None'}]},
  {'header':'Settings','rows':[{'label':'Moderated','kind':'toggle','on':True},{'label':'Closed','kind':'toggle','on':False},{'label':'Unrevealed','kind':'toggle','on':False,'sub':'Works stay hidden until you reveal them'},{'label':'Anonymous','kind':'toggle','on':False,'sub':'Creators stay hidden until you reveal them'}]},
  {'header':'Type','rows':[{'label':'Challenge','kind':'segments','options':['None','Gift exchange','Prompt meme'],'selected':0}]}]},1000)
add('AO3-Collection-Moderation','AO3 collections › Moderation','ListScreen',{'title':'Moderation','subtitle':'Lighthouse Week 2026 · 3 waiting','back':'Back'},{
 'segments':{'options':['Waiting','Approved','Rejected'],'selected':0},
 'sections':[{'kind':'rows','rows':[
  {'title':'Fog Signal','kicker':'Original Work','sub':'by tidewright · submitted 2 h ago','tone':'#2F6D6A','glyph':I['doc'],'square':True,'action':'Approve'},
  {'title':'The Keeper’s Daughter','kicker':'Original Work','sub':'by inkwell_moth · yesterday','tone':'#1F4E5F','glyph':I['doc'],'square':True,'action':'Approve'},
  {'title':'Bookmark of “Salt & Starlight”','kicker':'Bookmark','sub':'by marginalia · Oct 25','tone':'#6C6C70','glyph':I['book'],'square':True,'action':'Approve'}]}]})
add('AO3-Collection-Maintainers','AO3 collections › Maintainers','ListScreen',{'title':'Maintainers','subtitle':'Lighthouse Week 2026','back':'Back'},{
 'tools':[{'label':'Invite','icon':'plus'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'saltwindow','sub':'You','tone':'#23506B','badge':'Owner','badgeBg':'#990000'},
  {'title':'tidewright','sub':'Joined Sep 2024','tone':'#2F6D6A','badge':'Moderator','badgeBg':'#1E63C8'},
  {'title':'marginalia','sub':'Invited Oct 20','tone':'#7A4040','badge':'Invited','badgeBg':'#EFEFF4','badgeFg':'#3A3A3C'}]}]})

# Challenges
add('Challenge-SignUp','Challenge › Sign up (form)','FormScreen',{'title':'Sign Up','subtitle':'Austen Exchange 2026','back':'Back','confirm':'Submit'},{
 'sections':[{'header':'Request 1','rows':[{'label':'Fandom','kind':'chips','chips':['Persuasion']},{'label':'Characters','kind':'chips','chips':['Anne Elliot','Frederick Wentworth']},{'kind':'textarea','text':'Letters, rain, a second chance that takes its time.','rows':2}]},
  {'header':'Offer 1','rows':[{'label':'Fandom','kind':'chips','chips':['Pride and Prejudice']},{'label':'Characters','kind':'chips','chips':['Elizabeth Bennet','any']},{'label':'Add Another Offer','kind':'button'}]},
  {'header':'Your sign-up','rows':[{'label':'Pseud','kind':'nav','detail':'saltwindow'},{'label':'Make sign-up public','kind':'toggle','on':False}],'footer':'Sign-ups close Nov 1, 23:59 UTC.'}]},1000)
add('Challenge-SignUps','Challenge › Sign-ups (maintainer)','ListScreen',{'title':'Sign-ups','subtitle':'Austen Exchange 2026 · 98 sign-ups · closes Nov 1','back':'Back'},{
 'tools':[{'label':'More: Export, Close Sign-ups','icon':'more'}],
 'chips':[{'label':'All','on':True},{'label':'Incomplete 4'},{'label':'Pinch hitters 6'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'quietharbor','sub':'Requests Persuasion · offers Pride and Prejudice, Emma','tone':'#3E5B3A'},
  {'title':'anne_at_lyme','sub':'Requests Persuasion ×2 · offers Northanger Abbey','tone':'#6B4E23'},
  {'title':'lizzy_reads','sub':'Requests Pride and Prejudice · offer missing','tone':'#7A4040','badge':'Incomplete','badgeBg':'#FFF4E5','badgeFg':'#6B3A00'},
  {'title':'elinor_d','sub':'Requests Sense and Sensibility · offers Persuasion','tone':'#4A3D6A'}]}]})
add('Challenge-Assignments','Challenge › Assignments','ListScreen',{'title':'Assignments','subtitle':'Austen Exchange 2026 · works due Nov 12','back':'Back','tab':'writing'},{
 'sections':[{'header':'Yours','kind':'rows','rows':[{'title':'Writing for quietharbor','sub':'Persuasion · Anne Elliot/Frederick Wentworth · 0 of 5,000 words','tone':'#7B3FA0','glyph':I['gift'],'square':True,'badge':'15 days','badgeBg':'#FFF4E5','badgeFg':'#6B3A00','bar':0,'barLabel':'0 of 5,000 words'}]},
  {'header':'Pinch hits open','kind':'rows','rows':[{'title':'For elinor_d','sub':'Sense and Sensibility · original writer defaulted','tone':'#1E63C8','glyph':I['gift'],'square':True,'action':'Claim'}]}]})
add('Challenge-Settings','Challenge › Settings (maintainer)','FormScreen',{'title':'Challenge Settings','subtitle':'Austen Exchange 2026','back':'Back','confirm':'Save'},{
 'sections':[{'header':'Dates','rows':[{'label':'Sign-ups open','kind':'value','detail':'Oct 1'},{'label':'Sign-ups close','kind':'value','detail':'Nov 1'},{'label':'Works due','kind':'value','detail':'Nov 12'},{'label':'Works revealed','kind':'value','detail':'Dec 1'}]},
  {'header':'Sign-ups','rows':[{'label':'Sign-up open','kind':'toggle','on':True},{'label':'Requests per person','kind':'value','detail':'1–3'},{'label':'Offers per person','kind':'value','detail':'1–3'},{'label':'Tag sets','kind':'nav','detail':'Austen Exchange 2026'}]},
  {'header':'Matching','rows':[{'label':'Match on','kind':'segments','options':['Fandom','Characters','Both'],'selected':2},{'label':'Generate Potential Matches','kind':'button'}]}]},1000)
add('Prompt-Meme','Challenge › Prompt meme','ListScreen',{'title':'Persuasion Prompt Meme','subtitle':'142 prompts · 38 claimed · 21 filled','back':'Back'},{
 'tools':[{'label':'New Prompt','icon':'plus'}],
 'chips':[{'label':'All','on':True},{'label':'Unclaimed'},{'label':'Claimed by me'},{'label':'Filled'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Anne, rain, a borrowed coat','sub':'Anne Elliot/Frederick Wentworth · claimed by you','tone':'#7B3FA0','glyph':I['chat'],'square':True,'badge':'Claimed','badgeBg':'#990000'},
  {'title':'The navy list, read aloud','sub':'Gen · 2 claims · 1 fill','tone':'#7B3FA0','glyph':I['chat'],'square':True,'action':'Claim'},
  {'title':'Lyme, the morning after','sub':'Louisa Musgrove, Anne Elliot · unclaimed','tone':'#7B3FA0','glyph':I['chat'],'square':True,'action':'Claim'},
  {'title':'Kellynch, years later','sub':'Anne Elliot/Frederick Wentworth · 1 fill','tone':'#7B3FA0','glyph':I['chat'],'square':True,'action':'Claim'}]}]})
add('Prompt-Tags','Challenge › Prompt tags (maintainer)','FormScreen',{'title':'Tag Set','subtitle':'Austen Exchange 2026','back':'Back','confirm':'Save'},{
 'sections':[{'header':'Fandoms','rows':[{'label':'Allowed','kind':'chips','chips':['Persuasion','Pride and Prejudice','Emma','Northanger Abbey','+3']}]},
  {'header':'Characters','rows':[{'label':'Allowed','kind':'chips','chips':['Anne Elliot','Frederick Wentworth','Elizabeth Bennet','+41']},{'label':'Let participants nominate','kind':'toggle','on':True}]},
  {'header':'Nominations','rows':[{'label':'Review nominations','kind':'nav','badge':'12'}]}]})

# Writing
add('Writing-Chapters','Writing › a work’s chapters','ListScreen',{'title':'What the Tide Keeps','subtitle':'3 of 8 chapters posted · 9,800 words','back':'Back to Your Works','tab':'writing'},{
 'tools':[{'label':'Add Chapter','icon':'plus'},{'label':'More: Reorder, Edit Work','icon':'more'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'1. Low Water','sub':'3,210 words · posted Sep 28 · 84 comments','handle':True},
  {'title':'2. The Lamp Room','sub':'3,350 words · posted Oct 9 · 61 comments','handle':True},
  {'title':'3. Fog Bell','sub':'3,240 words · posted Oct 20 · 41 comments','handle':True},
  {'title':'4. Slack Water','sub':'1,240 words · draft, edited yesterday','handle':True,'badge':'Draft','badgeBg':'#EFEFF4','badgeFg':'#3A3A3C'}]}]})
add('Chapter-Add','Writing › Add Chapter (form)','FormScreen',{'title':'New Chapter','subtitle':'What the Tide Keeps · Chapter 5','mode':'sheet','trailing':'Post…'},{
 'sections':[{'rows':[{'label':'Title','kind':'field','placeholder':'Chapter title (optional)'},{'label':'Number','kind':'value','detail':'5 of 8'}]},
  {'header':'Summary','rows':[{'kind':'textarea','placeholder':'Optional','rows':2}]},
  {'header':'Notes','rows':[{'label':'Beginning notes','kind':'nav','detail':'None'},{'label':'End notes','kind':'nav','detail':'None'}]},
  {'header':'Text','rows':[{'label':'Write Chapter','kind':'nav','detail':'Empty','icon':I['pen']},{'label':'Import from a File…','kind':'nav','icon':I['import']}]},
  {'rows':[{'label':'Preview','kind':'button'},{'label':'Save as Draft','kind':'button'}]}]},960)
add('Post-Tags','Post a work › Tags','FormScreen',{'title':'Tags','back':'Back to Post','search':'Add a tag'},{
 'sections':[{'header':'Fandoms · required','rows':[{'label':'Fandoms','kind':'chips','chips':['Original Work']}]},
  {'header':'Relationships','rows':[{'label':'Relationships','kind':'chips','chips':['Original Female Character/Original Female Character']}]},
  {'header':'Characters','rows':[{'label':'Characters','kind':'chips','chips':['Original Characters']}]},
  {'header':'Additional tags','rows':[{'label':'Tags','kind':'chips','chips':['Lighthouses','Slow Burn','Found Family']}]},
  {'header':'Suggestions for “light”','rows':[{'label':'Lighthouse Keepers','sub':'2,904 works','kind':'nav'},{'label':'Lighthouses','sub':'6,120 works · added','kind':'check','on':True},{'label':'Light Angst','sub':'98k works','kind':'nav'}]}]},1000)
add('Post-Creators','Post a work › Co-creators','FormScreen',{'title':'Creators','back':'Back to Post','search':'Invite a co-creator by name'},{
 'sections':[{'header':'Creators','rows':[{'label':'saltwindow','sub':'You · this pseud','kind':'check','on':True,'avatar':True,'tile':'#23506B'},{'label':'tidewright','sub':'Invited · they accept on AO3','kind':'info','avatar':True,'tile':'#2F6D6A','badge':'Invited'}]},
  {'rows':[{'label':'Post under another pseud','kind':'nav','detail':'saltwindow'}]}]})
add('Post-Series','Post a work › Series','FormScreen',{'title':'Series','back':'Back to Post'},{
 'sections':[{'header':'Add to a series','rows':[{'label':'None','kind':'check'},{'label':'Lantern Season','sub':'3 parts · becomes part 4','kind':'check','on':True}]},
  {'rows':[{'label':'New Series…','kind':'button'}]}]})
add('Post-Parent','Post a work › Inspired by','FormScreen',{'title':'Inspired By','back':'Back to Post'},{
 'sections':[{'header':'Parent work','footer':'AO3 lets the parent’s creator know, unless they turned that off.','rows':[{'label':'AO3 link','kind':'field','text':'archiveofourown.org/works/48211093'},{'label':'The Lighthouse Keepers','sub':'tidewright · Original Work · found on AO3','kind':'check','on':True}]},
  {'header':'Not on AO3','rows':[{'label':'Title','kind':'field','placeholder':'Title'},{'label':'Link','kind':'field','placeholder':'https://'},{'label':'Translation of this work','kind':'toggle','on':False}]}]})
add('Post-CollectionsGifts','Post a work › Collections and gifts','FormScreen',{'title':'Collections & Gifts','back':'Back to Post'},{
 'sections':[{'header':'Collections','rows':[{'label':'Add to','kind':'chips','chips':['Lighthouse Week 2026']},{'label':'Add a Collection…','kind':'button'}]},
  {'header':'Gift for','footer':'Gifts go to an AO3 user or a name off AO3.','rows':[{'label':'Recipients','kind':'chips','chips':['quietharbor']},{'label':'Add a Recipient…','kind':'button'}]},
  {'header':'Challenge','rows':[{'label':'For an assignment','kind':'nav','detail':'Austen Exchange 2026'}]}]})
add('Series-Edit','Writing › Edit Series','FormScreen',{'title':'Edit Series','subtitle':'Lantern Season','back':'Back','confirm':'Save'},{
 'sections':[{'header':'Title','rows':[{'kind':'field','text':'Lantern Season'}]},
  {'header':'Summary','rows':[{'kind':'textarea','text':'Three keepers, three winters, one light.','rows':2}]},
  {'rows':[{'label':'Complete','kind':'toggle','on':False},{'label':'Reorder Works','kind':'nav','detail':'3'},{'label':'Remove Works','kind':'nav'}]},
  {'rows':[{'label':'Delete Series','kind':'destructive'}],'footer':'The works stay; only the series goes.'}]})

# Reader
add('Reader-PageJump','Reader › Go to Page (sheet)','FormScreen',{'title':'Go to Page','subtitle':'Chapter 7 · The Salt Road','mode':'sheet','confirm':'Go'},{
 'sections':[{'rows':[{'label':'Page','kind':'field','text':'4'},{'label':'of 18 in this chapter','kind':'info','colour':'#6C6C70'}]},
  {'header':'Or a chapter','rows':[{'label':'6. The Inland Sea','kind':'nav','detail':'p. 1'},{'label':'7. The Salt Road','kind':'check','on':True},{'label':'8. Shingle','kind':'nav','detail':'p. 1'}]},
  {'rows':[{'label':'Back to Where I Was','kind':'button'}]}]})
add('Reader-CustomizeTheme','Reader › Customize Theme','FormScreen',{'title':'Customize Theme','subtitle':'Sepia','back':'Back to Themes','confirm':'Save'},{
 'hero':{'title':'Aa · The road to the coast','sub':'Preview in New York, 19 pt','colour':'#9A6732','icon':'M4 19 9 5l5 14M6 14h6M15 19l3-8 3 8M16 16.5h4'},
 'sections':[{'header':'Colours','rows':[{'label':'Paper','kind':'swatches','colours':['#FBF0D9','#F4ECD8','#EDE3CC','#FFFFFF'],'selected':0},{'label':'Text','kind':'swatches','colours':['#5B4636','#3B2F1E','#1F1B16'],'selected':0},{'label':'Links','kind':'swatches','colours':['#9A6732','#990000','#1E63C8'],'selected':0}]},
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
