import sys,os,json,re; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from common import *
from desc import IDX
from collections import Counter, defaultdict
d=load(); S=d['styles']
OUT=REPO+'/redesign/design/tokens'
os.makedirs(OUT,exist_ok=True)
SRC={'file':'redesign/design/figma/figma_file.json','figmaFileName':d['name'],'figmaVersion':d['version'],'lastModified':d['lastModified'],
     'communityFile':'https://www.figma.com/community/file/1691465999134370980','license':'CC BY 4.0 - VLC Redesign by Juxtopposed (attribution required)'}
pal={p['name']:p for p in json.load(open(ROOT+'/palette/tokens.json'))['paintStyles']}
def camel(path):
    # 'FG/A1' -> fgA1 ; 'BG/Accent Bright' -> bgAccentBright ; 'Accent/DIm' -> accentDim
    parts=re.split(r'[/ ]+',path)
    out=[]
    for i,p in enumerate(parts):
        if p=='DIm': p='Dim'
        if i==0: out.append(p.lower())
        else: out.append(p[0].upper()+p[1:])
    return ''.join(out)
# ---------- colors: resolve from nodes
use=defaultdict(Counter); ex=defaultdict(list)
for n,par,dep in walk(d['document']):
    st=n.get('styles') or {}
    for kind,sid in st.items():
        if sid not in S or S[sid]['styleType']!='FILL': continue
        key='fills' if kind in('fill','fills') else ('strokes' if kind in('stroke','strokes') else None)
        if not key: continue
        for p in n.get(key,[]) or []:
            if p.get('type')=='SOLID' and p.get('visible',True):
                h,a=hexa(p['color'],p.get('opacity',1)); use[sid][(h,a)]+=1
                if n['id'] not in ex[sid] and len(ex[sid])<3: ex[sid].append(n['id'])
colors={'meta':{'source':SRC,'units':'hex sRGB + alpha 0..1','howDerived':'Each Figma paint style was resolved from the fills/strokes of the nodes that reference it (usageCount = number of paints). Styles that no node references cannot be resolved from figma_file.json (the REST /files response does not carry style values); for those the value comes from redesign/design/figma/palette/tokens.json (a Figma style dump made by another fork) and resolvedFrom says so.'},
        'dark':{},'light':{}}
issues=[]
for sid,v in sorted(S.items(),key=lambda x:x[1]['name']):
    if v['styleType']!='FILL': continue
    theme,rest=v['name'].split('/',1)
    tok=camel(rest)
    u=use.get(sid)
    if u:
        (h,a),c=u.most_common(1)[0]
        e={'hex':h,'alpha':a,'figmaStyle':v['name'],'styleId':sid,'usageCount':sum(u.values()),'resolvedFrom':'nodes','exampleNodes':ex[sid]}
        if len(u)>1: e['otherValuesSeen']=[{'hex':k[0],'alpha':k[1],'count':c2} for k,c2 in u.most_common()[1:]]
        p=pal.get(v['name'])
        if p and (p['hex'].upper()!=h or abs(p.get('opacity',1)-a)>0.01): issues.append('%s: nodes give %s@%s but palette/tokens.json says %s@%s'%(v['name'],h,a,p['hex'],p.get('opacity',1)))
    else:
        p=pal.get(v['name'])
        e={'hex':p['hex'].upper() if p else None,'alpha':round(p.get('opacity',1),4) if p else None,'figmaStyle':v['name'],'styleId':sid,'usageCount':0,
           'resolvedFrom':'palette/tokens.json (style not referenced by any node in figma_file.json)' if p else 'UNRESOLVED'}
    colors['dark' if theme=='Dark' else 'light'][tok]=e
