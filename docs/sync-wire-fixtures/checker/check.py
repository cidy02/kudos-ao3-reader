#!/usr/bin/env python3
"""D5 fixed-byte vector checker. Python standard library only; --write is maintainer-only."""
import hashlib
import json
import pathlib
import struct
import sys
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAGIC = b'KJ9\x00'
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = (-121665 * pow(121666, P-2, P)) % P
I = pow(2, (P-1)//4, P)
B_Y = (4 * pow(5, P-2, P)) % P

def sha(b): return hashlib.sha256(b).digest()
def H(b): return hashlib.sha512(b).digest()
def inv(x): return pow(x, P-2, P)
def xrecover(y):
    xx = (y*y-1)*inv(D*y*y+1) % P
    x = pow(xx, (P+3)//8, P)
    if (x*x-xx) % P: x = x*I % P
    if x & 1: x = P-x
    return x
B = (xrecover(B_Y), B_Y)
def add(a,b):
    x,y=a; u,v=b; t=D*x*u*y*v % P
    return ((x*v+u*y)*inv(1+t)%P, (y*v+x*u)*inv(1-t)%P)
def mul(p,n):
    out=(0,1)
    while n:
        if n&1: out=add(out,p)
        p=add(p,p); n//=2
    return out
def enc(p): return (p[1] | ((p[0]&1)<<255)).to_bytes(32,'little')
def dec(b):
    if len(b)!=32: raise ValueError('point width')
    v=int.from_bytes(b,'little'); y=v&((1<<255)-1)
    if y>=P: raise ValueError('noncanonical point')
    x=xrecover(y)
    if (x&1)!=(v>>255): x=P-x
    q=(x,y)
    if enc(q)!=b: raise ValueError('noncanonical point')
    return q
def pub(seed): return enc(mul(B,int.from_bytes(H(seed)[:32],'little') & ((1<<254)-8) | (1<<254)))
def sign(seed,msg):
    h=H(seed); a=(int.from_bytes(h[:32],'little') & ((1<<254)-8)) | (1<<254)
    r=int.from_bytes(H(h[32:]+msg),'little')%L
    R=enc(mul(B,r)); A=enc(mul(B,a))
    s=(r+int.from_bytes(H(R+A+msg),'little')*a)%L
    return R+s.to_bytes(32,'little')
def verify(key,msg,sig):
    if len(sig)!=64: return False
    try: A=dec(key); R=dec(sig[:32])
    except ValueError: return False
    s=int.from_bytes(sig[32:],'little')
    if s>=L: return False
    h=int.from_bytes(H(sig[:32]+key+msg),'little')%L
    return enc(mul(B,s))==enc(add(R,mul(A,h)))

def cj(obj):
    # Fixtures use only ASCII keys/values and integers. This subset is byte-identical to JCS.
    def check(v):
        if isinstance(v,float): raise ValueError('float outside fixture subset')
        if isinstance(v,str) and not v.isascii(): raise ValueError('non-ASCII outside fixture subset')
        if isinstance(v,dict):
            for k,x in v.items(): check(k); check(x)
        if isinstance(v,list):
            for x in v: check(x)
    check(obj)
    return json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def parse_json(b):
    def pairs(ps):
        d={}
        for k,v in ps:
            if k in d: raise ValueError('duplicate JSON key')
            d[k]=v
        return d
    o=json.loads(b.decode('utf8'),object_pairs_hook=pairs)
    if cj(o)!=b: raise ValueError('noncanonical JSON')
    return o

def envelope(typ,payload):
    head=MAGIC+struct.pack('>HHBBHQ',9,0,typ,0,0,len(payload))
    return head+payload+sha(head+payload)
def parse_envelope(raw):
    if len(raw)<52 or raw[:4]!=MAGIC: raise ValueError('envelope magic/size')
    maj,minor,typ,flags,reserved,n=struct.unpack('>HHBBHQ',raw[4:20])
    if (maj,minor,flags,reserved)!=(9,0,0,0) or n>1<<30: raise ValueError('envelope version/limit')
    if len(raw)!=20+n+32 or sha(raw[:-32])!=raw[-32:]: raise ValueError('envelope digest/length')
    return typ,raw[20:-32]

def record(kind,body,seed=None):
    b=cj(body); pre=struct.pack('>IHH',len(b),kind,0)+b
    sig=sign(seed,b'Kudos-v9-authority\0'+struct.pack('>HI',kind,len(b))+b) if seed else b''
    return pre+struct.pack('>H',len(sig))+sig
def parse_record(raw,known_key=None):
    if len(raw)<10: raise ValueError('short record')
    n,kind,flags=struct.unpack('>IHH',raw[:8])
    if flags or len(raw)<10+n: raise ValueError('record flags/length')
    body=parse_json(raw[8:8+n]); siglen=struct.unpack('>H',raw[8+n:10+n])[0]
    if len(raw)!=10+n+siglen or siglen not in (0,64): raise ValueError('signature length')
    if siglen and known_key and not verify(known_key,b'Kudos-v9-authority\0'+struct.pack('>HI',kind,n)+raw[8:8+n],raw[10+n:]): raise ValueError('authority signature')
    return kind,body

def segment(header,records,seed):
    hb=cj(header); p=struct.pack('>I',len(hb))+hb+struct.pack('>I',len(records))+b''.join(records)
    digest=sha(p); writer=uuid.UUID(header['writer']).bytes
    msg=b'Kudos-v9-segment\0'+uuid.UUID(header['libraryID']).bytes+writer+struct.pack('>QQ',header['firstSeq'],header['lastSeq'])+digest
    return envelope(3,p+digest+sign(seed,msg))
def parse_segment(raw,key):
    typ,p=parse_envelope(raw)
    if typ!=3 or len(p)<104: raise ValueError('segment type/size')
    n=struct.unpack('>I',p[:4])[0]; h=parse_json(p[4:4+n]); count=struct.unpack('>I',p[4+n:8+n])[0]
    end=len(p)-96; pos=8+n; recs=[]
    for _ in range(count):
        if pos+10>end: raise ValueError('record truncation')
        size=struct.unpack('>I',p[pos:pos+4])[0]
        if pos+10+size>end: raise ValueError('record length')
        sl=struct.unpack('>H',p[pos+8+size:pos+10+size])[0]
        if pos+10+size+sl>end: raise ValueError('signature length')
        r=p[pos:pos+10+size+sl]; recs.append(parse_record(r,key)); pos+=len(r)
    if pos!=end or sha(p[:end])!=p[end:end+32]: raise ValueError('segment trailer')
    msg=b'Kudos-v9-segment\0'+uuid.UUID(h['libraryID']).bytes+uuid.UUID(h['writer']).bytes+struct.pack('>QQ',h['firstSeq'],h['lastSeq'])+p[end:end+32]
    if not verify(key,msg,p[end+32:]): raise ValueError('segment signature')
    if len(recs)!=h['lastSeq']-h['firstSeq']+1: raise ValueError('range/count')
    for i,(_,b) in enumerate(recs):
        if (b['libraryID'],b['writer'],b['seq'])!=(h['libraryID'],h['writer'],h['firstSeq']+i): raise ValueError('record identity')
    return h,recs

LIB='11111111-1111-4111-8111-111111111111'
WR='22222222-2222-4222-8222-222222222222'
FOUNDER=bytes(range(32)); KEY=pub(FOUNDER)
def op(seq,kind,code,payload=None,minor=0):
    return record(code,dict(schema=9,libraryID=LIB,writer=WR,seq=seq,counter=seq,kind=kind,target='33333333-3333-4333-8333-333333333333',groups=[],payload=payload or {},observed={},requires=[],minReaderMinor=minor),FOUNDER if code in (4,58,59) else None)
def head(a,b):
    return dict(schema=9,kind='segment',libraryID=LIB,writer=WR,firstSeq=a,lastSeq=b,firstCounter=a,lastCounter=b,requiresDigest=sha(b'').hex(),minReaderMinor=0,admissionHash='00'*32)
def obj(t,kind,**fields): return envelope(t,cj(dict(schema=9,kind=kind,libraryID=LIB,**fields)))
def vectors():
    check=obj(4,'checkpoint',cut=[dict(writer=WR,seq=1)],logicalCounter=1,retained=[],evidence=[],diagnostics=[],opaque=[],assetClosure=[],minReaderMinor=0)
    boot_unsigned=dict(schema=9,kind='bootstrap',libraryID=LIB,sourceV8ManifestSHA256='11'*32,checkpointHash=sha(check).hex(),founders=[dict(keyID=sha(KEY).hex(),publicKey=KEY.hex())],creatorWriter=WR,createdAt=0,bootstrapNonce='33'*32,minReaderMinor=0,signature=None)
    boot_sig=sign(FOUNDER,b'Kudos-v9-bootstrap\0'+sha(cj(boot_unsigned))).hex(); boot_unsigned['signature']=boot_sig
    admission=dict(schema=9,kind='admission',libraryID=LIB,writer=WR,writerPublicKey=KEY.hex(),writerKeyID=sha(KEY).hex(),authorKeyID=sha(KEY).hex(),authorityHead='root:'+sha(KEY).hex(),enrollOpId=None,createdAt=0,minReaderMinor=0,signature=None)
    admission['signature']=sign(FOUNDER,b'Kudos-v9-admit\0'+sha(cj(admission))).hex()
    blob=b'fixture epub bytes\n'; blob_raw=struct.pack('>Q',len(blob))+blob+sha(blob)
    return {
      'framing':(obj(6,'writerIndex',writer=WR,admissionHash='00'*32,rangePages=[],highSeq=0,signature='00'*64),'valid envelope and canonical JSON'),
      'signed-op':(segment(head(1,1),[op(1,'writer.enroll',58,{'authorKeyID':sha(KEY).hex(),'subjectKeyID':sha(pub(bytes.fromhex('55'*32))).hex(),'subjectPublicKey':pub(bytes.fromhex('55'*32)).hex(),'authorityHead':'root:'+sha(KEY).hex()})],FOUNDER),'authority signature and segment signature'),
      'checkpoint':(check,'empty structural checkpoint; reducer summary pending D4'),
      'gap':(segment(head(3,3),[op(3,'work.edit',5)],FOUNDER),'seq 3 received before seq 1-2'),
      'equivocation-a':(segment(head(2,2),[op(2,'work.edit',5,{'title':'A'})],FOUNDER),'one verified content for seq 2'),
      'equivocation-b':(segment(head(2,2),[op(2,'work.edit',5,{'title':'B'})],FOUNDER),'conflicting verified content for seq 2'),
      'bootstrap':(envelope(1,cj(boot_unsigned)),'signed v8-to-v9 descriptor'),
      'admission':(envelope(2,cj(admission)),'founder writer admission'),
      'opaque':(segment(head(4,4),[op(4,'future.kind',0x8000,{'opaque':'keep these bytes'},1)],FOUNDER),'future noncritical op preserved byte for byte'),
      'blob-reference':(segment(head(5,5),[op(5,'asset.write',6,{'digest':sha(blob).hex(),'size':len(blob),'mediaType':'application/epub+zip','owner':'33333333-3333-4333-8333-333333333333','assetKind':'epub','observedBase':None})],FOUNDER),'asset.write metadata reference to pending bytes'),
      'blob':(envelope(5,blob_raw),'digest-addressed blob framing')
    }

def main():
    expected=vectors(); names=sorted(expected)
    if '--write' in sys.argv:
        for name,(raw,note) in expected.items():
            (ROOT/(name+'.json')).write_text(json.dumps(dict(name=name,note=note,hex=raw.hex(),sha256=sha(raw).hex()),indent=2)+'\n')
        print('wrote',len(names),'vectors'); return
    seen=sorted(p.stem for p in ROOT.glob('*.json'))
    if seen!=names: raise ValueError('fixture inventory mismatch')
    for name in names:
        v=json.loads((ROOT/(name+'.json')).read_text()); raw=bytes.fromhex(v['hex'])
        if v['name']!=name or v['sha256']!=sha(raw).hex() or raw!=expected[name][0]: raise ValueError(name+': golden bytes changed')
        typ,p=parse_envelope(raw)
        if typ==3:
            h,recs=parse_segment(raw,KEY)
            if segment(h,[op(b['seq'],b['kind'],k,b['payload'],b['minReaderMinor']) for k,b in recs],FOUNDER)!=raw: raise ValueError(name+': segment round trip')
        elif name=='blob':
            n=struct.unpack('>Q',p[:8])[0]
            if len(p)!=8+n+32 or sha(p[8:8+n])!=p[-32:]: raise ValueError('blob digest')
            if envelope(typ,p)!=raw: raise ValueError('blob round trip')
        else:
            parsed=parse_json(p)
            if envelope(typ,cj(parsed))!=raw: raise ValueError(name+': JSON round trip')
            if name in ('bootstrap','admission'):
                sig=bytes.fromhex(parsed.pop('signature')); parsed['signature']=None
                domain=b'Kudos-v9-bootstrap\0' if name=='bootstrap' else b'Kudos-v9-admit\0'
                if not verify(KEY,domain+sha(cj(parsed)),sig): raise ValueError(name+' signature')
        print('PASS',name)
    a=parse_segment(bytes.fromhex(json.loads((ROOT/'equivocation-a.json').read_text())['hex']),KEY)[1][0][1]
    b=parse_segment(bytes.fromhex(json.loads((ROOT/'equivocation-b.json').read_text())['hex']),KEY)[1][0][1]
    assert (a['writer'],a['seq'])==(b['writer'],b['seq']) and a!=b
    assert parse_segment(bytes.fromhex(json.loads((ROOT/'gap.json').read_text())['hex']),KEY)[0]['firstSeq']==3
    signed=bytearray(bytes.fromhex(json.loads((ROOT/'signed-op.json').read_text())['hex']))
    signed[-1] ^= 1
    try: parse_segment(bytes(signed),KEY)
    except ValueError: pass
    else: raise ValueError('tampered outer digest accepted')
    signed=bytearray(bytes.fromhex(json.loads((ROOT/'signed-op.json').read_text())['hex']))
    signed[-33] ^= 1
    signed[-32:]=sha(signed[:-32])
    try: parse_segment(bytes(signed),KEY)
    except ValueError: pass
    else: raise ValueError('tampered segment signature accepted')
    print(f'OK: {len(names)} byte vectors; Ed25519 signatures, gap and equivocation checked; all round trips exact; 2 tamper cases rejected')
if __name__=='__main__': main()
