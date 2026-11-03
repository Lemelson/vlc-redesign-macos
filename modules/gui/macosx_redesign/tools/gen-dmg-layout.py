#!/usr/bin/env python3
"""Generate or check Resources/dmg/DS_Store: the Finder window layout of the release DMG.

package-dmg.sh copies this template into every DMG, so releases need no Finder automation. It is
written directly in Finder's .DS_Store format (a buddy-allocated file holding one B-tree of records,
see https://metacpan.org/dist/Mac-Finder-DSStore/view/DSStoreFormat.pod) from layout.json:
- '.' bwsp: window bounds; toolbar, sidebar, path and status bars hidden;
- '.' icvp: icon view, icon and text size, background picture (an alias record);
- '.' pBBk: the same picture as a bookmark (what current Finder reads first); '.' vstl: icon view;
- an Iloc (icon centre) per item.
The picture's alias and bookmark name only the volume and `.background/background.tiff`; Finder resolves
them by that volume name and path. The output depends on layout.json alone (same bytes on every Mac).

Usage: tools/gen-dmg-layout.py            regenerate the template
       tools/gen-dmg-layout.py --check    verify the checked-in template against layout.json
"""
import argparse
import json
from pathlib import Path
import plistlib
import struct
import sys

TOOLS = Path(__file__).resolve().parent
DMG = TOOLS.parent / 'Resources/dmg'
LAYOUT = DMG / 'layout.json'
TEMPLATE = DMG / 'DS_Store'
BACKGROUND = '.background/background.tiff'
PAGE = 0x1000


def load_layout():
    return json.loads(LAYOUT.read_text())


def window_bounds(layout):
    """Finder's frame: origin from the bottom left of the screen, height including the title bar."""
    window = layout['window']
    return '{{%d, %d}, {%d, %d}}' % (window['x'], window['y'], window['width'],
                                     window['height'] + window['titleBarHeight'])


# --- background picture: alias and bookmark -----------------------------------------------------
# Both are built from the volume name and the picture's path alone, so the template is the same on
# every Mac and carries nothing of the Mac that made it: no dates, file or volume ids, UUIDs, sizes,
# sandbox tokens or temporary folders (Foundation's own bookmark data has all of these). The release
# DMG is a new volume each time, so Finder resolves both by volume name and path anyway.