# notes
colors['dark']['accentDim']['note']='Figma style name is misspelled "Accent/DIm"'
colors['light']['accentDim']['note']='Figma style name is misspelled "Accent/DIm"'
colors['light']['fg1']['note']='Light/FG/1 equals Dark/FG/1 (#EAEAEA) - near-white text on a light theme; almost certainly a designer mistake. Unused in the file.'
colors['light']['fg2']['note']='Light/FG/2 equals Dark/FG/2 (#C6C6C6); same suspected mistake. Unused in the file.'
colors['dark']['bgAccentDark']['note']='Mostly used for slider tick marks drawn over the filled (accent) part of sliders ("degrees" vectors in settings/sidebar sliders), plus selected accent-swatch frame.'
colors['dark']['bgB2Transparent']['note']='Defined but never used in the file; intended for modal scrims (spec-part2 token table).'
colors['dark']['accentBright']['note']='Defined but never used by any node; hover/pressed accent per spec (estimate).'
# light-theme completeness
light_used=[k for k,v in colors['light'].items() if v['usageCount']]
colors['meta']['lightThemeCoverage']='Only %d of %d Light styles are referenced, all inside frame "Player - Light" (2425:13624); that frame still uses many Dark styles (e.g. Dark/FG/A2 on control-bar icons, Dark/FG/A1 on library rows). Treat the Light palette as a mapping table, not as a verified design.'%(len(light_used),len(colors['light']))
# accents
acc_frames=[('orange','#D37918','1902:3670','Onboarding-1.png'),('red','#E15032','1902:4020','Onboarding-3.png'),('olive','#C49E23','1902:4325','Onboarding-4.png'),
 ('green','#19A234','1902:4634','Onboarding-5.png'),('teal','#18AAD3','1902:4940','Onboarding-6.png'),('blue','#185DD3','1902:5245','Onboarding-7.png'),
 ('purple','#8E42FF','1902:5550','Onboarding-8.png'),('pink','#F052B3','1902:6160','Onboarding-9.png'),('gray','#AFAFAF','1902:6465','Onboarding-10.png')]
# verify: Next button fill in each frame
def nextfill(fid):
    for n,p,dep in walk(IDX[fid][0]):
        if n['type']=='TEXT' and n.get('characters')=='Next':
            f=p.get('fills') or []
            if f and f[0]['type']=='SOLID': return hexa(f[0]['color'])[0]
sw=[]
for i,(nm,hx,fid,png) in enumerate(acc_frames):
    nf=nextfill(fid)
    if nf!=hx: issues.append('accent %s: expected %s, Next button fill in %s is %s'%(nm,hx,fid,nf))
    sw.append({'order':i+1,'name':nm,'hex':hx,'default':i==0,'verifiedIn':{'node':fid,'render':'renders/'+png,'how':'fill of the "Next" button and the selected color dot'},
               'settingsSwatchNode':None})
# settings swatches in Settings - global (3046:98xx)
gl=[]
for n,p,dep in walk(IDX['999:5047'][0]):
    if n['type'] in('FRAME','RECTANGLE','ELLIPSE') and n.get('fills'):
        f=n['fills'][0]
        if f.get('type')=='SOLID':
            h=hexa(f['color'])[0]
            for s in sw:
                if s['hex']==h and s['settingsSwatchNode'] is None and n['absoluteBoundingBox']['width']<=40: s['settingsSwatchNode']=n['id']
blue_fill=IDX['1925:9940'][0]['fills'][0]
blue_hex,blue_alpha=hexa(blue_fill['color'],blue_fill.get('opacity',1))
if blue_hex!='#185DD3': issues.append('blue seek fill 1925:9940: expected #185DD3, got '+blue_hex)
colors['accentSwatches']={'note':'The 9 accent options, in display order, as used by the Onboarding theme/color step (Onboarding-1, -3 ... -10) and the Settings > General "Accent color" row. Only orange has a named style set (Accent/Main, Bright, Dim, Logo, BG/Accent Bright, BG/Accent Dark); for the other 8 the designer applied the raw hex to the same elements and replaced Dark/BG/Accent Bright (seek-bar fill) with the accent at 24% opacity, except blue at 30% (node 1925:9940 in frame 1902:5245). The selected color-dot ring uses the accent at 30% opacity (verified in frames 1902:4020 ... 1902:6465). Derive Bright/Dim/BG tints for non-orange accents with these rules; record the method in code.',
  'derivationRule':{'bgAccentBright':'accent @ alpha 0.24 over the surface; blue uses bgAccentBrightOverrides (orange reference: #D37918@0.24 over #090909 = #39240D vs style #371F06)',
                    'bgAccentBrightOverrides':{'blue':{'alpha':blue_alpha,'node':'1925:9940','frame':'1902:5245'}},
                    'selectedRing':'accent @ alpha 0.30, 4 px','text/glyph on accent':'Dark/FG/B1 #161616'},
  'swatches':sw}
