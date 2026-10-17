#!/usr/bin/env python3
"""Generate the icon asset catalog and the typed icon table from the Figma SVG export.

Inputs:  redesign/design/figma/icons-svg/*.svg + index.json (Figma component set `Icon`, 42:356;
         see redesign/design/figma/ICONS.md), plus EMPTY_VARIANTS below.
Outputs: modules/gui/macosx_redesign/Sources/MXRDesign/Resources/Icons.xcassets  (rewritten)
         modules/gui/macosx_redesign/Sources/MXRDesign/Generated/Icons.swift

Every SVG is split into layers by paint color, keeping document order (consecutive elements with
the same color form one layer, so overlaps stack exactly as in Figma). Each layer becomes a
vector-preserving template imageset; `MXRIcon` stacks the layers and tints each one by its role:

    #8F8F8F  Dark/FG/A2      -> base       (the icon tint, `Theme.Color.fgA2` by default)
    #D37918  Dark/Accent/Main -> accent     (`Theme.Color.accentMain`, follows the accent)
    #AB6314  Dark/Accent/DIm  -> accentDim  (`Theme.Color.accentDim`, follows the accent)
    #303030  thumbnail fill   -> placeholder (`Theme.Color.thumbPlaceholder`)
    #373737  Dark/Divider/Bright -> divider (`Theme.Color.dividerBright`)

Accent/Main and Accent/Logo share #D37918 in Dark, so the color alone cannot tell them apart. The
roles of an icon's accent paths therefore also come from figma_file.json: when the instances of a
component paint its vectors with an `Accent/Logo` style (the VLC cone, 51:799-801 -> Dark 217:226,
Light 2425:13968), the accent layer becomes `logo` (`Theme.Color.accentLogo`, #C2711A in Light).

The outputs are committed and deterministic. Python 3 standard library only; run with -I:

    python3 -I modules/gui/macosx_redesign/tools/gen-icons.py           # write
    python3 -I modules/gui/macosx_redesign/tools/gen-icons.py --check   # exit 1 if stale
"""

import json
import pathlib
import re
import shutil
import sys
import textwrap
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
PACKAGE_DIR = TOOLS_DIR.parent
REPO_ROOT = PACKAGE_DIR.parents[2]
SVG_DIR = REPO_ROOT / "redesign" / "design" / "figma" / "icons-svg"
FIGMA_FILE = REPO_ROOT / "redesign" / "design" / "figma" / "figma_file.json"
XCASSETS = PACKAGE_DIR / "Sources" / "MXRDesign" / "Resources" / "Icons.xcassets"
SWIFT_OUT = PACKAGE_DIR / "Sources" / "MXRDesign" / "Generated" / "Icons.swift"

SVG_NS = "http://www.w3.org/2000/svg"
SHAPES = {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon"}

ROLES = {
    "#8F8F8F": "base",
    "#D37918": "accent",
    "#AB6314": "accentDim",
    "#303030": "placeholder",
    "#373737": "divider",
}

# Variants that are empty frames in Figma, so the SVG export has no file for them (ICONS.md lists
# them as missing). They get a variant with no layers: the 24x24 slot stays, nothing is drawn.
# `check` default (494:2400, FRAME 494:2401 has no children) is the trailing slot of every unchecked
# menu/dropdown row (75 instances); the checked row is `check` state=active (or selected).
EMPTY_VARIANTS = [
    {
        "name": "check",
        "tone": "mono",
        "state": "default",
        "figmaNode": "494:2400",
        "doc": "Unchecked = `.default` (an empty 24×24 slot, as in Figma); checked = `state: .active` "
               "(accent) or `.selected` (FG/A2).",
    },
]

# Edges the SVG export dropped. Figma's vector network for `subtitle` "Rectangle 1" (1911:8292 and
# 2461:9667, fillOverrideTable regions 5 and 13) has a folded top-left corner: an open edge from the
# top side at x 9 down to y 7.75 with a 2-unit round, then left to the outline. The export keeps only
# the closed outline. Measured on renders/Icon.png (2 px per unit): the fold's vertical stroke covers
# x 8.25-9.75, its horizontal stroke y 7-8.5. Each fix is inserted
# right after the element whose `id` it names and fails loudly if that element changes.
EXPORT_FIXES = {
    node: {
        "after": "Rectangle 1",
        "markup": '<path id="Fold" d="M9 2.75V5.75C9 6.85457 8.10457 7.75 7 7.75H3.75" stroke="#8F8F8F" '
                  'stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
        "expect": 'd="M9 2.75H17C18.7949 2.75 20.25 4.20507 20.25 6V18C20.25 19.7949 18.7949 21.25 17 '
                  '21.25H7C5.20507 21.25 3.75 19.7949 3.75 18V8C3.75 5.10051 6.10051 2.75 9 2.75Z"',
    }
    for node in ("1911:8286", "2461:9663")
}

# The empty 24x24 placeholder `0` (2107:6596): a blank slot in menu rows and dropdowns. No artwork.
BLANK = {"name": "blank", "figmaNode": "2107:6596"}

SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static",
    "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do",
    "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
    "as", "is", "nil", "self", "super", "throw", "throws", "true", "false", "try",
}


