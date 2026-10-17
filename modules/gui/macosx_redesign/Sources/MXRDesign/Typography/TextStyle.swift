import AppKit
import CoreText
import SwiftUI

extension Theme {
    /// A Figma text style: font family, weight, size, line height and letter spacing
    /// (typography.json). `Theme.Font.*` holds the generated ones.
    ///
    /// Apply it with `.mxrTextStyle(_:)`, which also reproduces the Figma line height (text box
    /// height and spacing between lines); `font` alone only sets the font.
    public struct TextStyle: Hashable, Sendable, Identifiable {
        /// Font families bundled in `Resources/Fonts` (SIL OFL 1.1).
        public enum Family: String, Sendable {
            /// Inter 3.19 (the version Figma renders; Inter 4 has different digit widths).
            case inter = "Inter"
            case dmMono = "DM Mono"
        }

        /// Name in typography.json, e.g. `body`.
        public let name: String
        public let family: Family
        /// CSS-style weight: 300, 400, 500 or 600 (bundled weights).
        public let weight: Int
        public let size: CGFloat
        /// Figma line height in points.
        public let lineHeight: CGFloat
        /// Figma letter spacing in points (tracking).
        public let letterSpacing: CGFloat

        public init(name: String, family: Family, weight: Int, size: CGFloat, lineHeight: CGFloat,
                    letterSpacing: CGFloat = 0) {
            self.name = name
            self.family = family
            self.weight = weight
            self.size = size
            self.lineHeight = lineHeight
            self.letterSpacing = letterSpacing
        }

        public var id: String { name }

        /// PostScript name of the bundled face, e.g. `Inter-SemiBold`.
        public var postScriptName: String {
            switch family {
            case .dmMono:
                return "DMMono-Regular"
            case .inter:
                switch weight {
                case ..<350: return "Inter-Light"
                case ..<450: return "Inter-Regular"
                case ..<550: return "Inter-Medium"
                default: return "Inter-SemiBold"
                }
            }
        }

        /// The same style at another size (line height scaled proportionally).
        public func size(_ newSize: CGFloat) -> TextStyle {
            TextStyle(name: name, family: family, weight: weight, size: newSize,
                      lineHeight: lineHeight * newSize / size, letterSpacing: letterSpacing)
        }

        /// The SwiftUI font (bundled face; system font of the same weight if fonts are unavailable).
        public var font: SwiftUI.Font { SwiftUI.Font(ctFont) }

        /// The AppKit font.
        public var nsFont: NSFont { ctFont as NSFont }

        /// The Core Text font.
        public var ctFont: CTFont { FontRegistry.font(postScriptName: postScriptName, size: size, weight: weight) }

        /// Ascent + descent + leading of the font: the line height Figma calls "auto".
        public var naturalLineHeight: CGFloat {
            let f = ctFont
            return CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)
        }

        /// Height of one line as AppKit and SwiftUI lay it out: ascent, descent and leading each
        /// rounded to whole points (equals `NSLayoutManager.defaultLineHeight(for:)`).
        public var renderedLineHeight: CGFloat {
            let f = ctFont
            return CTFontGetAscent(f).rounded() + CTFontGetDescent(f).rounded() + CTFontGetLeading(f).rounded()
        }

        /// Whether Figma sets a fixed line height (e.g. 28 for 16 pt) rather than "auto".
        public var hasFixedLineHeight: Bool {
            lineHeight - naturalLineHeight > 0.5
        }

        /// Space added to each rendered line to reach the Figma line height; 0 for "auto" line heights.
        public var extraLineSpacing: CGFloat {
            hasFixedLineHeight ? max(0, lineHeight - renderedLineHeight) : 0
        }

        /// Attributes for `NSAttributedString` (AppKit text): font, tracking and a paragraph style
        /// with the Figma line height, baseline centered like Figma.
        public func attributes(color: NSColor? = nil) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            var attributes: [NSAttributedString.Key: Any] = [
                .font: nsFont,
                .paragraphStyle: paragraph,
                .baselineOffset: extraLineSpacing / 2,
            ]
            if letterSpacing != 0 {
                attributes[.kern] = letterSpacing
            }
            if let color {
                attributes[.foregroundColor] = color
            }
            return attributes
        }
    }
}

extension View {
    /// Applies a Figma text style: font, letter spacing, and the Figma line height (spacing between
    /// lines plus half of the extra leading above the first and below the last line, as Figma does).
    public func mxrTextStyle(_ style: Theme.TextStyle) -> some View {
        modifier(MXRTextStyleModifier(style: style))
    }
}

private struct MXRTextStyleModifier: ViewModifier {
    let style: Theme.TextStyle

    func body(content: Content) -> some View {
        let extra = style.extraLineSpacing
        if style.letterSpacing != 0 {
            content
                .font(style.font)
                .tracking(style.letterSpacing)
                .lineSpacing(extra)
                .padding(.vertical, extra / 2)
        } else {
            content
                .font(style.font)
                .lineSpacing(extra)
                .padding(.vertical, extra / 2)
        }
    }
}

/// Registers the bundled fonts and builds `CTFont`s from the bundled files (by URL, so an installed
/// font with the same PostScript name, e.g. a newer Inter, is never picked by accident).
enum FontRegistry {
    /// Bundled faces. Registering happens on first access (thread-safe, once).
    static let fonts = BundledFonts(descriptors: registerBundledFonts())

    private static let cache = FontCache()

    static func font(postScriptName: String, size: CGFloat, weight: Int) -> CTFont {
        if let cached = cache.font(postScriptName, size) {
            return cached
        }
        let font: CTFont
        if let descriptor = fonts.descriptors[postScriptName] {
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            font = NSFont.systemFont(ofSize: size, weight: nsWeight(weight)) as CTFont
        }
        cache.store(font, postScriptName, size)
        return font
    }

    private static func nsWeight(_ weight: Int) -> NSFont.Weight {
        switch weight {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        default: .bold
        }
    }

    private static func registerBundledFonts() -> [String: CTFontDescriptor] {
        guard let bundle = DesignSystem.resourceBundle else { return [:] }
        var urls: [URL] = []
        for ext in ["otf", "ttf"] {
            urls += bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            urls += bundle.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
        }
        var result: [String: CTFontDescriptor] = [:]
        for url in Set(urls).sorted(by: { $0.path < $1.path }) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let err = error?.takeRetainedValue(),
               CFErrorGetCode(err) != CTFontManagerError.alreadyRegistered.rawValue {
                DesignSystem.log.error("cannot register \(url.lastPathComponent, privacy: .public): \(err.localizedDescription, privacy: .public)")
            }
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                    result[name] = descriptor
                }
            }
        }
        if result.isEmpty {
            DesignSystem.log.error("no bundled fonts found; using the system font")
        }
        return result
    }
}

/// The bundled font descriptors by PostScript name. Immutable; `CTFontDescriptor` is thread-safe.
final class BundledFonts: @unchecked Sendable {
    let descriptors: [String: CTFontDescriptor]

    init(descriptors: [String: CTFontDescriptor]) {
        self.descriptors = descriptors
    }

    /// PostScript names of the registered faces, sorted.
    var names: [String] { descriptors.keys.sorted() }
}

/// Small thread-safe cache of `CTFont`s by PostScript name and size.
private final class FontCache: @unchecked Sendable {
    private let lock = NSLock()
    private var fonts: [String: CTFont] = [:]

    func font(_ name: String, _ size: CGFloat) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        return fonts["\(name)@\(size)"]
    }

    func store(_ font: CTFont, _ name: String, _ size: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        fonts["\(name)@\(size)"] = font
    }
}