# unstyled raw colors that recur
colors['rawColors']={'note':'Frequently used colors that are NOT bound to a style (count = paints in the whole file). Use these only where noted.',
 'items':[
  {'hex':'#FFFFFF','alpha':0.06,'use':'Icon Wrapper hover background (177:99); library rail icon hover','node':'177:99'},
  {'hex':'#303030','alpha':1,'use':'placeholder thumbnail background in library rows / icon "thumbnail" (417 paints)','node':'2404:9202'},
  {'hex':'#262626','alpha':1,'use':'volume cone body behind the gradient fill (244:213)','node':'244:213'},
  {'hex':'#000000','alpha':0.2,'use':'darkening overlay on the volume gradient and on thumbnail images','node':'244:214'},
  {'hex':'#171717','alpha':1,'use':'Home grid card background under thumbnail images (r12)','node':'6841:14982'},
  {'hex':'#FFFFFF','alpha':0.14,'use':'subtitle-timeline cue blocks on the seek bar (20x24 r1)','node':'3749:12473'},
  {'hex':'#FFFFFF','alpha':0.21,'use':'1.5 px stroke around the white color-field swatch (Settings > Subtitles text color)','node':'3191:18739'},
  {'hex':'#5C5C5C','alpha':0.25,'use':'keycap bottom "3D" drop shadow (0,6,0) in Onboarding shortcuts','node':'1902:7075'},
 ]}
colors['gradients']={'volumeCone':{'node':'244:214','type':'linear, left to right across the full 86 px cone','stops':[{'hex':'#95D318','pos':0},{'hex':'#B2A918','pos':0.579},{'hex':'#D37918','pos':0.792},{'hex':'#FF3737','pos':1.0}],'overlay':'#000000 @ 0.20','body':'#262626','track':'Dark/BG/B2 #090909','note':'The fill is a clip of fixed width per volume step (see metrics.json volume.fillWidthByStep); the gradient is mapped to the full cone, so higher volume reveals orange/red.'},
  'onboardingSystemTile':{'node':'1902:3991','stops':[{'hex':'#AFAFAF','pos':0.5},{'hex':'#222222','pos':0.5}],'note':'hard diagonal split for the "System" theme tile'}}
colors['meta']['issues']=issues
json.dump(colors,open(OUT+'/colors.json','w'),indent=2,ensure_ascii=False)
print('colors issues',issues)
# ---------- typography
combos=Counter(); ex=defaultdict(list); col=defaultdict(Counter); samples=defaultdict(list)
for n,p,dep in walk(d['document']):
    if n['type']!='TEXT': continue
    s=n['style']
    k=(s.get('fontFamily'),s.get('fontWeight'),round(s.get('fontSize'),3),round(s.get('lineHeightPx',0),2),s.get('lineHeightUnit'),round(s.get('letterSpacing',0),3))
    combos[k]+=1
    if len(ex[k])<4: ex[k].append(n['id'])
    t=n.get('characters','')[:40]
    if len(samples[k])<4 and t not in samples[k]: samples[k].append(t)
    st=n.get('styles') or {}
    if 'fill' in st: col[k][S[st['fill']]['name']]+=1
    else:
        for f in n.get('fills',[]):
            if f.get('type')=='SOLID': col[k][hexa(f['color'],f.get('opacity',1))[0]]+=1
NAMES={('Inter',400,14.0):'body',('Inter',400,12.0):'caption',('Inter',400,16.0,19.36):'bodyLarge',('Inter',500,16.0):'sectionHeader',('Inter',400,15.0):'time',
 ('Inter',600,14.0):'button',('Inter',400,8.0):'thumbGlyph',('Inter',500,10.0):'iconDigits',('Inter',300,16.0,28.0):'onboardingBody',('Inter',300,16.0,19.36):'onboardingTileLabel',
 ('Inter',600,16.0):'buttonLarge',('Inter',400,14.0,24.5):'dialogHint',('DM Mono',400,14.0):'keycap',('Inter',400,16.0,28.0):'dialogSectionTitle',('Inter',300,24.0):'onboardingTitle',
 ('Inter',500,14.0):'chapterNumber',('Inter',400,20.0):'homeSectionTitle',('Inter',500,24.0):'nowPlayingTitle',('Inter',400,24.0):'onboardingTitleRegular',('Inter',300,32.0):'welcomeTitle',('Inter',700,7.467):'hdrBadge'}
