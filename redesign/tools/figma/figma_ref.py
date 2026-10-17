#!/usr/bin/env python3
"""Crop a Figma node out of its frame render, for comparing an implementation by eye.

Each top-level frame of redesign/design/figma/figma_file.json has a PNG in renders/ that covers
the frame's absoluteRenderBounds (frame + shadow bleed) at the export scale 2: pixel (0, 0) is the
render-bounds origin and the PNG is ceil(bounds x 2) pixels. A node's crop is its
absoluteBoundingBox minus that origin, times 2. When that lands between pixels (frames whose
render bounds start at x.2 / y.8, e.g. Onboarding), the crop is resampled bilinearly so the node
starts exactly at the crop's corner. This is the same math and rounding as `mxr-snapshot ref`
(modules/gui/macosx_redesign): crops at the render's 2x agree within a level or two per channel;
crops at another --scale are resampled slightly differently. Use that tool for the full render/compare loop. This script is for
humans and needs no Swift build.

Usage (from anywhere):
  python3 -I redesign/tools/figma/figma_ref.py 848:1711                 # info + crop to ./848-1711@2x.png
  python3 -I redesign/tools/figma/figma_ref.py 848-1711 -o play.png --scale 1
  python3 -I redesign/tools/figma/figma_ref.py 2245:9805 --bounds render  # include the drop shadow
  python3 -I redesign/tools/figma/figma_ref.py 1904:7238 --info           # info and children only
  python3 -I redesign/tools/figma/figma_ref.py --find "Show Advanced" [--frame 491:1780]

Cropping uses Pillow when it is installed, otherwise macOS `sips` (whole pixels only).
"""
import argparse
import decimal
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../.."))
FIGMA = os.path.join(REPO, "redesign/design/figma")
RENDERS = os.path.join(FIGMA, "renders")


def load_document():
    with open(os.path.join(FIGMA, "figma_file.json"), encoding="utf-8") as f:
        return json.load(f)["document"]


def render_files():
    """Frame id -> render file (relative to renders/), from the table in INDEX.md."""
    pattern = re.compile(r"^\|\s*\d+\s*\|\s*`([^`]+)`\s*\|.*?\|\s*\[([^\]]+)\]\(renders/")
    result = {}
    with open(os.path.join(FIGMA, "INDEX.md"), encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line)
            if m:
                result[m.group(1)] = m.group(2)
    return result


def index_nodes(document):
    """id -> (node, parent id, top-level frame), plus top-level frames in layer order."""
    nodes, frames, names = {}, [], {}
    files = render_files()

    def walk(node, parent, frame):
        nodes[node["id"]] = (node, parent, frame)
        for child in node.get("children") or []:
            walk(child, node["id"], frame)

    for canvas in document.get("children", []):
        for top in canvas.get("children", []):
            seen = names.get(top["name"], 0)
            names[top["name"]] = seen + 1
            top["_render"] = files.get(top["id"], top["name"] + (".png" if seen == 0 else "-%d.png" % seen))
            frames.append(top)
            walk(top, None, top)
    return nodes, frames


def normalized(node_id):
    node_id = node_id.strip()
    return node_id.replace("-", ":") if ":" not in node_id and "-" in node_id else node_id


def png_size(path):
    with open(path, "rb") as f:
        header = f.read(24)
    return struct.unpack(">II", header[16:24])


def round_half_away(value):
    """Rounds like Swift's .rounded(): halves away from zero (Python's round() goes to even)."""
    return int(decimal.Decimal(value).quantize(decimal.Decimal(1), rounding=decimal.ROUND_HALF_UP))


def snapped(value):
    """Removes float noise around whole numbers (105.99999 -> 106), like FigmaIndex.snapped."""
    return float(round_half_away(value)) if abs(value - round_half_away(value)) < 0.001 else value


def export_scale(rb, width, height):
    """The frame's export scale: the PNG is ceil(render bounds x scale) pixels (normally 2).

    Returns (sx, sy, fits_rule); falls back to the measured ratio when the PNG doesn't fit."""
    measured = (width / rb["width"], height / rb["height"])
    nominal = round_half_away(measured[0] * 4) / 4

    def fits(length, pixels):
        return abs(math.ceil(length * nominal - 0.001) - pixels) <= 1

    if nominal > 0 and fits(rb["width"], width) and fits(rb["height"], height):
        return nominal, nominal, True
    return measured[0], measured[1], False


