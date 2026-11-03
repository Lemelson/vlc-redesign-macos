#!/usr/bin/env python3
"""Generate or check Resources/dmg/DS_Store: the Finder window layout of the release DMG.

package-dmg.sh copies this template into every DMG, so releases need no Finder automation. It is
written directly in Finder's .DS_Store format (a buddy-allocated file holding one B-tree of records,
see https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod) from layout.json:
- '.' bwsp: window bounds; toolbar, sidebar, path and status bars hidden;
- '.' icvp: icon view, icon and text size, background picture (an alias record);
- '.' pBBk: the same picture as a bookmark (what current Finder reads first); '.' vstl: icon view;
- an Iloc (icon centre) per item.
The picture's alias and bookmark are made from a scratch HFS+ volume named like the DMG, holding
`.background/background.tiff` at the same path; Finder resolves them by that volume name and path.

Usage: tools/gen-dmg-layout.py            regenerate the template (mounts and ejects a scratch image)
       tools/gen-dmg-layout.py --check    verify the checked-in template against layout.json
"""
import argparse
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
DMG = TOOLS.parent / 'Resources/dmg'
LAYOUT = DMG / 'layout.json'
TEMPLATE = DMG / 'DS_Store'
BACKGROUND = '.background/background.tiff'
PAGE = 0x1000
MAC_EPOCH = datetime.datetime(1904, 1, 1, tzinfo=datetime.timezone.utc)


def load_layout():
    return json.loads(LAYOUT.read_text())


def window_bounds(layout):
    """Finder's frame: origin from the bottom left of the screen, height including the title bar."""
    window = layout['window']
    return '{{%d, %d}, {%d, %d}}' % (window['x'], window['y'], window['width'],
                                     window['height'] + window['titleBarHeight'])


# --- background picture: tiff, alias, bookmark --------------------------------------------------

def make_background_tiff(out):
    """The 1x and 2x pictures as one multi-resolution TIFF, which Finder picks per display."""
    subprocess.run(['tiffutil', '-cathidpicheck', str(DMG / 'background.png'), str(DMG / 'background@2x.png'),
                    '-out', str(out)], check=True, capture_output=True)


def mac_time(seconds):
    return int(seconds - MAC_EPOCH.timestamp())