ROLE={'body':'default UI text: labels, menu items, list rows, window title, setting labels','caption':'toggle ON/OFF, slider scale labels, small hints','bodyLarge':'library breadcrumb/titles, settings page title, category headers','sectionHeader':'settings section headings (Dark/FG/2) and sidebar section headers',
 'time':'control-bar current time / duration, seek-preview time','button':'dialog buttons (Cancel/Save), Continue Watching','thumbGlyph':'"▶" placeholder glyph in library thumbnails','iconDigits':'"10"/"15" digits inside skip icons','onboardingBody':'onboarding paragraph + shortcut labels','onboardingTileLabel':'theme tile labels (Light/Dark/System)',
 'buttonLarge':'onboarding Next/Back/Finish, folder chip','dialogHint':'dialog helper text, Keyboard Shortcuts column headers','keycap':'Keyboard Shortcuts key fields','dialogSectionTitle':'dialog section titles (Network URL, Basic, Playback)','onboardingTitle':'onboarding step title','chapterNumber':'chapter numbers (accent)',
 'homeSectionTitle':'full-library Home section titles','nowPlayingTitle':'music now-playing "title - artist"','onboardingTitleRegular':'onboarding step title (regular variant)','welcomeTitle':'"Welcome to VLC!"','hdrBadge':'"HDR" text inside the HDR icon (icon artwork, not UI text)'}
styles=[];scaled=[]
for k,v in combos.most_common():
    fam,w,size,lh,lhu,ls=k
    rec={'fontFamily':fam,'fontWeight':w,'fontSize':size,'lineHeightPx':lh,'lineHeight':'auto (Figma INTRINSIC, ~1.21 em for Inter)' if lhu=='INTRINSIC_%' else '%g px (%g%%)'%(lh,round(lh/size*100)),'letterSpacing':ls,
         'usageCount':v,'exampleNodes':ex[k],'sampleText':samples[k],'colors':dict(col[k].most_common(4))}
    nm=NAMES.get((fam,w,size,lh)) or NAMES.get((fam,w,size))
    if size in(7.7,8.8,8.25,4.4) or (size<8 and nm is None):
        rec['note']='scaled copy (x0.55) of the player inside the Onboarding theme preview; not a real text style'; scaled.append(rec); continue
    if size==700.0:
        rec['note']='Figma canvas section label ("Components"/"Designs"); not UI'; scaled.append(rec); continue
    rec['name']=nm; rec['role']=ROLE.get(nm,'')
    styles.append(rec)
typo={'meta':{'source':SRC,'howDerived':'Every TEXT node in figma_file.json grouped by (family, weight, size, line height, letter spacing). The file defines NO text styles (0 TEXT styles), so names below are proposed. textCase is ORIGINAL and italic false everywhere. Inline overrides (styleOverrideTable) exist on 21 nodes: SemiBold 600 for the time inside the resume toast, FG/A3 for "(optional)" and "%" suffixes, FG/1 for the edited time, strikethrough in one hidden toast.',
  'fontFiles':'Inter (weights 300/400/500/600/700) and DM Mono 400 - bundle both (SIL OFL).','distinctCombos':len(combos)},
  'styles':styles,'excluded':scaled,
  'inlineOverrides':[{'node':'1922:9584','text':'You already watched till 00:04:80.','override':'time portion Inter 600'},{'node':'6251:13901','text':'Playlist Name (optional)','override':'"(optional)" fill Dark/FG/A3'},{'node':'1904:7242','text':'00:02:10','override':'Current Time click/edit state: fill Dark/FG/1, size 15'},{'node':'2245:9804','text':'100 %','override':'"%" fill Dark/FG/A3'},{'node':'774:1026','text':'0 px','override':'unit fill Dark/FG/A4'}]}