def crop_rect(node, frame, render_path, bounds, scale):
    """The crop in render pixels as (x, y, w, h) floats, the output size, the render scale."""
    box = node.get("absoluteRenderBounds") if bounds == "render" else None
    box = box or node["absoluteBoundingBox"]
    rb = frame.get("absoluteRenderBounds") or frame["absoluteBoundingBox"]
    width, height = png_size(render_path)
    sx, sy, fits_rule = export_scale(rb, width, height)
    out_size = (round_half_away(box["width"] * scale), round_half_away(box["height"] * scale))
    x = snapped((box["x"] - rb["x"]) * sx)
    y = snapped((box["y"] - rb["y"]) * sy)
    native = abs(sx - scale) < 0.01 and abs(sy - scale) < 0.01
    if native:  # 1:1 copy of out_size pixels, shifted bilinearly when x/y are fractional
        rect = (x, y, float(out_size[0]), float(out_size[1]))
    else:
        rect = (x, y, snapped(box["width"] * sx), snapped(box["height"] * sy))
    return box, rect, out_size, (sx, sy, fits_rule), (width, height), native


def crop(render_path, rect, out_size, native, out_path):
    try:
        from PIL import Image
    except ImportError:
        Image = None
    x, y, w, h = rect
    ix, iy = math.floor(x), math.floor(y)
    whole = native and x == ix and y == iy
    if Image is not None:
        image = Image.open(render_path).convert("RGBA")
        if whole:
            image.crop((ix, iy, ix + out_size[0], iy + out_size[1])).save(out_path)  # pads with transparency
            return
        # Whole-pixel superset (padded with transparency); resize() premultiplies RGBA.
        # BILINEAR at 1:1 is the same sub-pixel shift as mxr-snapshot.
        piece = image.crop((ix, iy, math.ceil(x + w) + 1, math.ceil(y + h) + 1))
        fx, fy = x - ix, y - iy
        if native:
            piece.resize(out_size, Image.BILINEAR, box=(fx, fy, fx + w, fy + h)).save(out_path)
            return
        # Another scale: shift onto whole pixels first, then area-average (BOX), which is close
        # to mxr-snapshot's exact coverage-weighted average.
        if fx or fy:
            size = (math.ceil(w), math.ceil(h))
            piece = piece.resize(size, Image.BILINEAR, box=(fx, fy, fx + size[0], fy + size[1]))
        piece.resize(out_size, Image.BOX, box=(0, 0, w, h)).save(out_path)
        return
    if not shutil.which("sips"):
        sys.exit("need Pillow (pip install pillow) or macOS sips to crop")
    if not whole:
        print("warning   without Pillow the crop is rounded to whole pixels (up to 1/2 px off)")
    x0, y0 = round_half_away(x), round_half_away(y)
    x1, y1 = round_half_away(x + w), round_half_away(y + h)
    width, height = png_size(render_path)
    if x0 < 0 or y0 < 0 or x1 > width or y1 > height:
        sys.exit("node extends beyond its frame render; install Pillow to crop it with transparent padding")
    with tempfile.TemporaryDirectory() as tmp:
        staged = os.path.join(tmp, "crop.png")
        subprocess.run(
            ["sips", "--cropToHeightWidth", str(y1 - y0), str(x1 - x0), "--cropOffset", str(y0), str(x0),
             render_path, "--out", staged],
            check=True, stdout=subprocess.DEVNULL,
        )
        if (x1 - x0, y1 - y0) != out_size:
            subprocess.run(["sips", "--resampleHeightWidth", str(out_size[1]), str(out_size[0]), staged],
                           check=True, stdout=subprocess.DEVNULL)
        shutil.move(staged, out_path)


def hidden_ancestor(node, nodes):
    """The outermost hidden layer on the path to node (node itself included), or None."""
    chain, current = [], node
    while current is not None:
        chain.insert(0, current)
        pid = nodes[current["id"]][1]
        current = nodes[pid][0] if pid else None
    return next((n for n in chain if not n.get("visible", True)), None)