def fail(message):
    sys.stderr.write("gen-icons: error: %s\n" % message)
    sys.exit(1)


def camel(text):
    parts = [p.lower() for p in re.split(r"[^A-Za-z0-9]+", text) if p]
    if not parts:
        fail("cannot make an identifier from %r" % text)
    out = parts[0] + "".join(p[0].upper() + p[1:] for p in parts[1:])
    if out[0].isdigit():
        out = "icon" + out[0].upper() + out[1:]
    return out


def swift_case(name):
    return "`%s`" % name if name in SWIFT_KEYWORDS else name


def local(tag):
    return tag.split("}", 1)[1] if tag.startswith("{") else tag


def attr_text(attrs):
    return "".join(' %s="%s"' % (k, escape(v, {'"': "&quot;"})) for k, v in attrs)


def normalize_color(value):
    if value is None:
        return None
    value = value.strip()
    if value.lower() == "none":
        return None
    match = re.fullmatch(r"#([0-9A-Fa-f]{6})", value)
    if not match:
        fail("unsupported paint %r" % value)
    return "#" + match.group(1).upper()


def role_for(color, where):
    role = ROLES.get(color)
    if role is None:
        fail("%s: color %s has no role; add it to ROLES" % (where, color))
    return role


def logo_components():
    """Component node ids whose accent vectors Figma paints with an `Accent/Logo` style.

    Instances carry the styles (the component's own vectors are unstyled), so a vector id
    `I<instance>;<vector>` with a Logo fill marks `<vector>`; its component is the variant node
    that contains it. A component that mixes Logo and Main styles on its vectors is an error.
    """
    try:
        with open(FIGMA_FILE, encoding="utf-8") as fh:
            figma = json.load(fh)
    except (OSError, ValueError) as exc:
        fail("cannot read figma_file.json: %s" % exc)
    styles = figma.get("styles", {})
    logo = {k for k, v in styles.items() if v.get("name", "").endswith("Accent/Logo")}
    main = {k for k, v in styles.items() if v.get("name", "").endswith("Accent/Main")}
    logo_vectors, main_vectors = set(), set()
    components = {}  # component id -> descendant ids
    stack = [figma.get("document", figma)]
    while stack:
        node = stack.pop()
        if not isinstance(node, dict):
            continue
        children = node.get("children") or []
        fill = (node.get("styles") or {}).get("fill")
        vector = node.get("id", "").split(";")[-1]
        if fill in logo:
            logo_vectors.add(vector)
        elif fill in main:
            main_vectors.add(vector)
        if node.get("type") == "COMPONENT":
            ids, inner = set(), list(children)
            while inner:
                child = inner.pop()
                ids.add(child.get("id", ""))
                inner.extend(child.get("children") or [])
            components[node["id"]] = ids
        stack.extend(children)
    found = set()
    for component, ids in components.items():
        if ids & logo_vectors:
            if ids & main_vectors:
                fail("component %s mixes Accent/Logo and Accent/Main vectors" % component)
            found.add(component)
    return found