json.dump(typo,open(OUT+'/typography.json','w'),indent=2,ensure_ascii=False)
print('typo styles',len(styles),'excluded',len(scaled))
# ---------- metrics
def bbx(i): return IDX[i][0]['absoluteBoundingBox']
def N(i): return IDX[i][0]
def m(i,**extra):
    n=N(i); b=n['absoluteBoundingBox']
    r={'node':i,'w':round(b['width'],3),'h':round(b['height'],3)}
    if n.get('cornerRadius'): r['radius']=n['cornerRadius']
    if n.get('rectangleCornerRadii') and len(set(n['rectangleCornerRadii']))>1: r['radii']=n['rectangleCornerRadii']
    if n.get('layoutMode') in('HORIZONTAL','VERTICAL'):
        r['gap']=n.get('itemSpacing',0); r['padding']=[n.get('paddingTop',0),n.get('paddingRight',0),n.get('paddingBottom',0),n.get('paddingLeft',0)]
    r.update(extra); return r
R=Counter(); G=Counter(); P=Counter(); SW=Counter()
for n,p,dep in walk(d['document']):
    if n.get('cornerRadius') and n['type'] not in('VECTOR','BOOLEAN_OPERATION'): R[n['cornerRadius']]+=1
    if n.get('layoutMode') in('HORIZONTAL','VERTICAL'):
        G[n.get('itemSpacing',0)]+=1; P[(n.get('paddingTop',0),n.get('paddingRight',0),n.get('paddingBottom',0),n.get('paddingLeft',0))]+=1
    if n.get('strokes') and any(s.get('visible',True) for s in n['strokes']): SW[(n.get('strokeWeight'),n.get('strokeAlign'))]+=1
def clean(c,limit,skipfrac=True):
    out=[]
    for k,v in c.most_common():
        vals=k if isinstance(k,tuple) else (k,)
        if skipfrac and any(isinstance(x,float) and abs(x*2-round(x*2))>0.01 for x in vals if x is not None): continue
        out.append({'value':list(k) if isinstance(k,tuple) else k,'count':v})
        if len(out)>=limit: break
    return out
