import sys,os,json; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from common import *
d=load(); S=d['styles']
IDX={}
for n,p,dep in walk(d['document']): IDX[n['id']]=(n,p)
def paints(n,key,skey):
    out=[]
    st=n.get('styles') or {}
    sid=st.get(skey) or st.get(skey+'s')
    for p in n.get(key,[]) or []:
        if p.get('visible',True) is False: continue
        if p['type']=='SOLID':
            h,a=hexa(p['color'],p.get('opacity',1)); out.append((S[sid]['name'] if sid else '')+'='+h+('' if a==1 else '@%.2f'%a))
        else: out.append(p['type'])
    return out
def desc(n,ind=''):
    bb=n.get('absoluteBoundingBox') or {}
    s='%s%s %s "%s" %gx%g'%(ind,n['id'],n['type'],n['name'][:40],bb.get('width',0),bb.get('height',0))
    if n.get('cornerRadius'): s+=' r=%g'%n['cornerRadius']
    if n.get('rectangleCornerRadii'): s+=' radii=%s'%n['rectangleCornerRadii']
    if n.get('layoutMode') and n['layoutMode']!='NONE':
        s+=' AL:%s gap=%s pad=%s,%s,%s,%s'%(n['layoutMode'][0],n.get('itemSpacing',0),n.get('paddingTop',0),n.get('paddingRight',0),n.get('paddingBottom',0),n.get('paddingLeft',0))
        if n.get('primaryAxisAlignItems'): s+=' main=%s'%n['primaryAxisAlignItems']
        if n.get('counterAxisAlignItems'): s+=' cross=%s'%n['counterAxisAlignItems']
    f=paints(n,'fills','fill')
    if f: s+=' fill=%s'%f
    k=paints(n,'strokes','stroke')
    if k: s+=' stroke=%s w=%s %s%s'%(k,n.get('strokeWeight'),n.get('strokeAlign'),(' dash=%s'%n['strokeDashes']) if n.get('strokeDashes') else '')
    if n.get('individualStrokeWeights'): s+=' isw=%s'%n['individualStrokeWeights']
    ef=[e for e in n.get('effects',[]) if e.get('visible',True)]
    if ef: s+=' fx=%s'%[(e['type'],e.get('radius'),e.get('offset') and (e['offset']['x'],e['offset']['y']),e.get('color') and hexa(e['color']),e.get('spread')) for e in ef]
    if n.get('opacity',1)!=1: s+=' op=%.2f'%n['opacity']
    if n['type']=='TEXT': s+=' "%s" %s/%s/%s'%(n['characters'][:25],n['style'].get('fontWeight'),n['style'].get('fontSize'),round(n['style'].get('lineHeightPx',0),1))
    if n.get('visible',True) is False: s+=' [HIDDEN]'
    return s
def tree(nid,maxd=2,ind=''):
    n=IDX[nid][0] if isinstance(nid,str) else nid
    print(desc(n,ind))
    if maxd>0:
        for c in n.get('children',[]) or []: tree(c,maxd-1,ind+'  ')
if __name__=='__main__':
    md=int(sys.argv[1])
    for a in sys.argv[2:]: tree(a,md); print()
