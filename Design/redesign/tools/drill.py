import sys; sys.path.insert(0,'.')
from gen import board
from data import W, I, works
B=[]
def add(name,title,comp,attrs,data,h=844): board(name,title,comp,attrs,data,h); B.append((name,title,h))
add('Shelf-ReadingNow','Library › Reading Now','ListScreen',{'title':'Reading Now','subtitle':'7 works · most recently read first','back':'Back'},{
 'tools':[{'label':'Filters','icon':'filter'},{'label':'More: List or Grid, Sort, Select','icon':'more'}],
 'chips':[{'label':'All','on':True},{'label':'New chapters'},{'label':'Downloaded'}],
 'sections':[{'works':works('salt','north','hound','stars', salt={'progress':40,'progressLabel':'Ch 12 · 40%'}, north={'progress':75,'progressLabel':'Ch 9 · 75%'}, hound={'progress':62,'progressLabel':'Ch 4 · 62%'}, stars={'progress':18,'progressLabel':'Ch 2 · 18%'})}]},1000)
add('All-Collections','Library › Collections','ListScreen',{'title':'Collections','subtitle':'4 collections · 1 pinned to Home','back':'Back to Library'},{
 'tools':[{'label':'New Collection','icon':'plus'},{'label':'More: Sort, Select','icon':'more'}],
 'sections':[{'kind':'rows','rows':[
  {'title':'Austen Variations','sub':'12 works · on Home · updated today','tone':'#9C2F6B','initial':'A','square':True},
  {'title':'Baker Street','sub':'9 works · Oct 20','tone':'#B8892A','initial':'B','square':True},
  {'title':'Comfort Reads','sub':'15 works · Oct 2','tone':'#2F7A4A','initial':'C','square':True},
  {'title':'Lighthouses and Lanterns','sub':'6 works · September','tone':'#1E63C8','initial':'L','square':True}]}]})
open('drill.list','w').write('\n'.join(f'{n}|{t}|{h}' for n,t,h in B)); print(len(B))