vol={c['name'].split('=')[1]:round([x for x in c['children'] if x['type']=='GROUP'][0]['absoluteBoundingBox']['width'],1) for c in N('244:184')['children']}
pb=bbx('491:1781'); qb=bbx('463:831')
metrics={'meta':{'source':SRC,'units':'Figma px at 1x = macOS points. Player frames are 1920x1080; renders are 2x.','howDerived':'Named values are read directly from the listed node (absoluteBoundingBox, cornerRadius, itemSpacing, padding [top,right,bottom,left]); distributions are counts over every node in the file. Fractional values produced by the 0.55x onboarding preview are excluded from distributions.'},
 'radius':{'scale':{'xs':2,'sm':3,'md':4,'lg':6,'xl':10,'xxl':14,'toast':16,'videoFrame':19,'albumArt':20},
   'usage':{'2':'settings category row, Advanced Options bar, EQ panel, library thumb','3':'toggle knob/track','4':'icon button, seek fill/playhead, segmented segment, sidebar Button, dropdown option, thumbnail image','6':'play button, time labels, dropdown, toggle base, segmented container, menu row, dialog buttons, folder chip, settings nav card/search','10':'side panels (queue/tracks/settings sidebar), menus, context menus','12':'Home grid cards','14':'dialogs, settings window, onboarding window, miniplayer, seek thumbnail','16':'resume toast','19':'video frame (inner rounded video area)','20':'music cover art','100':'full circle (onboarding color dots, round markers)'},
   'distribution':clean(R,16)},
 'spacing':{'gapDistribution':clean(G,16),'paddingDistribution':clean(P,16),'note':'Dominant auto-layout gaps: 10 (default), 8, 20, 12, 14, 16, 5, 4, 6, 2, 1 (tab strips).'},
 'stroke':{'distribution':clean(SW,10),'divider':{'weight':1,'color':'Dark/Divider/Dim','node':'6062:13362'},'controlBarTopBorder':{'weight':1,'align':'INSIDE','color':'Dark/Divider/Dim','node':'491:1779'},
   'iconStroke':{'default':1.5,'active':2.0,'note':'from vectors in the Icon set (42:356): mono/two-tone default 1.5 px, many active variants 2 px'},'dash':{'customizeOutline':[4,4],'subtitleConnector':{'dash':[8,8],'color':'Dark/Divider/Bright','node':'1911:7954'}},
   'videoFrame':{'weight':20,'align':'CENTER','color':'Dark/BG/A3','node':'6586:17371','note':'20 px centered stroke around the r19 video area = visible 10 px window frame'}},
 'effects':{'bgBlur':{'type':'background blur','radius':50,'style':'bg blur','usedOn':'top bar, control bar, side panels, library panel, video frame, thumbnail, toast'},
   'menuShadow':{'style':'bg blur + shadow','blur':50,'shadow':{'x':0,'y':8,'blur':15,'spread':0,'color':'#000000','alpha':0.46},'usedOn':'menus, context menus, dialogs, settings window, volume tooltip'},
   'miniplayerShadow':{'x':0,'y':0,'blur':11.8,'color':'#000000','alpha':0.38,'node':'970:3090'},
   'onboardingShadow':{'x':0,'y':4,'blur':11.8,'color':'#000000','alpha':0.38,'node':'1899:3055'},
   'dropdownListShadow':{'x':0,'y':4,'blur':13.8,'color':'#000000','alpha':0.35,'node':'2372:8307'},
   'presetListShadow':{'x':0,'y':0,'blur':14,'spread':8,'color':'#000000','alpha':0.35,'node':'2372:8838'},
   'keycapShadow':{'x':0,'y':6,'blur':0,'color':'#5C5C5C','alpha':0.25,'node':'1902:7075'},
   'albumArtGlow':{'x':0,'y':0,'blur':90.5,'spread':64,'color':'#FFFFFF','alpha':0.03,'node':'4777:24028'},
   'albumBackdropBlur':{'type':'layer blur','radius':20,'node':'4777:24034','note':'1952x1952 scaled cover art behind the music player'},
   'onboardingPreviewBlur':{'type':'background blur','radius':27.5,'note':'= 50 x 0.55 scale of the preview player'}},
 'window':{'player':m('247:445',fill='Dark/BG/A3'),'videoArea':m('6586:17371',note='frame 1920x1005 between top bar and control bar; content clipped to r19 with 10 px padding'),
   'topBar':m('247:447',fill='Dark/BG/A3 (+bg blur)'),'topBarLeftGroup':m('247:448'),'logoCell':m('247:449'),'folderChip':m('247:459'),'windowControlCell':m('247:466'),'windowControlsGroup':m('247:464')},
 'controlBar':{'bar':m('491:1779',fill='Dark/BG/A3 Transparent (+bg blur), 1px top Dark/Divider/Dim'),'transportGroup':m('3603:12301'),'prevNextCell':m('3603:12302'),
   'playButton':m('848:1711',fill='Dark/Accent/Main, glyph Dark/FG/B1'),'pauseButton':m('848:1713',fill='Dark/FG/A3'),'seekGroup':m('1908:7385'),'timeLabel':m('1904:7237'),
   'seekTrack':m('1908:7387',fill='Dark/BG/B2'),'seekFill':m('1908:7388',fill='Dark/BG/Accent Bright'),'playhead':m('1908:7389',fill='Dark/Accent/Main'),
   'volumeGroup':m('491:1731'),'trackButtonsGroup':m('491:1728'),'iconButton':m('177:97',hoverFill='#FFFFFF@0.06'),'musicTransportGroup':m('4778:26182'),
   'volumeTooltip':m('2245:9805',fill='Dark/BG/B1 Transparent + bg blur + shadow'),'seekThumbnail':m('2151:9673',fill='Dark/BG/A3 Transparent + bg blur'),'seekThumbnailImage':m('2151:9674')},
 'volume':{'cone':m('244:210'),'fillWidthByStep':vol,'maxPercent':200},
 'sidePanels':{'queuePanel':m('463:831',fill='Dark/BG/B1 Transparent + bg blur'),'tracksPopup':m('491:2243'),'settingsSidebar':m('5187:24308'),
   'placement':{'rightInset':pb['x']+pb['width']-(qb['x']+qb['width']),'gapAboveControlBar':pb['y']-(qb['y']+qb['height']),'gapBelowTopBar':20,'note':'946 = 1080 - 40 (top bar) - 54 (control bar) - 2x20'},
   'tabStrip':m('463:832',fill='Dark/BG/B2'),'tabCell3':m('463:833'),'tabCell4wide':m('5187:24310'),'tabCell4narrow':m('5187:24315'),'tabUnderline':{'h':2,'color':'Dark/Accent/Main'},
   'queueHeaderRow':m('463:840'),'sectionHeaderRow':m('491:2252'),'listContainer':m('491:2258'),'listRow':m('491:2260'),'footer':m('505:3083'),'footerButton':m('500:3062',hoverFill='Dark/BG/A4')},
 'library':{'sidebar':m('848:1995'),'rail':m('848:1867',fill='Dark/BG/A4'),'panel':m('848:1872',fill='Dark/BG/B1 Transparent + bg blur'),'headerBlock':m('848:1873'),'headerRow':m('848:1874'),'mediaRow':m('2404:9179'),'thumb':m('2404:9180'),
   'fullWindowNavColumn':m('970:3324'),'fullWindowNavCard':m('970:3325',fill='Dark/BG/A4'),'homeCard':m('6841:14982')},
 'miniplayer':{'collapsed':m('970:3090'),'expanded':m('970:3092'),'videoBlock':m('970:3055'),'infoBlock':m('970:3062'),'queue':m('970:3180')},
 'menus':{'appMenu':m('6062:13354'),'appMenuRow':m('6062:13492'),'contextMenu':m('2139:8935'),'contextMenuRow':m('2107:5934'),'rightClickMenu':m('6065:13616',note='no blur/shadow effect in Figma'),'rightClickRow':m('6077:14345'),'rowHoverFill':'Dark/BG/A2','profilesSubmenu':m('6648:20514'),'menuIcon':24},
 'controls':{'toggle':m('536:1013'),'toggleKnob':m('536:1011'),'toggleLabelCell':m('536:1010'),'segmented':m('804:1207'),'segment':m('804:1202'),'dropdown':m('2372:8299'),'dropdownOption':m('2372:8360'),'dropdownOpenList':m('2372:8307'),
   'stackedChoice':m('3176:16555'),'stackedChoiceRow':m('3176:16549'),'dialogButton':m('1915:8659'),'dialogPrimaryButton':m('1915:8663',disabledOpacity=0.5),'dialogHeaderDropdown':m('1959:5324')},
 'dialogs':{'settings':m('999:5047'),'settingsHeader':m('999:5048'),'settingsSearch':m('1040:2512'),'settingsNavColumn':m('999:5060'),'settingsNavCard':m('999:5061'),'settingsCategoryRow':m('3021:9836'),'settingsContent':m('1088:4049'),
   'settingsSectionHeaderRow':m('3046:9858'),'settingsRowTall':m('3046:9860'),'settingsRow':m('3046:9895'),'advancedOptionsBar':m('3046:9907'),'equalizerPanel':m('3178:16770'),
   'addSubtitles':m('1911:7545'),'addSubtitlesHeader':m('1911:7546'),'dialogFooter':m('1915:8662'),'keyboardShortcuts':m('2437:14832'),'openNetworkStream':m('6216:13614'),'openNetworkStreamHeader':m('6216:13615'),'dialogBody':m('6216:13623'),'newPlaylist':m('6259:14954'),
   'onboarding':m('1899:3055'),'onboardingButton':m('1902:3383'),'themeTile':m('1902:3980'),'colorDot':m('1902:4003'),'resumeToast':m('1919:9580'),'resumeContinueButton':m('1922:9581'),'resumeCloseButton':m('6309:14029')},
 'standardHeights':{'topBar':40,'controlBar':54,'controlItem':28,'iconButton':32,'tabStrip':50,'panelSectionHeader':60,'listRow':32,'menuRow':48,'dropdown':48,'dropdownOption':44,'settingsRow':'42-46','settingsSectionHeader':39,'advancedOptionsBar':38,'dialogHeaderSimple':50,'dialogHeaderWithToolbar':96,'dialogFooter':72,'button':32,'textField':34,'toggle':32,'segmented':44},
 'standardWidths':{'sidePanel':400,'panelContent':360,'libraryRail':50,'libraryPanel':377,'libraryPanelContent':337,'fullLibraryNav':217,'appMenu':375,'contextMenu':265,'rightClickMenu':292,'settingsWindow':1048,'settingsNav':216,'settingsContent':832,'settingsControlColumn':'364 (dropdown) / 213 (segmented) / 68 (toggle)','dialogLarge':1048,'dialogSmall':713,'onboarding':1090,'miniplayer':391,'seekThumbnail':272,'button':100}}
json.dump(metrics,open(OUT+'/metrics.json','w'),indent=2,ensure_ascii=False)
print('ok')