def alias_record(volume, volume_name, relative):
    """Alias Manager record (version 2) for volume/relative, like Finder writes into icvp."""
    target = volume / relative
    folder = target.parent
    volume_date = mac_time(os.stat(volume).st_birthtime)
    target_date = mac_time(os.stat(target).st_birthtime)
    carbon_volume = volume_name.encode('utf-8').replace(b':', b'/')
    carbon_name = target.name.encode('utf-8').replace(b':', b'/')
    header = struct.pack('>h28pI2shI64pII4s4shhI2s10s', 0, carbon_volume, volume_date, b'H+', 5,
                         os.stat(folder).st_ino, carbon_name, os.stat(target).st_ino, target_date,
                         b'\0\0\0\0', b'\0\0\0\0', -1, -1, 0, b'\0\0', b'\0' * 10)
    def tag(number, data):
        return struct.pack('>hh', number, len(data)) + data + (b'\0' if len(data) & 1 else b'')
    def unicode(text):
        encoded = text.encode('utf-16-be')
        return struct.pack('>h', len(encoded) // 2) + encoded
    cnids, path = [], target.parent
    while path != volume:
        cnids.append(os.stat(path).st_ino)
        path = path.parent
    extras = (tag(0, folder.name.encode('utf-8'))
              + struct.pack('>hhQhhQ', 16, 8, volume_date * 65536, 17, 8, target_date * 65536)
              + tag(1, struct.pack('>%dI' % len(cnids), *cnids))
              + tag(2, ':'.join([volume_name, *Path(relative).parts]).encode('utf-8'))
              + tag(14, unicode(target.name)) + tag(15, unicode(volume_name))
              + tag(18, ('/' + relative).encode('utf-8')) + tag(19, str(volume).encode('utf-8'))
              + struct.pack('>hh', -1, 0))
    body = header + extras
    return struct.pack('>4shh', b'\0\0\0\0', 8 + len(body), 2) + body


def bookmark(path):
    """NSURL bookmark data for path (Foundation through JavaScript for Automation; no Apple events)."""
    script = ('ObjC.import("Foundation");'
              f'var url = $.NSURL.fileURLWithPath({json.dumps(str(path))});'
              'var data = url.bookmarkDataWithOptionsIncludingResourceValuesForKeysRelativeToURLError(0, $(), $(), null);'
              'data.base64EncodedStringWithOptions(0).js')
    result = subprocess.run(['osascript', '-l', 'JavaScript', '-e', script], capture_output=True, text=True, check=True)
    return base64.b64decode(result.stdout.strip())


def picture_references(volume_name):
    mount = Path('/Volumes') / volume_name
    if mount.exists():
        raise SystemExit(f'{mount} is in use; eject it first (the alias must name that mount point)')
    with tempfile.TemporaryDirectory(prefix='mxr-dmg-layout-') as scratch:
        image = Path(scratch) / 'layout.dmg'
        subprocess.run(['hdiutil', 'create', '-quiet', '-size', '8m', '-fs', 'HFS+', '-volname', volume_name,
                        '-type', 'UDIF', str(image)], check=True)
        subprocess.run(['hdiutil', 'attach', '-quiet', '-nobrowse', '-mountpoint', str(mount), str(image)], check=True)
        try:
            (mount / BACKGROUND).parent.mkdir()
            make_background_tiff(mount / BACKGROUND)
            return alias_record(mount, volume_name, BACKGROUND), bookmark(mount / BACKGROUND)
        finally:
            subprocess.run(['hdiutil', 'detach', '-quiet', str(mount)], check=True)


# --- .DS_Store ------------------------------------------------------------------------------------

def record_bytes(name, code, kind, value):
    encoded = name.encode('utf-16-be')
    out = struct.pack('>I', len(encoded) // 2) + encoded + code.encode('ascii') + kind.encode('ascii')
    if kind == 'blob':
        return out + struct.pack('>I', len(value)) + value
    if kind == 'long':
        return out + struct.pack('>I', value)
    if kind == 'type':
        return out + value
    raise ValueError(kind)


def records(layout, alias, bookmark_data):
    bwsp = {'ContainerShowSidebar': False, 'PreviewPaneVisibility': False, 'ShowPathbar': False,
            'ShowSidebar': False, 'ShowStatusBar': False, 'ShowTabView': False, 'ShowToolbar': False,
            'SidebarWidth': 0, 'WindowBounds': window_bounds(layout)}
    icvp = {'arrangeBy': 'none', 'backgroundColorBlue': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorRed': 1.0,
            'backgroundImageAlias': alias, 'backgroundType': 2, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
            'gridSpacing': 100.0, 'iconSize': float(layout['iconSize']), 'labelOnBottom': True,
            'scrollPositionX': 0.0, 'scrollPositionY': 0.0, 'showIconPreview': False, 'showItemInfo': False,
            'textSize': float(layout['textSize']), 'viewOptionsVersion': 1}
    entries = [('.', 'bwsp', 'blob', plistlib.dumps(bwsp, fmt=plistlib.FMT_BINARY, sort_keys=True)),
               ('.', 'icvp', 'blob', plistlib.dumps(icvp, fmt=plistlib.FMT_BINARY, sort_keys=True)),
               ('.', 'pBBk', 'blob', bookmark_data),
               ('.', 'vSrn', 'long', 1),
               ('.', 'vstl', 'type', b'icnv')]
    for name, (x, y) in layout['items'].items():
        entries.append((name, 'Iloc', 'blob', struct.pack('>IIII', x, y, 0xFFFFFFFF, 0xFFFF0000)))
    # Finder keeps records sorted by file name (case-insensitive), then by code.
    return sorted(entries, key=lambda entry: (entry[0].lower(), entry[1]))


def ds_store(entries):
    """Buddy allocator over 2^31 bytes: header 32@0, DSDB 32@32, allocator info 2048@2048,
    the one B-tree leaf 4096@4096; every other block is on the free lists."""
    leaf = struct.pack('>II', 0, len(entries)) + b''.join(record_bytes(*entry) for entry in entries)
    if len(leaf) > PAGE:
        raise ValueError('layout does not fit one B-tree page')
    used = {0: 5, 32: 5, 2048: 11, 4096: 12}           # offset -> log2(size)
    free = {size: [] for size in range(32)}
    for size in range(5, 31):                            # the buddies left over from splitting 2^31
        offset = 1 << size
        if offset not in used:
            free[size].append(offset)
    free[5] = [offset for offset in free[5] if offset not in used]
    addresses = [2048 | 11, 32 | 5, 4096 | 12]
    info = struct.pack('>II', len(addresses), 0) + struct.pack('>256I', *(addresses + [0] * (256 - len(addresses))))
    info += struct.pack('>I', 1) + bytes([4]) + b'DSDB' + struct.pack('>I', 1)
    for size in range(32):
        info += struct.pack('>I', len(free[size])) + b''.join(struct.pack('>I', offset) for offset in free[size])
    dsdb = struct.pack('>IIIII', 2, 0, len(entries), 1, PAGE)
    space = bytearray(8192)
    space[0:32] = struct.pack('>4sIII16s', b'Bud1', 2048, 2048, 2048,
                              bytes.fromhex('0000100c000000870000200b00000000'))
    space[32:32 + len(dsdb)] = dsdb
    space[2048:2048 + len(info)] = info
    space[4096:4096 + len(leaf)] = leaf
    return struct.pack('>I', 1) + bytes(space)


def read_ds_store(data):
    """(name, code) -> value for a file written by ds_store(): enough to check the template."""
    space = data[4:]
    magic, root, _, _ = struct.unpack('>4sIII', space[:16])
    if data[:4] != b'\0\0\0\1' or magic != b'Bud1':
        raise ValueError('not a .DS_Store file')
    count = struct.unpack('>I', space[root:root + 4])[0]
    addresses = struct.unpack('>%dI' % count, space[root + 8:root + 8 + 4 * count])
    def block(number):
        address = addresses[number]
        return space[address & ~0x1F:(address & ~0x1F) + (1 << (address & 0x1F))]
    directory = root + 8 + 4 * ((count + 255) // 256 * 256)
    entries = struct.unpack('>I', space[directory:directory + 4])[0]
    position, toc = directory + 4, {}
    for _ in range(entries):
        length = space[position]
        name = space[position + 1:position + 1 + length].decode('ascii')
        toc[name] = struct.unpack('>I', space[position + 1 + length:position + 5 + length])[0]
        position += 5 + length
    node_number, levels, _, _, _ = struct.unpack('>IIIII', block(toc['DSDB'])[:20])
    if levels != 0:
        raise ValueError('template has more than one B-tree level')
    node = block(node_number)
    _, total = struct.unpack('>II', node[:8])
    position, values = 8, {}
    for _ in range(total):
        length = struct.unpack('>I', node[position:position + 4])[0]
        name = node[position + 4:position + 4 + 2 * length].decode('utf-16-be')
        position += 4 + 2 * length
        code, kind = node[position:position + 4].decode('ascii'), node[position + 4:position + 8].decode('ascii')
        position += 8
        if kind == 'blob':
            size = struct.unpack('>I', node[position:position + 4])[0]
            value = node[position + 4:position + 4 + size]
            position += 4 + size
        elif kind == 'long':
            value = struct.unpack('>I', node[position:position + 4])[0]
            position += 4
        elif kind == 'type':
            value = node[position:position + 4]
            position += 4
        else:
            raise ValueError(f'unexpected record type {kind}')
        values[name, code] = value
    return values


LABEL_WIDTH = 150      # Finder wraps an icon label to about this width at 13 pt
LABEL_GAP = 4


def placement_problems(layout):
    """Every item, label included, lies inside one card of the picture with room to spare."""
    half, problems = layout['iconSize'] / 2, []
    for name, (x, y) in layout['items'].items():
        box = (x - max(half, LABEL_WIDTH / 2), y - half,
               x + max(half, LABEL_WIDTH / 2), y + half + LABEL_GAP + layout['textSize'] * 1.4)
        if not any(card['left'] + 4 <= box[0] and card['top'] + 4 <= box[1]
                   and box[2] <= card['right'] - 4 and box[3] <= card['bottom'] - 4 for card in layout['cards']):
            problems.append(f'{name} (with its label) does not fit inside a card')
    return problems


def check(data, layout):
    """Problems that keep data from showing layout.json's window."""
    values = read_ds_store(data)
    problems = []
    bwsp = plistlib.loads(values.get(('.', 'bwsp'), plistlib.dumps({})))
    if bwsp.get('WindowBounds') != window_bounds(layout):
        problems.append(f'window bounds {bwsp.get("WindowBounds")} != {window_bounds(layout)}')
    for key in ('ShowToolbar', 'ShowSidebar', 'ShowStatusBar', 'ShowPathbar', 'ShowTabView'):
        if bwsp.get(key) is not False:
            problems.append(f'{key} is not off')
    icvp = plistlib.loads(values.get(('.', 'icvp'), plistlib.dumps({})))
    if icvp.get('iconSize') != layout['iconSize'] or icvp.get('textSize') != layout['textSize']:
        problems.append('icon or text size differs from layout.json')
    if icvp.get('backgroundType') != 2 or icvp.get('arrangeBy') != 'none':
        problems.append('no background picture or icons are auto-arranged')
    alias = icvp.get('backgroundImageAlias', b'')
    carbon = ':'.join([layout['volumeName'], *Path(BACKGROUND).parts]).encode('utf-8')
    if carbon not in alias or ('/' + BACKGROUND).encode('utf-8') not in alias:
        problems.append(f'background alias does not point at {layout["volumeName"]}/{BACKGROUND}')
    if BACKGROUND.encode('utf-8').split(b'/')[-1] not in values.get(('.', 'pBBk'), b''):
        problems.append('background bookmark is missing')
    if values.get(('.', 'vstl')) != b'icnv':
        problems.append('window does not open in icon view')
    for name, (x, y) in layout['items'].items():
        location = values.get((name, 'Iloc'))
        if location is None or struct.unpack('>II', location[:8]) != (x, y):
            problems.append(f'{name} is not at {x}, {y}')
    problems += placement_problems(layout)
    extra = sorted({name for name, _ in values} - {'.', *layout['items']})
    if extra:
        problems.append('records for unknown items: ' + ', '.join(extra))
    return problems


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='verify the checked-in template; change nothing')
    args = parser.parse_args()
    layout = load_layout()
    if args.check:
        problems = check(TEMPLATE.read_bytes(), layout)
        if problems:
            sys.exit('FAIL: ' + '; '.join(problems) + ' (run tools/gen-dmg-layout.py)')
        print('PASS: DS_Store template matches layout.json')
    else:
        alias, bookmark_data = picture_references(layout['volumeName'])
        TEMPLATE.write_bytes(ds_store(records(layout, alias, bookmark_data)))
        problems = check(TEMPLATE.read_bytes(), layout)
        if problems:
            sys.exit('FAIL: ' + '; '.join(problems))
        print(f'wrote {TEMPLATE}')
