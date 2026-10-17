// Generates Resources/AppIcon.icns: the flat Figma cone (icons-svg/vlc.svg) on the
// design's dark chrome, so "VLC Redesign" is distinguishable from stock VLC.
// Usage (from the package dir): swift tools/gen-app-icon.swift
import AppKit

let fm = FileManager.default
let package = URL(fileURLWithPath: fm.currentDirectoryPath)
let svg = package.appendingPathComponent("../../../redesign/design/figma/icons-svg/vlc.svg").standardized
guard let cone = NSImage(contentsOf: svg) else { fatalError("cannot load \(svg.path)") }

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func srgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body with a ~185/1024 corner radius.
    let body = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGradient(starting: srgb(0x2A2A2A), ending: srgb(0x151515))!.draw(in: path, angle: -90)
    srgb(0x373737).setStroke()   // Dark/Divider/Bright
    path.lineWidth = max(1, s / 512)
    path.stroke()
    let side = s * 560 / 1024
    cone.draw(in: NSRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let out = package.appendingPathComponent("Resources/AppIcon.icns")
try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
