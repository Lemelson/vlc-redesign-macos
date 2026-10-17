import sys,os,json; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from common import *
from desc import IDX, S
from collections import Counter, defaultdict, OrderedDict
d=load(); top=d['document']['children'][0]['children']
iconset=IDX['42:356'][0]
idx=json.load(open(ROOT+'/icons-svg/index.json'))
byNode={e['figmaNode']:e for e in idx['icons']}
use=json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'icon_use.json')))
tops={t['id']:t for t in top}
def props(nm):
    return OrderedDict(kv.split('=',1) for kv in nm.split(', '))
def classify(ch):
    fills=Counter(); strokes=Counter()
    for n,p,dep in walk(ch):
        if n is ch: continue
        if n.get('visible',True) is False: continue
        st=n.get('styles') or {}
        for key,sk,cnt in(('fills','fill',fills),('strokes','stroke',strokes)):
            for f in n.get(key,[]) or []:
                if f.get('type')=='SOLID' and f.get('visible',True):
                    sid=st.get(sk) or st.get(key)
                    nm=S[sid]['name'].replace('Dark/','') if sid else hexa(f['color'],f.get('opacity',1))[0]
                    cnt[nm]+=1
    if strokes and not fills: shape='outline'
    elif fills and not strokes: shape='filled'
    elif fills and strokes: shape='outline+fill'
    else: shape='empty'
    cols=sorted(set(list(fills)+list(strokes)))
    return shape, cols
def frames_str(fr):
    c=Counter(); comp=set()
    for lab,(vis,hid) in fr.items():
        if vis==0: continue
        nm,i=lab.rsplit(' (',1); i=i.rstrip(')')
        if tops[i]['type']=='COMPONENT_SET': comp.add(nm)
        else: c[nm]+=1
    parts=['%s%s'%(k,' ×%d'%v if v>1 else '') for k,v in sorted(c.items())]
    parts+=['[%s]'%k for k in sorted(comp)]
    return ', '.join(parts)
def hidden_only(fr):
    return all(v[0]==0 for v in fr.values())
rows=defaultdict(list); missing=[]; unused=[]
order=[]
for ch in iconset['children']:
    pr=props(ch['name']); name=pr.pop('name')
    if name not in rows: order.append(name)
    var=[]
    for k in ('state','direction','value','EQ'):
        if pr.get(k,'default')!='default': var.append('%s=%s'%(k,pr[k]))
    two=pr.get('two-tone')=='yes'
    shape,cols=classify(ch)
    e=byNode.get(ch['id'])
    fr=use.get(ch['id'],{})
    fs=frames_str(fr)
    if not fr: unused.append((name,', '.join(var),ch['id']))
    elif not fs: fs='(only in hidden layers: %s)'%', '.join(sorted(set(l.rsplit(' (',1)[0] for l in fr)))
    if not e: missing.append((name,ch['id'],fs))
    rows[name].append(('two-tone' if two else 'mono', ', '.join(var) or 'default', shape, ', '.join(cols), '`%s`'%e['file'] if e else '**MISSING**', ch['id'], fs or '—'))
L=[]
L.append('# Icon catalog (Figma component set `Icon`, node 42:356)\n')
L.append('Generated from `figma_file.json` (component set children, their vector paints, and every INSTANCE of them in the 104 other top-level frames) and `icons-svg/index.json`. Design: VLC Redesign by Juxtopposed, Figma community file https://www.figma.com/community/file/1691465999134370980, CC BY 4.0.\n')
L.append('- Variants in Figma: **%d** (all 24×24 COMPONENTs). SVGs in `icons-svg/`: **%d** (index.json `count` = %d). Variants used by at least one visible instance: **%d**; unused: **%d**.'%(len(iconset['children']),len(idx['icons']),idx['count'],len(iconset['children'])-len(unused),len(unused)))
L.append('- Variant axes in Figma: `name`, `direction` (left/right/up/down), `state` (default / active / selected), `value` (volume or thumbnail level), `EQ` (equalizer preset curve), `two-tone` (yes/no).')
L.append('- **mono** = functional, clickable icon: strokes `Dark/FG/A2` #8F8F8F, 1.5 px. **active** = orange `Dark/Accent/Main` (often filled, 2 px strokes). **two-tone** = decorative menu icon: gray `FG/A2` strokes + accent part in `Dark/Accent/DIm` #AB6314 (not Accent/Main). **selected** = variant used for the current item in the library rail / menus.')
L.append('- *Shape* is computed from the vectors: outline = strokes only, filled = fills only, outline+fill = both. *Colors* lists the styles (or raw hex) painted.')
L.append('- *Used in* lists top-level frames that contain a visible instance (×N = number of frames with that name); `[Name]` = only inside that component set definition (and therefore everywhere that component is placed). Frame ids: see `INDEX.md`.')
L.append('- File names follow `icons-svg/index.json`; when two variants share a name and props, the second file carries the node id (e.g. `album-6206-13653.svg`).\n')
L.append('## Missing from icons-svg\n')
L.append('| Icon | Node | Used in | Note |\n|---|---|---|---|')
notes={'check':'Plain (unselected) check glyph. It is the trailing slot of the `option` menu row component, so it appears in every menu/dropdown; it is drawn in Dark/FG/A2. Export it (only `check-active`, `check-selected`, `check-selected-two-tone` exist as SVG).',
       '0':'Empty 24×24 placeholder (no artwork). Used as the blank leading/trailing slot in menu rows, dropdown options and Customize tiles. Implement as an empty spacer; no SVG needed.'}
for name,i,fs in missing: L.append('| %s | %s | %s | %s |'%(name,i,fs,notes.get(name,'')))
L.append('\nNo other icon artwork is referenced outside the `Icon` set: a scan for loose vectors (6–48 px, outside any INSTANCE) in all screens found none. The VLC cone in the top bar is the `vlc` variant; thumbnails use the `thumbnail` variants. Note that some product imagery (cover art, video stills, cat placeholder) are IMAGE fills, not icons.\n')
L.append('## All variants\n')
L.append('| Icon | Tone | Variant | Shape | Colors | SVG file | Node | Used in |\n|---|---|---|---|---|---|---|---|')
for name in sorted(order,key=str.lower):
    for r in rows[name]:
        L.append('| %s | %s |'%(name,' | '.join(r)))
L.append('\n## Unused variants (%d)\n'%len(unused))
L.append('Defined in the set but never instanced in any frame (still exported as SVG where available): '+', '.join('%s%s (%s)'%(n,' ['+v+']' if v else '',i) for n,v,i in unused)+'.\n')
L.append('## Notes and inconsistencies\n')
L.append('- `icons-svg/index.json` names its source as Figma file `B7ifd32zHbliiZs9q00JG3`; `figma_file.json` was fetched from another copy of the same community file. Node ids match 1:1 (206/208 found; the 2 missing are listed above).')
L.append('- `subtitle` and `album` each have two variants with identical properties (different artwork); check the SVG before using either.')
L.append('- Several "active" variants mix raw hex #D37918/#8F8F8F with styled paints; treat raw #D37918 as `Accent/Main` and raw #8F8F8F as `FG/A2` so accent recoloring works.')
L.append('- Settings categories reuse icons: General and Performance both use `preferences` (sliders), per spec-part2 §14.')
open(REPO+'/redesign/design/figma/ICONS.md','w').write('\n'.join(L)+'\n')
print(len(missing),len(unused))
