import sys; sys.path.insert(0,'.')
from gen import board
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): board(name,title,comp,attrs,data,h); B.append((name,title,h))
add('Settings-Library','Settings › Library','FormScreen',{'title':'Library','back':'Back to Settings'},{
 'sections':[{'header':'Opening a work','rows':[{'label':'Open straight into the reader','kind':'toggle','on':True,'sub':'Off: open Work Detail first'},{'label':'Ask before downloading on cellular','kind':'toggle','on':True}]},
  {'header':'When you finish a work','rows':[{'label':'Mark as Finished at the last page','kind':'toggle','on':True},{'label':'Keep the download','kind':'segments','options':['Always','30 days','Never'],'selected':1}]},
  {'header':'Shelves','rows':[{'label':'Edit Shelves','kind':'nav','detail':'6 shown'},{'label':'Default sort','kind':'nav','detail':'Recently read'}]},
  {'header':'Recently Deleted','rows':[{'label':'Keep deleted works for','kind':'value','detail':'90 days'}]}]})
add('Settings-Preservation','Settings › Preservation','FormScreen',{'title':'Preservation','back':'Back to Settings'},{
 'sections':[{'header':'Works that leave AO3','footer':'Kudos never deletes a work because AO3 lost it.','rows':[{'label':'Keep a copy of every saved work','kind':'toggle','on':True,'sub':'2 works are kept only in Kudos'},{'label':'Check what’s still on AO3','kind':'nav','detail':'Last: Oct 20'}]},
  {'header':'Originals','rows':[{'label':'Keep imported original files','kind':'toggle','on':True,'sub':'PDFs and EPUBs from other sites · 84 MB'},{'label':'Rebuild works from originals','kind':'nav'}]},
  {'header':'Series','rows':[{'label':'Ask to save the whole series','kind':'toggle','on':True}]}]})
add('Settings-Queues','Settings › Reading Queues','FormScreen',{'title':'Reading Queues','back':'Back to Settings'},{
 'sections':[{'header':'Want to Read','rows':[{'label':'Download queued works','kind':'segments','options':['Wi‑Fi','Always','Never'],'selected':0},{'label':'Download ahead','kind':'value','detail':'Next 3'}]},
  {'header':'New queues','rows':[{'label':'When I finish a work','kind':'segments','options':['Remove','Keep'],'selected':0},{'label':'Pin new queues to Home','kind':'toggle','on':False}]},
  {'rows':[{'label':'Manage Tags','kind':'nav','detail':'5'}]}]})
add('Settings-Account','Settings › Account and privacy','FormScreen',{'title':'Account & Privacy','back':'Back to Settings'},{
 'sections':[{'header':'AO3','rows':[{'label':'Logged in as saltwindow','sub':'Session stored on this iPhone only','kind':'info','avatar':True,'tile':'#23506B'},{'label':'AO3 Preferences','kind':'nav'},{'label':'Log Out','kind':'destructive'}]},
  {'header':'Mature works','rows':[{'label':'Hide mature content','kind':'toggle','on':False},{'label':'Blur covers of Mature and Explicit','kind':'toggle','on':True},{'label':'Require Face ID to reveal','kind':'toggle','on':True}]},
  {'header':'Privacy','rows':[{'label':'Privacy and Local Data','kind':'nav'}]}]})
add('Legal-Notices','Settings › About › Legal notices','FormScreen',{'title':'Legal Notices','back':'Back to About'},{
 'sections':[{'header':'Kudos','rows':[{'label':'Kudos','sub':'AGPL-3.0 · source on GitHub','kind':'out'}]},
  {'header':'Open-source parts','rows':[{'label':l,'sub':s,'kind':'nav'} for l,s in [('Readium Swift Toolkit','BSD-3-Clause'),('SwiftSoup','MIT'),('FluidAudio','Apache-2.0'),('Kokoro TTS voices','Apache-2.0'),('MuPDF','AGPL-3.0'),('Literata typeface (Android)','OFL-1.1')]]},
  {'header':'AO3','rows':[{'label':'Not affiliated with the OTW','sub':'Kudos is an independent reader for Archive of Our Own','kind':'info'}]}]})
add('Downloaded-Date','Work › Edit downloaded date (sheet)','FormScreen',{'title':'Downloaded','subtitle':'Imported works','mode':'sheet','confirm':'Save'},{
 'sections':[{'rows':[{'label':'Date','kind':'value','detail':'Oct 22, 2026'},{'label':'Time','kind':'value','detail':'21:40'}]},
  {'rows':[{'label':'Use the file’s date','kind':'button'}],'footer':'Imports take the date you imported them.'}]})
add('Local-Destination','Import › Where to put it (sheet)','FormScreen',{'title':'Add to Library','subtitle':'The Boy Who Lived Twice.pdf','mode':'sheet','confirm':'Add'},{
 'sections':[{'header':'Put it in','rows':[{'label':'Library only','kind':'check'},{'label':'Want to Read','kind':'check','on':True},{'label':'A Queue…','kind':'nav','detail':'Summer Reading'},{'label':'A Collection…','kind':'nav','detail':'None'}]},
  {'header':'Found in the file','rows':[{'label':'Source','kind':'value','detail':'FanFiction.net'},{'label':'Fandom','kind':'value','detail':'Harry Potter'},{'label':'Rating','kind':'value','detail':'T'}]}]})
open('group3.list','w').write('\n'.join(f'{n}|{t}|{h}' for n,t,h in B)); print(len(B))