def split_layers(svg_text, where):
    """Return (root attributes, [(role, [element markup...]), ...]) in document order.

    The icon frame is 24x24 at the origin; a few exports (sort-active, view-active) have a larger
    viewBox because an accent dot overflows the frame. MXRIcon draws those at their full size from
    the frame's top-left corner, as Figma does.
    """
    try:
        root = ET.fromstring(svg_text)
    except ET.ParseError as exc:
        fail("%s: %s" % (where, exc))
    if local(root.tag) != "svg":
        fail("%s: root is not <svg>" % where)
    root_attrs = [(k, v) for k, v in root.attrib.items()]
    match = re.fullmatch(r"0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)", root.attrib.get("viewBox", ""))
    if not match or float(match.group(1)) < 24 or float(match.group(2)) < 24:
        fail("%s: expected a viewBox of 0 0 24 24 or larger, got %r" % (where, root.attrib.get("viewBox")))
    pieces = []  # (role, markup)

    def walk(node, inherited, wrappers):
        for child in node:
            tag = local(child.tag)
            attrs = dict(inherited)
            for key in ("fill", "stroke"):
                if key in child.attrib:
                    attrs[key] = child.attrib[key]
            if tag == "g":
                extra = [(k, v) for k, v in child.attrib.items() if k not in ("id", "fill", "stroke")]
                walk(child, attrs, wrappers + ([extra] if extra else []))
            elif tag in SHAPES:
                if len(child):
                    fail("%s: <%s> has children" % (where, tag))
                fill = normalize_color(attrs.get("fill"))
                stroke = normalize_color(attrs.get("stroke"))
                # Geometry and stroke style of the element, with the resolved paints made explicit.
                own = [(k, v) for k, v in child.attrib.items() if k not in ("id", "fill", "stroke")]
                if fill and stroke and fill != stroke:
                    # Paint the fill and the stroke as separate elements (SVG paints fill first).
                    fill_only = [(k, v) for k, v in own if not k.startswith("stroke")]
                    fill_only += [("fill", fill), ("stroke", "none")]
                    stroke_only = own + [("fill", "none"), ("stroke", stroke)]
                    pieces.append((role_for(fill, where), element(tag, fill_only, wrappers)))
                    pieces.append((role_for(stroke, where), element(tag, stroke_only, wrappers)))
                elif fill or stroke:
                    paints = [("fill", fill or "none")] + ([("stroke", stroke)] if stroke else [])
                    pieces.append((role_for(fill or stroke, where), element(tag, own + paints, wrappers)))
            else:
                fail("%s: unsupported element <%s>" % (where, tag))

    walk(root, {"fill": root.attrib.get("fill"), "stroke": root.attrib.get("stroke")}, [])
    layers = []
    for role, markup in pieces:
        if layers and layers[-1][0] == role:
            layers[-1][1].append(markup)
        else:
            layers.append((role, [markup]))
    return root_attrs, layers


def element(tag, attrs, wrappers):
    markup = "<%s%s/>" % (tag, attr_text(attrs))
    for extra in reversed(wrappers):
        markup = "<g%s>%s</g>" % (attr_text(extra), markup)
    return markup


def layer_svg(root_attrs, markups):
    keep = [(k, v) for k, v in root_attrs if k in ("width", "height", "viewBox", "fill")]
    return "<svg%s xmlns=\"%s\">\n%s\n</svg>\n" % (attr_text(keep), SVG_NS, "\n".join(markups))


def imageset_contents(filename):
    return json.dumps({
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }, indent=2, sort_keys=True) + "\n"


def load_icons():
    try:
        with open(SVG_DIR / "index.json", encoding="utf-8") as fh:
            index = json.load(fh)
    except (OSError, ValueError) as exc:
        fail("cannot read index.json: %s" % exc)
    icons = []
    for entry in sorted(index["icons"], key=lambda e: e["file"]):
        path = SVG_DIR / entry["file"]
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            fail("cannot read %s: %s" % (path, exc))
        fix = EXPORT_FIXES.get(entry["figmaNode"])
        if fix:
            pattern = r'(<path id="%s" %s[^>]*/>)' % (re.escape(fix["after"]), re.escape(fix["expect"]))
            text, count = re.subn(pattern, lambda m: m.group(1) + "\n" + fix["markup"], text)
            if count != 1:
                fail("%s: EXPORT_FIXES no longer matches the export; re-check node %s"
                     % (entry["file"], entry["figmaNode"]))
        icons.append(dict(entry, svg=text))
    for empty in EMPTY_VARIANTS:
        if any(i["figmaNode"] == empty["figmaNode"] for i in icons):
            fail("node %s now exists in icons-svg; remove it from EMPTY_VARIANTS" % empty["figmaNode"])
    return icons


