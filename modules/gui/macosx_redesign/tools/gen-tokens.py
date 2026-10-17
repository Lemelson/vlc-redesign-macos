#!/usr/bin/env python3
"""Generate Sources/MXRDesign/Generated/Tokens.swift from the design tokens.

Inputs:  redesign/design/tokens/{colors,typography,metrics}.json (extracted from Figma).
Output:  modules/gui/macosx_redesign/Sources/MXRDesign/Generated/Tokens.swift

The output is committed and deterministic (no timestamps; JSON key order is kept).
Python 3 standard library only. Run with -I so nothing is imported from the CWD:

    python3 -I modules/gui/macosx_redesign/tools/gen-tokens.py           # write
    python3 -I modules/gui/macosx_redesign/tools/gen-tokens.py --check   # exit 1 if stale

Naming follows redesign/design/tokens/README.md ("Proposed Swift naming"):
Theme.Color.*, Theme.Font.*, Theme.Metric.*, Theme.Radius.*, Theme.Spacing.*, Theme.Stroke.*,
Theme.Effect.*, Theme.Gradient.*, Theme.Accent.
"""

import json
import keyword
import pathlib
import re
import sys

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
PACKAGE_DIR = TOOLS_DIR.parent
REPO_ROOT = PACKAGE_DIR.parents[2]
TOKENS_DIR = REPO_ROOT / "redesign" / "design" / "tokens"
OUTPUT = PACKAGE_DIR / "Sources" / "MXRDesign" / "Generated" / "Tokens.swift"

# Accent-dependent paint styles. Orange uses the Figma values; other accents are derived at
# runtime by Theme.Accent (see AccentPalette.swift) with the rule recorded in colors.json.
ACCENT_TOKENS = ["accentMain", "accentDim", "accentBright", "accentLogo", "bgAccentBright", "bgAccentDark"]

# Semantic names for colors.json "rawColors" (keyed by Figma node id). A raw color that is not
# listed here makes the generator fail, so new values surface as a naming task.
RAW_COLOR_NAMES = {
    "177:99": "iconHover",
    "2404:9202": "thumbPlaceholder",
    "244:213": "volumeBody",
    "244:214": "imageOverlay",
    "6841:14982": "homeCard",
    "3749:12473": "subtitleCue",
    "3191:18739": "swatchOutline",
    "1902:7075": "keycapShadow",
    "2425:13624": "videoUnderBars",
}

# Text styles that are artwork rather than UI text (drawn inside icon SVGs); not generated.
SKIPPED_TEXT_STYLES = {"hdrBadge": "the HDR icon artwork already contains this text (Inter Bold 7.47)"}

# Swift reserved words that cannot be used unescaped as member names.
SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
    "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch",
    "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
    "return", "throw", "switch", "where", "while", "as", "false", "is", "nil", "self", "Self", "super",
    "throws", "true", "try",
}


def fail(message):
    sys.stderr.write("gen-tokens: error: %s\n" % message)
    sys.exit(1)


def load(name):
    path = TOKENS_DIR / name
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        fail("cannot read %s: %s" % (path, exc))


def ident(name):
    """camelCase Swift identifier from a JSON key ("full bass" -> fullBass, "10%" -> p10)."""
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", name) if p]
    if not parts:
        fail("cannot make an identifier from %r" % name)
    head, tail = parts[0], parts[1:]
    out = head[0].lower() + head[1:] + "".join(p[0].upper() + p[1:] for p in tail)
    if out[0].isdigit():
        out = "v" + out
    if out in SWIFT_KEYWORDS or keyword.iskeyword(out):
        out = "`%s`" % out
    return out


def type_ident(name):
    out = ident(name).strip("`")
    return out[0].upper() + out[1:]