def alias_record(volume_name, relative):
    """Alias Manager record (version 2) for /Volumes/<volume_name>/<relative>, like Finder writes into
    icvp, with the volume and file ids and dates left unknown (0)."""
    target = Path(relative)
    carbon_volume = volume_name.encode('utf-8').replace(b':', b'/')
    carbon_name = target.name.encode('utf-8').replace(b':', b'/')
    header = struct.pack('>h28pI2shI64pII4s4shhI2s10s', 0, carbon_volume, 0, b'H+', 5, 0, carbon_name, 0, 0,
                         b'\0\0\0\0', b'\0\0\0\0', -1, -1, 0, b'\0\0', b'\0' * 10)
    def tag(number, data):
        return struct.pack('>hh', number, len(data)) + data + (b'\0' if len(data) & 1 else b'')
    def unicode(text):
        encoded = text.encode('utf-16-be')
        return struct.pack('>h', len(encoded) // 2) + encoded
    extras = (tag(0, target.parent.name.encode('utf-8'))
              + tag(2, ':'.join([volume_name, *target.parts]).encode('utf-8'))
              + tag(14, unicode(target.name)) + tag(15, unicode(volume_name))
              + tag(18, ('/' + relative).encode('utf-8')) + tag(19, f'/Volumes/{volume_name}'.encode('utf-8'))
              + struct.pack('>hh', -1, 0))
    body = header + extras
    return struct.pack('>4shh', b'\0\0\0\0', 8 + len(body), 2) + body


BOOKMARK_PATH, BOOKMARK_FILE_PROPERTIES = 0x1004, 0x1010
BOOKMARK_VOLUME_PATH, BOOKMARK_VOLUME_URL, BOOKMARK_VOLUME_NAME = 0x2002, 0x2005, 0x2010
BOOKMARK_KEYS = {BOOKMARK_PATH, BOOKMARK_FILE_PROPERTIES, BOOKMARK_VOLUME_PATH, BOOKMARK_VOLUME_URL, BOOKMARK_VOLUME_NAME}


def bookmark(volume_name, relative):
    """NSURL bookmark data ('book', the layout of CFURLCreateBookmarkData) holding only the path
    components, "a regular file" and the volume's mount point, URL and name. Foundation resolves it
    on any volume of that name (NSURL needs the file properties to; without them it finds nothing)."""
    data, offsets = bytearray(b'\0\0\0\0'), {}                 # the first TOC's offset goes first
    def item(kind, payload):
        offset = len(data)
        data.extend(struct.pack('<II', len(payload), kind) + payload + b'\0' * (-len(payload) % 4))
        return offset
    def string(text):
        return item(0x0101, text.encode('utf-8'))
    components = ['Volumes', volume_name, *Path(relative).parts]
    parts = [string(part) for part in components]
    offsets[BOOKMARK_PATH] = item(0x0601, struct.pack('<%dI' % len(parts), *parts))
    # Resource flags, valid-flags mask, reserved: "is a regular file", the first four flags known.
    offsets[BOOKMARK_FILE_PROPERTIES] = item(0x0201, struct.pack('<QQQ', 1, 0x0F, 0))
    offsets[BOOKMARK_VOLUME_URL] = item(0x0901, ('file:///Volumes/%s/' % volume_name.replace(' ', '%20')).encode('utf-8'))
    offsets[BOOKMARK_VOLUME_NAME] = string(volume_name)
    offsets[BOOKMARK_VOLUME_PATH] = string(f'/Volumes/{volume_name}')
    toc = len(data)
    entries = sorted(offsets.items())
    data.extend(struct.pack('<IIIII', 12 + 12 * len(entries), 0xFFFFFFFE, 1, 0, len(entries)))
    for key, offset in entries:
        data.extend(struct.pack('<III', key, offset, 0))
    data[0:4] = struct.pack('<I', toc)
    header = struct.pack('<4sIII', b'book', 64 + len(data), 0x10050000, 64) + b'\0' * 48
    return header + bytes(data)


def read_bookmark(data):
    """key -> value (strings, lists of strings) of bookmark data written by bookmark()."""
    if data[:4] != b'book':
        raise ValueError('not bookmark data')
    base = struct.unpack('<I', data[12:16])[0]
    def item(offset):
        length, kind = struct.unpack('<II', data[base + offset:base + offset + 8])
        payload = data[base + offset + 8:base + offset + 8 + length]
        if kind in (0x0101, 0x0901):
            return payload.decode('utf-8')
        if kind == 0x0601:
            return [item(entry) for entry in struct.unpack('<%dI' % (length // 4), payload)]
        return payload
    toc = base + struct.unpack('<I', data[base:base + 4])[0]
    _, magic, _, following, count = struct.unpack('<IIIII', data[toc:toc + 20])
    if magic != 0xFFFFFFFE or following != 0:
        raise ValueError('bookmark data has more than one table of contents')
    return {key: item(offset) for key, offset, _ in
            (struct.unpack('<III', data[toc + 20 + 12 * n:toc + 32 + 12 * n]) for n in range(count))}


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


def template(layout):
    name = layout['volumeName']
    return ds_store(records(layout, alias_record(name, BACKGROUND), bookmark(name, BACKGROUND)))


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
    try:
        marks = read_bookmark(values.get(('.', 'pBBk'), b''))
    except (ValueError, struct.error):
        marks = {}
    if marks.get(BOOKMARK_PATH) != ['Volumes', layout['volumeName'], *Path(BACKGROUND).parts]:
        problems.append(f'background bookmark does not point at {layout["volumeName"]}/{BACKGROUND}')
    if set(marks) - BOOKMARK_KEYS:
        problems.append('background bookmark carries more than the path and the volume name')
    if data != template(layout):
        problems.append('template is not the one layout.json generates')
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
        TEMPLATE.write_bytes(template(layout))
        problems = check(TEMPLATE.read_bytes(), layout)
        if problems:
            sys.exit('FAIL: ' + '; '.join(problems))
        print(f'wrote {TEMPLATE}')