def build():
    icons = load_icons()
    logos = logo_components()
    variants = {}  # name -> {(tone, state): variant}
    assets = {}    # asset name -> svg text
    for icon in icons:
        stem = icon["file"][:-4]
        v = icon["variant"]
        unknown_axes = set(v) - {"direction", "value", "EQ", "state"}
        if unknown_axes:
            fail("%s: unknown variant axes %s" % (icon["file"], sorted(unknown_axes)))
        name = camel(" ".join([icon["name"]] + [v[a] for a in ("direction", "value", "EQ") if a in v]))
        tone = "twoTone" if icon["twoTone"] else "mono"
        state = v.get("state", "default")
        if state not in ("default", "active", "selected"):
            fail("%s: unknown state %r" % (icon["file"], state))
        root_attrs, layers = split_layers(icon["svg"], icon["file"])
        if not layers:
            fail("%s: no artwork" % icon["file"])
        if icon["figmaNode"] in logos:
            layers = [("logo" if role == "accent" else role, markups) for role, markups in layers]
        layer_assets = []
        for i, (role, markups) in enumerate(layers):
            asset = stem if len(layers) == 1 else "%s-layer%d" % (stem, i)
            if asset in assets:
                fail("duplicate asset name %s" % asset)
            assets[asset] = layer_svg(root_attrs, markups)
            layer_assets.append((asset, role))
        view_box = dict(root_attrs)["viewBox"].split()
        variant = {"tone": tone, "state": state, "file": icon["file"], "node": icon["figmaNode"],
                   "layers": layer_assets, "canvas": (view_box[2], view_box[3])}
        slots = variants.setdefault(name, {})
        key = (tone, state)
        if key in slots:
            # Two Figma variants with identical properties (album, subtitle): the one painted with
            # Accent/DIm is the two-tone artwork; file it there when that slot is free.
            other = slots[key]
            mine_dim = any(r == "accentDim" for _, r in layer_assets)
            other_dim = any(r == "accentDim" for _, r in other["layers"])
            two_key = ("twoTone", state)
            if tone == "mono" and two_key not in slots and mine_dim != other_dim:
                moved = variant if mine_dim else other
                kept = other if mine_dim else variant
                moved = dict(moved, tone="twoTone")
                slots[key] = kept
                slots[two_key] = moved
            else:
                fail("%s and %s are both %s/%s/%s" % (other["file"], icon["file"], name, tone, state))
        else:
            slots[key] = variant
    for empty in EMPTY_VARIANTS:
        slots = variants.get(empty["name"])
        key = (empty["tone"], empty["state"])
        if slots is None or key in slots:
            fail("EMPTY_VARIANTS: %s %s/%s must add a missing variant to an exported icon"
                 % (empty["name"], key[0], key[1]))
        slots[key] = {"tone": key[0], "state": key[1], "file": "", "node": empty["figmaNode"],
                      "layers": [], "canvas": ("24", "24")}
    if BLANK["name"] in variants:
        fail("an icon is already called %s" % BLANK["name"])
    return variants, assets