def num(value):
    """Swift literal for a JSON number: integers without a fraction, others with up to 4 decimals."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail("not a number: %r" % (value,))
    if float(value).is_integer():
        return str(int(value))
    text = ("%.4f" % value).rstrip("0").rstrip(".")
    return text


def hex_int(hex_string):
    match = re.fullmatch(r"#?([0-9A-Fa-f]{6})", hex_string.strip())
    if not match:
        fail("bad hex color %r" % hex_string)
    return "0x" + match.group(1).upper()


def rgba(hex_string, alpha):
    return "Theme.RGBA(hex: %s, alpha: %s)" % (hex_int(hex_string), num(alpha))


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def doc(text):
    """One-line doc comment text (no newlines, trimmed)."""
    return " ".join(str(text).split())


def extract_rgba(text):
    """Find '#RRGGBB' and an optional '@ alpha' in free text ('#000000 @ 0.20', 'Dark/BG/B2 #090909')."""
    match = re.search(r"(#[0-9A-Fa-f]{6})(?:\s*@\s*([0-9.]+))?", text)
    if not match:
        return None
    return match.group(1), float(match.group(2) or 1)


class Writer:
    def __init__(self):
        self.lines = []
        self.level = 0

    def line(self, text=""):
        self.lines.append(("    " * self.level + text) if text else "")

    def open(self, text):
        self.line(text + " {")
        self.level += 1

    def close(self, suffix=""):
        self.level -= 1
        self.line("}" + suffix)

    def open_switch(self, subject):
        """`switch subject {` with the cases at the same level (Swift style)."""
        self.line("switch %s {" % subject)

    def close_switch(self):
        self.line("}")

    def text(self):
        return "\n".join(self.lines) + "\n"


# ----------------------------------------------------------------------------------------------
# Colors


def color_tokens(colors):
    dark, light = colors["dark"], colors["light"]
    tokens = []  # (name, darkValue, lightValue, docText, isAccent)
    for key, entry in dark.items():
        light_entry = light.get(key)
        light_note = ""
        if light_entry is None:
            light_entry = entry
            light_note = " Light has no such style; the dark value is used."
        text = "`%s` %s@%s" % (entry["figmaStyle"], entry["hex"], num(entry["alpha"]))
        if light_entry is not entry:
            text += " · `%s` %s@%s" % (light_entry["figmaStyle"], light_entry["hex"], num(light_entry["alpha"]))
        text += "." + light_note
        if entry.get("note"):
            text += " " + doc(entry["note"])
        tokens.append((key, (entry["hex"], entry["alpha"]), (light_entry["hex"], light_entry["alpha"]), text,
                       key in ACCENT_TOKENS))
    extra_light = [k for k in light if k not in dark]
    if extra_light:
        fail("light styles without a dark counterpart: %s" % extra_light)
    for token in ACCENT_TOKENS:
        if token not in dark:
            fail("accent token %s missing from colors.json" % token)

    # Derived: the selected ring around the accent dot (colors.json accentSwatches.derivationRule).
    ring_rule = colors["accentSwatches"]["derivationRule"]["selectedRing"]
    match = re.search(r"alpha ([0-9.]+)", ring_rule)
    if not match:
        fail("cannot read the selectedRing alpha from %r" % ring_rule)
    ring_alpha = float(match.group(1))
    main_dark, main_light = dark["accentMain"], light["accentMain"]
    tokens.append(("accentRing", (main_dark["hex"], ring_alpha), (main_light["hex"], ring_alpha),
                   "Selected accent-dot ring: the accent at %s opacity (colors.json derivationRule.selectedRing; "
                   "node 1902:4003)." % num(ring_alpha), True))

    # Raw colors with semantic names. The light value comes from lightHex/lightAlpha (D032);
    # every app-defined color must name one so nothing stays dark-only in the light theme.
    for item in colors["rawColors"]["items"]:
        name = RAW_COLOR_NAMES.get(item["node"])
        if name is None:
            fail("rawColors item %s (%s) has no semantic name; add it to RAW_COLOR_NAMES" % (item["node"], item["use"]))
        if "lightHex" not in item:
            fail("rawColors item %s (%s) has no lightHex; give it a light-theme value (D032)" % (item["node"], item["use"]))
        value = (item["hex"], item["alpha"])
        light_value = (item["lightHex"], item.get("lightAlpha", item["alpha"]))
        text = "Raw %s@%s (node %s): %s." % (item["hex"], num(item["alpha"]), item["node"], doc(item["use"]).rstrip("."))
        if light_value != value:
            text += " Light %s@%s." % (light_value[0], num(light_value[1]))
        tokens.append((name, value, light_value, text, False))
    # Gradient parts that differ in Player - Light (colors.json gradients.<key>.light) become
    # scheme-aware color tokens, e.g. volumeConeTrack; Theme.Gradient aliases them.
    for key, g in colors["gradients"].items():
        for field in themed_gradient_fields(g):
            dark_value, light_value = extract_rgba(g[field]), extract_rgba(g["light"][field])
            if dark_value is None or light_value is None:
                fail("cannot parse gradient %s.%s or its light value" % (key, field))
            tokens.append((ident(key) + type_ident(field), dark_value, light_value,
                           "Gradient %s %s: dark `%s` · light `%s`." % (key, field, doc(g[field]),
                                                                       doc(g["light"][field])), False))
    names = [t[0] for t in tokens]
    if len(set(names)) != len(names):
        fail("duplicate color token names: %s" % names)
    return tokens


GRADIENT_PARTS = ("overlay", "body", "track")


def themed_gradient_fields(g):
    """Gradient parts with a Player - Light value (colors.json gradients.<key>.light)."""
    light = g.get("light", {}) if isinstance(g, dict) else {}
    extra = [k for k in light if k not in GRADIENT_PARTS + ("frame", "note")]
    if extra:
        fail("unknown light gradient fields: %s" % extra)
    return [f for f in GRADIENT_PARTS if f in light and f in g]


def emit_colors(w, colors):
    tokens = color_tokens(colors)
    w.line("// MARK: - Colors")
    w.line()
    w.line("extension Theme {")
    w.level += 1
    w.line("/// Identifies a color token. `rawValue` indexes the generated value tables.")
    w.open("public enum ColorToken: Int, CaseIterable, Sendable")
    for name, _, _, _, _ in tokens:
        w.line("case %s" % name)
    w.line()
    w.line("/// Whether the value depends on the selected accent (`Theme.Accent`).")
    w.open("public var isAccentDependent: Bool")
    w.open_switch("self")
    accent_cases = ", ".join("." + t[0] for t in tokens if t[4])
    w.line("case %s: true" % accent_cases)
    w.line("default: false")
    w.close_switch()
    w.close()
    w.line()
    w.line("/// Figma paint style without the theme prefix (`BG/A3` for `Dark/BG/A3` and `Light/BG/A3`),")
    w.line("/// or `nil` for derived and raw colors.")
    w.open("public var figmaStyle: String?")
    w.open_switch("self")
    for name, _, _, _, _ in tokens:
        style = colors["dark"].get(name, {}).get("figmaStyle")
        if style:
            w.line('case .%s: "%s"' % (name, style.split("/", 1)[1]))
    w.line("default: nil")
    w.close_switch()
    w.close()
    w.line()
    w.line("/// The token for a Figma paint style name, with or without the `Dark/` / `Light/` prefix")
    w.line("/// (case-insensitive, so `Accent/Dim` finds the misspelled `Accent/DIm`).")
    w.open("public init?(figmaStyle: String)")
    w.line('let key = figmaStyle.hasPrefix("Dark/") || figmaStyle.hasPrefix("Light/")')
    w.line('    ? String(figmaStyle.split(separator: "/", maxSplits: 1)[1]) : figmaStyle')
    w.line("guard let token = Self.allCases.first(where: { $0.figmaStyle?.lowercased() == key.lowercased() }) else {")
    w.line("    return nil")
    w.line("}")
    w.line("self = token")
    w.close()
    w.line()
    w.line("/// Swift name of the token, e.g. `fgA2`.")
    w.open("public var name: String")
    w.open_switch("self")
    for name, _, _, _, _ in tokens:
        w.line('case .%s: "%s"' % (name, name))
    w.close_switch()
    w.close()
    w.close()
    w.line()
    w.line("/// Color tokens. Each resolves from the environment's color scheme and `mxrAccent`;")
    w.line("/// use them as `ShapeStyle`s, or call `color(accent:)` / `nsColor(accent:)`.")
    w.open("public enum Color")
    for name, dark_value, light_value, text, _ in tokens:
        w.line("/// %s" % text)
        w.line("public static let %s = ThemeColor(.%s)" % (name, name))
    w.close()
    w.level -= 1
    w.line("}")
    w.line()
    w.line("/// Generated value tables, indexed by `Theme.ColorToken.rawValue`. Accent-dependent entries hold")
    w.line("/// the orange (default) values; other accents are derived in `AccentPalette`.")
    w.open("enum GeneratedPalette")
    for scheme, idx in (("dark", 1), ("light", 2)):
        w.line("static let %s: [Theme.RGBA] = [" % scheme)
        w.level += 1
        for token in tokens:
            hex_value, alpha = token[idx]
            w.line("%s, // %s" % (rgba(hex_value, alpha), token[0]))
        w.level -= 1
        w.line("]")
    w.close()
    w.line()

    # Accents
    swatches = sorted(colors["accentSwatches"]["swatches"], key=lambda s: s["order"])
    defaults = [s["name"] for s in swatches if s.get("default")]
    if defaults != ["orange"]:
        fail("expected orange to be the single default accent, got %s" % defaults)
    rule = colors["accentSwatches"]["derivationRule"]
    bg_match = re.search(r"alpha ([0-9.]+)", rule["bgAccentBright"])
    if not bg_match:
        fail("cannot read the bgAccentBright alpha from %r" % rule["bgAccentBright"])
    w.line("// MARK: - Accents")
    w.line()
    w.line("extension Theme {")
    w.level += 1
    w.line("/// The user-selectable accent colors, in display order (Onboarding and Settings > General).")
    w.open("public enum Accent: String, CaseIterable, Sendable, Identifiable")
    for s in swatches:
        w.line("/// %s · onboarding node %s · settings swatch %s%s" % (
            s["hex"], s["verifiedIn"]["node"], s["settingsSwatchNode"], " · default" if s.get("default") else ""))
        w.line("case %s" % ident(s["name"]))
    w.line()
    w.line("public var id: String { rawValue }")
    w.line()
    w.line("/// The accent's color as Figma shows it (dark Onboarding frames, Settings > General swatches):")
    w.line("/// the dark-theme `accentMain`. The light theme derives its own `accentMain` from it (orange:")
    w.line("/// `Light/Accent/Main`), see `AccentPalette`; use `Theme.Color.accentMain` for themed UI.")
    w.open("public var swatch: Theme.RGBA")
    w.open_switch("self")
    for s in swatches:
        w.line("case .%s: Theme.RGBA(hex: %s)" % (ident(s["name"]), hex_int(s["hex"])))
    w.close_switch()
    w.close()
    w.line()
    w.line("/// Opacity of `accentMain` used as the seek-bar fill (`bgAccentBright`) for non-orange accents.")
    w.open("var derivedFillAlpha: Double")
    w.open_switch("self")
    for name, override in rule.get("bgAccentBrightOverrides", {}).items():
        if name not in [s["name"] for s in swatches] or not 0 <= override["alpha"] <= 1:
            fail("invalid bgAccentBright override for %s" % name)
        w.line("// Figma node %s in onboarding frame %s." % (override["node"], override["frame"]))
        w.line("case .%s: %s" % (ident(name), num(override["alpha"])))
    w.line("default: %s" % num(float(bg_match.group(1))))
    w.close_switch()
    w.close()
    w.close()
    w.level -= 1
    w.line("}")
    w.line()

    # Gradients
    grads = colors["gradients"]
    w.line("// MARK: - Gradients")
    w.line()
    w.line("extension Theme {")
    w.level += 1
    w.line("/// Gradient tokens (colors.json `gradients`).")
    w.open("public enum Gradient")
    for key, g in grads.items():
        if not isinstance(g, dict) or "stops" not in g:
            continue
        w.line("/// %s (node %s).%s" % (doc(g.get("type", "gradient")), g.get("node", "?"),
                                       (" " + doc(g["note"])) if g.get("note") else ""))
        w.line("public static let %s: [Theme.GradientStop] = [" % ident(key))
        w.level += 1
        for stop in g["stops"]:
            if "rgb" in stop:  # the Figma paint's exact sRGB components (the hex is rounded)
                color = "Theme.RGBA(red: %s, green: %s, blue: %s)" % tuple("%.6f" % c for c in stop["rgb"])
            else:
                color = "Theme.RGBA(hex: %s)" % hex_int(stop["hex"])
            w.line("Theme.GradientStop(color: %s, location: %s)," % (color, num(stop["pos"])))
        w.level -= 1
        w.line("]")
        themed = themed_gradient_fields(g)
        for field in GRADIENT_PARTS:
            if field in themed:
                w.line("/// Follows the color scheme: `%s` · light `%s`." % (doc(g[field]), doc(g["light"][field])))
                w.line("public static let %s%s: ThemeColor = Theme.Color.%s%s" % (
                    ident(key), type_ident(field), ident(key), type_ident(field)))
            elif field in g:
                parsed = extract_rgba(g[field])
                if parsed is None:
                    fail("cannot parse gradient %s.%s = %r" % (key, field, g[field]))
                w.line("/// `%s`" % doc(g[field]))
                w.line("public static let %s%s = %s" % (ident(key), type_ident(field), rgba(parsed[0], parsed[1])))
    w.close()
    w.level -= 1
    w.line("}")
    w.line()


# ----------------------------------------------------------------------------------------------
# Typography


def emit_typography(w, typo):
    styles = typo["styles"]
    families = {"Inter": ".inter", "DM Mono": ".dmMono"}
    w.line("// MARK: - Typography")
    w.line()
    w.line("extension Theme {")
    w.level += 1
    w.line("/// Text styles found on Figma TEXT nodes (typography.json). Apply with `.mxrTextStyle(_:)` to get")
    w.line("/// the Figma line height and letter spacing, or use `font` / `nsFont` for the font alone.")
    w.open("public enum Font")
    names = []
    by_name = {s["name"]: s for s in styles}
    for s in styles:
        name = s["name"]
        if "derivedFrom" in s:
            base = by_name.get(s["derivedFrom"])
            if base is None or "derivedFrom" in base:
                fail("style %s derives from unknown or derived style %r" % (name, s["derivedFrom"]))
            for field in ("fontFamily", "fontWeight", "fontSize", "lineHeightPx", "lineHeight", "letterSpacing"):
                if field in s:
                    fail("derived style %s must not repeat %s; it takes the base style's value" % (name, field))
                s[field] = base[field]
            s["usageCount"] = None
        if name in SKIPPED_TEXT_STYLES:
            w.line("// `%s` is not generated: %s." % (name, SKIPPED_TEXT_STYLES[name]))
            continue
        family = families.get(s["fontFamily"])
        if family is None:
            fail("unknown font family %r in style %s" % (s["fontFamily"], name))
        intrinsic = str(s.get("lineHeight", "")).startswith("auto")
        uses = ("derived from `%s`, not a Figma style" % s["derivedFrom"]) if "derivedFrom" in s \
            else "%d uses" % s["usageCount"]
        w.line("/// %s %s %s/%s%s — %s (%s)" % (
            s["fontFamily"], s["fontWeight"], num(s["fontSize"]), num(s["lineHeightPx"]),
            " (intrinsic)" if intrinsic else "", doc(s["role"]), uses))
        w.line("public static let %s = Theme.TextStyle(name: %s, family: %s, weight: %d, size: %s, lineHeight: %s, "
               "letterSpacing: %s)" % (ident(name), swift_string(name), family, int(s["fontWeight"]), num(s["fontSize"]),
                                       num(round(s["lineHeightPx"], 2)), num(s.get("letterSpacing", 0))))
        names.append(ident(name))
    w.close()
    w.level -= 1
    w.line("}")
    w.line()
    w.line("extension Theme.TextStyle {")
    w.level += 1
    for name in names:
        w.line("/// Same as `Theme.Font.%s`." % name)
        w.line("public static var %s: Theme.TextStyle { Theme.Font.%s }" % (name, name))
    w.line()
    w.line("/// A text sample from Figma in this style (typography.json `sampleText`), for specimens.")
    w.open("public var figmaSample: String")
    w.open_switch("name")
    for s in styles:
        if s["name"] in SKIPPED_TEXT_STYLES:
            continue
        samples = [t for t in s.get("sampleText", []) if t.strip()]
        sample = max(samples, key=len) if samples else s["name"]
        w.line("case %s: %s" % (swift_string(s["name"]), swift_string(" ".join(sample.split()))))
    w.line('default: "Aa"')
    w.close_switch()
    w.close()
    w.line()
    w.line("/// Every generated text style, in typography.json order (most used first).")
    w.line("public static let all: [Theme.TextStyle] = [")
    w.level += 1
    for n in names:
        w.line("Theme.Font.%s," % n)
    w.level -= 1
    w.line("]")
    w.level -= 1
    w.line("}")
    w.line()


# ----------------------------------------------------------------------------------------------
# Metrics


def insets(padding):
    if not (isinstance(padding, list) and len(padding) == 4):
        fail("bad padding %r" % (padding,))
    top, right, bottom, left = padding
    if not any(padding):
        return ".zero"
    return "Theme.Insets(top: %s, leading: %s, bottom: %s, trailing: %s)" % (num(top), num(left), num(bottom), num(right))


def box_literal(entry):
    parts = []
    parts.append("node: %s" % swift_string(entry["node"]))
    parts.append("width: %s" % num(entry["w"]))
    parts.append("height: %s" % num(entry["h"]))
    if "radius" in entry:
        parts.append("radius: %s" % num(entry["radius"]))
    if "radii" in entry:
        tl, tr, br, bl = entry["radii"]
        parts.append("radii: Theme.CornerRadii(topLeading: %s, topTrailing: %s, bottomTrailing: %s, bottomLeading: %s)"
                     % (num(tl), num(tr), num(br), num(bl)))
    if "gap" in entry:
        parts.append("gap: %s" % num(entry["gap"]))
    if "padding" in entry:
        parts.append("padding: %s" % insets(entry["padding"]))
    return "Theme.Box(%s)" % ", ".join(parts)


def box_doc(entry):
    extra = []
    for key in ("fill", "hoverFill", "note"):
        if key in entry:
            extra.append("%s: %s" % (key, doc(entry[key])))
    for key, value in entry.items():
        if key not in ("node", "w", "h", "radius", "radii", "gap", "padding", "fill", "hoverFill", "note"):
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                continue  # emitted as its own constant
            extra.append("%s: %s" % (key, doc(value)))
    return "Figma node %s, %s×%s.%s" % (entry["node"], num(entry["w"]), num(entry["h"]),
                                         (" " + "; ".join(extra) + ".") if extra else "")


def emit_group(w, group_key, group):
    w.line("/// metrics.json `%s`." % group_key)
    w.open("public enum %s" % type_ident(group_key))
    for key, entry in group.items():
        name = ident(key)
        if isinstance(entry, dict) and "node" in entry and "w" in entry and "h" in entry:
            w.line("/// %s" % box_doc(entry))
            w.line("public static let %s = %s" % (name, box_literal(entry)))
            for extra_key, value in entry.items():
                if extra_key in ("w", "h", "radius", "gap"):
                    continue
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    w.line("/// `%s.%s` (node %s)." % (key, extra_key, entry["node"]))
                    w.line("public static let %s%s: CGFloat = %s" % (name, type_ident(extra_key), num(value)))
        elif isinstance(entry, dict) and all(isinstance(v, (int, float)) for v in entry.values()) and \
                all(re.fullmatch(r"\d+%?", k) for k in entry):
            # e.g. volume.fillWidthByStep {"0": 1, "10%": 7, ...}
            w.line("/// `%s.%s`: value by step (percent → points)." % (group_key, key))
            pairs = ", ".join("(%s, %s)" % (k.rstrip("%"), num(v)) for k, v in entry.items())
            w.line("public static let %s: [(percent: Int, value: CGFloat)] = [%s]" % (name, pairs))
        elif isinstance(entry, dict):
            notes = []
            for sub_key, value in entry.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    w.line("/// `%s.%s.%s`%s" % (group_key, key, sub_key, (" (node %s)." % entry["node"]) if "node" in entry else "."))
                    w.line("public static let %s%s: CGFloat = %s" % (name, type_ident(sub_key), num(value)))
                elif sub_key != "node":
                    notes.append("%s: %s" % (sub_key, doc(value)))
            if notes:
                w.line("// %s: %s" % (key, "; ".join(notes)))
        elif isinstance(entry, (int, float)) and not isinstance(entry, bool):
            w.line("/// `%s.%s`." % (group_key, key))
            w.line("public static let %s: CGFloat = %s" % (name, num(entry)))
        else:
            w.line("// %s: %s" % (key, doc(entry)))
    w.close()


def emit_metrics(w, metrics):
    radius = metrics["radius"]
    spacing = metrics["spacing"]
    stroke = metrics["stroke"]
    effects = metrics["effects"]

    w.line("// MARK: - Radius")
    w.line()
    w.line("extension Theme {")
    w.level += 1
    w.line("/// Corner-radius scale (metrics.json `radius.scale`).")
    w.open("public enum Radius")
    usage = radius.get("usage", {})
    for key, value in radius["scale"].items():
        use = usage.get(num(value))
        w.line("/// %s pt%s" % (num(value), (" — " + doc(use)) if use else ""))
        w.line("public static let %s: CGFloat = %s" % (ident(key), num(value)))
    w.close()
    w.line()

    w.line("/// Auto-layout gaps found in Figma (metrics.json `spacing.gapDistribution`; fractional values from")
    w.line("/// the 0.55× onboarding preview are excluded).")
    w.open("public enum Spacing")
    counts = {int(g["value"]): g["count"] for g in spacing["gapDistribution"] if float(g["value"]).is_integer()}
    dominant = [int(v) for v in re.findall(r"\b(\d+)\b", spacing.get("note", "").split(":", 1)[-1])]
    gaps = sorted({gap for gap in list(counts) + dominant if gap > 0})
    for gap in gaps:
        if gap in counts:
            w.line("/// %d pt (%d auto-layout frames)." % (gap, counts[gap]))
        else:
            w.line("/// %d pt (listed as a dominant gap in metrics.json `spacing.note`)." % gap)
        w.line("public static let gap%d: CGFloat = %d" % (gap, gap))
    w.close()
    w.line()

    w.line("/// Stroke widths and dash patterns (metrics.json `stroke`).")
    w.open("public enum Stroke")
    w.line("/// Divider lines: %s px `%s` (node %s)." % (num(stroke["divider"]["weight"]), stroke["divider"]["color"],
                                                     stroke["divider"]["node"]))
    w.line("public static let hairline: CGFloat = %s" % num(stroke["divider"]["weight"]))
    w.line("/// Control-bar top border: %s px `%s`, %s (node %s)." % (
        num(stroke["controlBarTopBorder"]["weight"]), stroke["controlBarTopBorder"]["color"],
        stroke["controlBarTopBorder"]["align"].lower(), stroke["controlBarTopBorder"]["node"]))
    w.line("public static let controlBarTopBorder: CGFloat = %s" % num(stroke["controlBarTopBorder"]["weight"]))
    w.line("/// Icon strokes (mono / two-tone, default state).")
    w.line("public static let icon: CGFloat = %s" % num(stroke["iconStroke"]["default"]))
    w.line("/// Icon strokes in many active variants.")
    w.line("public static let iconActive: CGFloat = %s" % num(stroke["iconStroke"]["active"]))
    vf = stroke["videoFrame"]
    w.line("/// %s" % doc(vf.get("note", "Video frame stroke.")))
    w.line("public static let videoFrame: CGFloat = %s" % num(vf["weight"]))
    dash = stroke["dash"]
    w.line("/// Dash pattern of the Customize outline.")
    w.line("public static let customizeOutlineDash: [CGFloat] = [%s]" % ", ".join(num(v) for v in dash["customizeOutline"]))
    w.line("/// Dash pattern of the subtitle connector (`%s`, node %s)." % (dash["subtitleConnector"]["color"],
                                                                        dash["subtitleConnector"]["node"]))
    w.line("public static let subtitleConnectorDash: [CGFloat] = [%s]" % ", ".join(
        num(v) for v in dash["subtitleConnector"]["dash"]))
    w.close()
    w.line()

    w.line("/// Blurs and shadows (metrics.json `effects`).")
    w.open("public enum Effect")
    for key, e in effects.items():
        name = ident(key)
        if "shadow" in e and isinstance(e["shadow"], dict):
            s = e["shadow"]
            w.line("/// Style \"%s\": background blur %s + shadow. Used on %s." % (e.get("style", key), num(e.get("blur", 0)),
                                                                                doc(e.get("usedOn", "?"))))
            w.line("public static let %s = Theme.Shadow(x: %s, y: %s, blur: %s, spread: %s, color: %s)" % (
                name, num(s["x"]), num(s["y"]), num(s["blur"]), num(s.get("spread", 0)), rgba(s["color"], s["alpha"])))
            w.line("/// Background blur radius that goes with `%s`." % name)
            w.line("public static let %sBlur: CGFloat = %s" % (name, num(e.get("blur", 0))))
        elif "color" in e and "blur" in e:
            w.line("/// Shadow from node %s." % e.get("node", "?"))
            w.line("public static let %s = Theme.Shadow(x: %s, y: %s, blur: %s, spread: %s, color: %s)" % (
                name, num(e.get("x", 0)), num(e.get("y", 0)), num(e["blur"]), num(e.get("spread", 0)),
                rgba(e["color"], e["alpha"])))
        elif "radius" in e:
            w.line("/// %s, radius %s%s%s" % (e.get("type", "blur").capitalize(), num(e["radius"]),
                                             (". Used on " + doc(e["usedOn"])) if e.get("usedOn") else "",
                                             (". " + doc(e["note"])) if e.get("note") else "."))
            w.line("public static let %sRadius: CGFloat = %s" % (name, num(e["radius"])))
        else:
            fail("unknown effect shape for %s: %r" % (key, e))
    w.close()
    w.line()

    w.line("/// Component metrics read from named Figma nodes (metrics.json), plus the standard sizes.")
    w.open("public enum Metric")
    for key, value in metrics["standardHeights"].items():
        if isinstance(value, (int, float)):
            w.line("/// Standard height: %s." % key)
            w.line("public static let %sHeight: CGFloat = %s" % (ident(key), num(value)))
        else:
            w.line("// standardHeights.%s = %s (see the component metrics)" % (key, doc(value)))
    for key, value in metrics["standardWidths"].items():
        if isinstance(value, (int, float)):
            w.line("/// Standard width: %s." % key)
            w.line("public static let %sWidth: CGFloat = %s" % (ident(key), num(value)))
        else:
            w.line("// standardWidths.%s = %s (see the component metrics)" % (key, doc(value)))
    placement = metrics["sidePanels"]["placement"]
    w.line("/// Inset of floating side panels from the window edge and the bars (sidePanels.placement).")
    w.line("public static let panelInset: CGFloat = %s" % num(placement["rightInset"]))
    w.line("/// Icon artwork size (all Figma icons are 24×24).")
    w.line("public static let iconSize: CGFloat = %s" % num(metrics["menus"]["menuIcon"]))
    w.line()
    skip = {"meta", "radius", "spacing", "stroke", "effects", "standardHeights", "standardWidths"}
    first = True
    for key, group in metrics.items():
        if key in skip:
            continue
        if not isinstance(group, dict):
            fail("unexpected metrics group %s" % key)
        if not first:
            w.line()
        first = False
        emit_group(w, key, group)
    w.close()
    w.level -= 1
    w.line("}")


def generate():
    colors = load("colors.json")
    typo = load("typography.json")
    metrics = load("metrics.json")
    meta = colors.get("meta", {}).get("source", {})
    w = Writer()
    w.line("// Tokens.swift — generated — do not edit.")
    w.line("//")
    w.line("// Generated by modules/gui/macosx_redesign/tools/gen-tokens.py from")
    w.line("// redesign/design/tokens/{colors,typography,metrics}.json.")
    w.line("// Figma: \"%s\" version %s, %s" % (meta.get("figmaFileName", "?"), meta.get("figmaVersion", "?"),
                                             meta.get("license", "")))
    w.line("// Regenerate: python3 -I modules/gui/macosx_redesign/tools/gen-tokens.py")
    w.line()
    w.line("import CoreGraphics")
    w.line()
    emit_colors(w, colors)
    emit_typography(w, typo)
    emit_metrics(w, metrics)
    return w.text()


def main(argv):
    check = "--check" in argv[1:]
    unknown = [a for a in argv[1:] if a != "--check"]
    if unknown:
        fail("unknown arguments %s (usage: gen-tokens.py [--check])" % unknown)
    text = generate()
    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else None
    if check:
        if current != text:
            sys.stderr.write("gen-tokens: %s is stale; run tools/gen-tokens.py\n" % OUTPUT.relative_to(REPO_ROOT))
            return 1
        return 0
    if current != text:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(text, encoding="utf-8")
        print("gen-tokens: wrote %s" % OUTPUT.relative_to(REPO_ROOT))
    else:
        print("gen-tokens: %s is up to date" % OUTPUT.relative_to(REPO_ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
