import json, os, struct
REPO=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../..'))
ROOT=REPO+'/redesign/design/figma'
_d=None
def load():
    global _d
    if _d is None: _d=json.load(open(os.path.join(ROOT,'figma_file.json')))
    return _d
def pngsize(p):
    with open(p,'rb') as f:
        h=f.read(24)
    return struct.unpack('>II',h[16:24])
def renders():
    out={}
    rd=os.path.join(ROOT,'renders')
    for dp,dn,fn in os.walk(rd):
        for f in fn:
            if f.endswith('.png'):
                full=os.path.join(dp,f); rel=os.path.relpath(full,rd)
                out[rel]=pngsize(full)
    return out
def walk(n,parent=None,depth=0):
    yield n,parent,depth
    for c in n.get('children',[]) or []:
        yield from walk(c,n,depth+1)
def hexa(c,op=1.0):
    r,g,b=[round(c[k]*255) for k in 'rgb']
    a=c.get('a',1)*op
    return '#%02X%02X%02X'%(r,g,b), round(a,4)