def swift_source(variants):
    order = {"mono": 0, "twoTone": 1, "default": 0, "active": 1, "selected": 2}
    lines = []
    add = lines.append
    add("// Icons.swift — generated — do not edit.")
    add("//")
    add("// Generated by modules/gui/macosx_redesign/tools/gen-icons.py from redesign/design/figma/icons-svg/")
    add("// (Figma component set `Icon`, node 42:356; VLC Redesign by Juxtopposed, CC BY 4.0).")
    add("// Regenerate: python3 -I modules/gui/macosx_redesign/tools/gen-icons.py")
    add("")
    add("import CoreGraphics")
    add("")
    add("extension MXRIcon {")
    add("    /// Every icon of the Figma `Icon` set (`redesign/design/figma/ICONS.md`). Direction, value and EQ")
    add("    /// variants are separate names; tone (mono / two-tone) and state (default / active / selected)")
    add("    /// are chosen with `MXRIcon(_:tone:state:)`.")
    add("    public enum Name: String, CaseIterable, Sendable {")
    for name in sorted(variants):
        slots = variants[name]
        desc = ", ".join("%s%s" % (tone if tone == "twoTone" else "mono",
                                   "" if state == "default" else "/" + state)
                         for tone, state in sorted(slots, key=lambda k: (order[k[0]], order[k[1]])))
        first = next(slots[k] for k in sorted(slots, key=lambda k: (order[k[0]], order[k[1]])) if slots[k]["file"])
        add("        /// `%s` (node %s) · %s" % (first["file"], first["node"], desc))
        for empty in EMPTY_VARIANTS:
            if empty["name"] == name:
                text = "%s %s (node %s) is an empty frame in Figma. %s" % (
                    empty["tone"], empty["state"], empty["figmaNode"], empty["doc"])
                for line in textwrap.wrap(text, width=100):
                    add("        /// " + line)
        add("        case %s" % swift_case(name))
    add("        /// Figma `0` (node %s): the empty 24×24 slot used in menu rows and dropdowns." % BLANK["figmaNode"])
    add("        case %s" % BLANK["name"])
    add("    }")
    add("")
    add("    /// The variants available for `name`, mono before two-tone, default before active/selected.")
    add("    public static func variants(of name: Name) -> [Variant] {")
    add("        switch name {")
    for name in sorted(variants):
        slots = variants[name]
        add("        case .%s:" % name)
        add("            return [")
        for key in sorted(slots, key=lambda k: (order[k[0]], order[k[1]])):
            v = slots[key]
            layers = ", ".join("Layer(asset: \"%s\", role: .%s)" % (asset, role) for asset, role in v["layers"])
            canvas = "" if v["canvas"] == ("24", "24") else ", canvas: CGSize(width: %s, height: %s)" % v["canvas"]
            add("                Variant(tone: .%s, state: .%s, figmaNode: \"%s\", sourceFile: \"%s\", layers: [%s]%s),"
                % (v["tone"], v["state"], v["node"], v["file"], layers, canvas))
        add("            ]")
    add("        case .%s:" % BLANK["name"])
    add("            return [Variant(tone: .mono, state: .default, figmaNode: \"%s\", sourceFile: \"\", layers: [])]"
        % BLANK["figmaNode"])
    add("        }")
    add("    }")
    add("}")
    return "\n".join(lines) + "\n"


def expected_files(variants, assets):
    files = {XCASSETS / "Contents.json": json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2,
                                                    sort_keys=True) + "\n"}
    for asset, svg in sorted(assets.items()):
        folder = XCASSETS / ("%s.imageset" % asset)
        files[folder / ("%s.svg" % asset)] = svg
        files[folder / "Contents.json"] = imageset_contents("%s.svg" % asset)
    files[SWIFT_OUT] = swift_source(variants)
    return files


def existing_files():
    found = set()
    if XCASSETS.exists():
        found.update(p for p in XCASSETS.rglob("*") if p.is_file())
    if SWIFT_OUT.exists():
        found.add(SWIFT_OUT)
    return found


def main(argv):
    check = "--check" in argv[1:]
    unknown = [a for a in argv[1:] if a != "--check"]
    if unknown:
        fail("unknown arguments %s (usage: gen-icons.py [--check])" % unknown)
    variants, assets = build()
    files = expected_files(variants, assets)
    stale = set(existing_files()) != set(files) or any(
        not path.exists() or path.read_text(encoding="utf-8") != text for path, text in files.items())
    if check:
        if stale:
            sys.stderr.write("gen-icons: icon outputs are stale; run tools/gen-icons.py\n")
            return 1
        return 0
    if not stale:
        print("gen-icons: up to date (%d icons, %d imagesets)" % (len(variants) + 1, len(assets)))
        return 0
    if XCASSETS.exists():
        shutil.rmtree(XCASSETS)
    for path, text in sorted(files.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    multi = sum(1 for slots in variants.values() for v in slots.values() if len(v["layers"]) > 1)
    print("gen-icons: wrote %d icon names, %d imagesets (%d variants have several layers)"
          % (len(variants) + 1, len(assets), multi))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
