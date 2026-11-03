// Generates Resources/dmg/background.png and background@2x.png: the release DMG window's picture
// (tools/package-dmg.sh). Geometry and texts come from Resources/dmg/layout.json, colors and type
// from the design tokens, so the window matches the app's dark look.
// Usage (from the package dir): swift tools/gen-dmg-background.swift
import AppKit

let fm = FileManager.default
let package = URL(fileURLWithPath: fm.currentDirectoryPath)
let tokens = package.appendingPathComponent("../../../redesign/design/tokens").standardized
let output = package.appendingPathComponent("Resources/dmg")

func json(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { fatalError("cannot read \(url.path)") }
    return object
}

let layout = json(output.appendingPathComponent("layout.json"))
let palettes = json(tokens.appendingPathComponent("colors.json"))
let styles = json(tokens.appendingPathComponent("typography.json"))["styles"] as! [[String: Any]]

/// "dark.bgA5" or "light.bgA1": a color token of that theme.
func color(_ name: String) -> CGColor {
    let parts = name.split(separator: ".").map(String.init)
    guard parts.count == 2, let palette = palettes[parts[0]] as? [String: [String: Any]],
          let entry = palette[parts[1]], let hex = entry["hex"] as? String,
          let value = UInt32(hex.dropFirst(), radix: 16) else { fatalError("no color token \(name)") }
    let alpha = (entry["alpha"] as? Double) ?? 1
    return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

// The module bundles Inter; register it so the picture does not depend on installed fonts.
let fonts = package.appendingPathComponent("Sources/MXRDesign/Resources/Fonts")
for name in ["Inter-Light.otf", "Inter-Regular.otf", "Inter-Medium.otf", "Inter-SemiBold.otf"] {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}
func font(_ styleName: String) -> NSFont {
    guard let style = styles.first(where: { $0["name"] as? String == styleName }),
          let size = style["fontSize"] as? Double, let weight = style["fontWeight"] as? Int else { fatalError("no text style \(styleName)") }
    let face = [300: "Inter-Light", 400: "Inter-Regular", 500: "Inter-Medium", 600: "Inter-SemiBold"][weight] ?? "Inter-Regular"
    guard let font = NSFont(name: face, size: size) else { fatalError("cannot load \(face)") }
    return font
}

let window = layout["window"] as! [String: Double]
let width = window["width"]!, height = window["height"]!
let cards = layout["cards"] as! [[String: Any]]

/// Centred on the window, or left-aligned at "x".
func drawText(_ spec: [String: Any]) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font(spec["style"] as! String),
                                                     .foregroundColor: NSColor(cgColor: color(spec["color"] as! String))!]
    let text = NSAttributedString(string: spec["text"] as! String, attributes: attributes)
    let size = text.size()
    let x = (spec["x"] as? Double) ?? (width - size.width) / 2
    // Keep clear of the cards' right edge (inset 24 + 24 padding).
    guard x + size.width <= width - 48 else { fatalError("text too wide for the window: \(spec["text"]!)") }
    text.draw(at: NSPoint(x: x, y: (spec["centerY"] as! Double) - size.height / 2))
}

func render(scale: Double) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)   // 72 dpi at 1x, 144 dpi at 2x
    NSGraphicsContext.saveGraphicsState()
    // Flipped, so layout.json's top-left coordinates apply as they are.
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
    let context = graphics.cgContext   // already in points: rep.size makes it scale by `scale`
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)

    context.setFillColor(color(layout["background"] as! String))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // Light cards that the items sit on: Finder labels them in dark text.
    for card in cards {
        let left = card["left"] as! Double, top = card["top"] as! Double
        let rect = CGRect(x: left, y: top, width: (card["right"] as! Double) - left, height: (card["bottom"] as! Double) - top)
        let radius = card["radius"] as! Double
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(color(card["color"] as! String))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(color(card["stroke"] as! String))
        context.setLineWidth(1)
        context.strokePath()
    }

    let arrow = layout["arrow"] as! [String: Any]
    let fromX = arrow["fromX"] as! Double, toX = arrow["toX"] as! Double, y = arrow["y"] as! Double
    context.setStrokeColor(color(arrow["color"] as! String))
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: fromX, y: y))
    context.addLine(to: CGPoint(x: toX, y: y))
    context.move(to: CGPoint(x: toX - 14, y: y - 14))
    context.addLine(to: CGPoint(x: toX, y: y))
    context.addLine(to: CGPoint(x: toX - 14, y: y + 14))
    context.strokePath()

    for text in layout["texts"] as! [[String: Any]] { drawText(text) }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try fm.createDirectory(at: output, withIntermediateDirectories: true)
try render(scale: 1).write(to: output.appendingPathComponent("background.png"))
try render(scale: 2).write(to: output.appendingPathComponent("background@2x.png"))
print("wrote \(output.path)/background.png and background@2x.png")