def describe(node, parent, frame, nodes):
    chain, current = [], node
    while current is not None:
        chain.insert(0, "%s [%s]" % (current["name"], current["id"]))
        pid = nodes[current["id"]][1]
        current = nodes[pid][0] if pid else None
    box = node["absoluteBoundingBox"]
    print("node      %s %s \"%s\" %g×%g pt%s" % (node["id"], node["type"], node["name"], box["width"], box["height"],
                                                 "" if node.get("visible", True) else " (hidden)"))
    if node["type"] == "TEXT":
        print("text      %s" % node.get("characters", "")[:120])
    print("path      " + " › ".join(chain))
    children = node.get("children") or []
    if children:
        print("children  %d" % len(children))
        for child in children[:60]:
            b = child["absoluteBoundingBox"] or {}
            print("  %-14s %-10s %g×%g at %g,%g  %s" % (
                child["id"], child["type"], b.get("width", 0), b.get("height", 0),
                b.get("x", 0) - box["x"], b.get("y", 0) - box["y"], child["name"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("node", nargs="?", help="Figma node id, 848:1711 or 848-1711")
    parser.add_argument("-o", "--out", help="output PNG (default ./<node>@<scale>x.png)")
    parser.add_argument("--scale", type=float, default=2.0, help="pixels per point of the crop (default 2)")
    parser.add_argument("--bounds", choices=["box", "render"], default="box",
                        help="box = absoluteBoundingBox (default); render = include shadows")
    parser.add_argument("--info", action="store_true", help="print node info only, don't crop")
    parser.add_argument("--find", metavar="TEXT", help="search node names and text instead")
    parser.add_argument("--frame", help="limit --find to one top-level frame")
    parser.add_argument("--limit", type=int, default=40)
    args = parser.parse_args()

    nodes, frames = index_nodes(load_document())
    if args.find is not None:
        frame_id = normalized(args.frame) if args.frame else None
        shown = 0
        for node_id, (node, _, frame) in nodes.items():
            if frame_id and frame["id"] != frame_id:
                continue
            text = node.get("characters", "") if node["type"] == "TEXT" else ""
            if args.find.lower() in node["name"].lower() or args.find.lower() in text.lower():
                b = node.get("absoluteBoundingBox") or {}
                print("%-16s %-10s %-12s %s%s  <%s %s>" % (
                    node_id, node["type"], "%g×%g" % (b.get("width", 0), b.get("height", 0)), node["name"],
                    (' "%s"' % text[:50]) if text and text != node["name"] else "", frame["name"], frame["id"]))
                shown += 1
                if shown >= args.limit:
                    break
        print("%d node(s)" % shown)
        return
    if not args.node:
        parser.error("give a node id or --find TEXT")

    node_id = normalized(args.node)
    if node_id not in nodes:
        sys.exit("unknown Figma node %s" % args.node)
    node, parent, frame = nodes[node_id]
    render_path = os.path.join(RENDERS, frame["_render"])
    box, rect, out_size, (sx, sy, fits_rule), (width, height), native = crop_rect(
        node, frame, render_path, args.bounds, args.scale)
    describe(node, parent, frame, nodes)
    print("frame     %s \"%s\" -> renders/%s (%.2fx of render bounds)" % (frame["id"], frame["name"], frame["_render"], sx))
    x, y, w, h = rect
    print("crop      x %g y %g %gx%g px of the render" % (x, y, w, h))
    hidden = hidden_ancestor(node, nodes)
    if hidden is not None:
        print("warning   " + ("node is hidden in Figma (visible: false)" if hidden is node else
                              "node is inside the hidden layer \"%s\" [%s]" % (hidden["name"], hidden["id"]))
              + "; the render doesn't show it")
    if x < 0 or y < 0 or x + w > width or y + h > height:
        print("warning   node extends beyond its frame render; the outside part is transparent")
    if not fits_rule:
        print("warning   render size doesn't match its bounds at 2x; using the measured %.3fx%.3f px/pt" % (sx, sy))
    if not native:
        print("warning   crop resampled from the %gx render to %gx" % (sx, args.scale))
    elif x != math.floor(x) or y != math.floor(y):
        print("warning   the frame render starts between pixels: crop shifted by %.2f, %.2f px (bilinear), "
              "so edges are slightly softer than in the render" % (x - math.floor(x), y - math.floor(y)))
    if args.info:
        return
    out = args.out or "%s@%gx.png" % (node_id.replace(":", "-").replace(";", "_"), args.scale)
    crop(render_path, rect, out_size, native, out)
    print("-> %dx%d px\n%s" % (out_size[0], out_size[1], os.path.abspath(out)))


if __name__ == "__main__":
    main()
