import Foundation
import MXRCore
import XCTest

/// Settings rows must do something and speak in human words (SD-04, SD-05, SD-06, SD-M3, D035).
final class SettingsCatalogLintTests: XCTestCase {
    private let catalog = SettingsCatalog.bundled
    private static let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testInfoTextsAreForPeople() {
        for row in catalog.allRows {
            guard let info = row.info else { continue }
            for marker in ["verify", "TODO", "FIXME", "XXX"] {
                XCTAssertFalse(info.localizedCaseInsensitiveContains(marker), "\(row.id): \(info)")
            }
            XCTAssertNotEqual(info.lowercased(), row.label.lowercased(), "\(row.id): the ⓘ text only repeats the label")
        }
    }

    func testEveryDropdownOffersARealChoice() {
        for row in catalog.allRows where row.control == .dropdown || row.control == .segmented {
            let count = row.composite?.count ?? row.choices?.count ?? 0
            XCTAssertTrue(count >= 2 || row.choiceSource != nil, "\(row.id) is a one-item dropdown")
            if let choices = row.choices {
                XCTAssertEqual(Set(choices.map(\.title)).count, choices.count, "\(row.id) repeats a title")
            }
        }
    }

    /// VLC's own defaults (src/libvlc-module.c and the module sources, read 2026-10-14) for every
    /// option-backed dropdown: a fresh install must show a title from the catalog, never a raw value.
    func testEngineDefaultsResolveToCatalogTitles() {
        let defaults: [String: SettingValue] = [
            "align": .integer(0), "aspect-ratio": .string(""), "audio-language": .string(""), "audio-replay-gain-mode": .string("none"),
            "auhal-audio-device": .string(""), "avcodec-skiploopfilter": .integer(0), "avi-index": .integer(0), "clock-synchro": .integer(-1),
            "codec": .string("any"), "crop": .string(""), "dec-dev": .string("any"), "deinterlace": .integer(-1), "deinterlace-mode": .string("auto"),
            "dvd": .string(""), "equalizer-preset": .string("flat"), "fit": .integer(1), "force-dolby-surround": .integer(0),
            "freetype-outline-thickness": .integer(4), "freetype-shadow-distance": .float(0.06), "freetype-text-direction": .integer(0),
            "hotkeys-x-wheel-mode": .integer(2), "hotkeys-y-wheel-mode": .integer(0), "input-timeshift-granularity": .integer(-1),
            "log-verbose": .integer(-1), "logmode": .string("text"), "menu-language": .string(""), "mix-mode": .integer(0),
            "postproc-q": .integer(0), "preferred-resolution": .integer(-1), "recursive": .string("collapse"), "restore-playback-pos": .integer(1),
            "role": .string("video"), "snapshot-format": .string("png"), "sout-x264-preset": .string(""), "sout-x264-tune": .string(""),
            "soxr-resampler-quality": .integer(2), "sub-autodetect-fuzzy": .integer(3), "sub-language": .string(""), "sub-text-scale": .integer(100),
            "subsdec-encoding": .string(""), "syslog-facility": .string("user"),
        ]
        for row in catalog.allRows where row.control == .dropdown {
            guard let option = row.option, !option.hasPrefix("macosx-redesign-") else { continue }
            guard let value = defaults[option] else { XCTFail("\(option): add its VLC default to this table"); continue }
            XCTAssertTrue(row.choices?.contains { $0.value.isEquivalent(to: value) } ?? false, "\(option) default \(value) has no title")
        }
    }

    /// Every app option is registered by the module, used by the interface, and the other way round.
    func testEveryAppOptionHasAConsumer() throws {
        let registered = try appOptions()
        let referenced = catalog.referencedOptions.filter { $0.hasPrefix("macosx-redesign-") }
        XCTAssertTrue(referenced.isSubset(of: registered), "Catalog rows for unregistered options: \(referenced.subtracting(registered).sorted())")
        let conditions = Set(catalog.allRows.flatMap { [$0.enabledWhen?.option, $0.visibleWhen?.option].compactMap { $0 } })
        let code = try sourceText()
        for name in registered where !name.hasPrefix("macosx-redesign-key-") {
            let short = String(name.dropFirst("macosx-redesign-".count))
            let used = conditions.contains(name) || code.contains("\"\(name)\"") || code.contains("\"\(short)\"")
            XCTAssertTrue(used, "\(name) is registered but nothing reads it")
        }
    }

    private func appOptions() throws -> Set<String> {
        let text = try String(contentsOf: Self.packageDirectory.appendingPathComponent("module/MXRAppOptions.inc"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"add_\w+\("(macosx-redesign-[a-z0-9-]+)""#)
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// Interface sources that read options (the catalog, option registrations, previews and mocks excluded).
    private func sourceText() throws -> String {
        var text = ""
        for folder in ["Sources", "module"] {
            let root = Self.packageDirectory.appendingPathComponent(folder)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
            for file in files where ["swift", "m", "c", "h"].contains(file.pathExtension) {
                let path = file.path
                if path.contains("/MXRGallery") || path.contains("/MXRMockBackend/") || path.contains("/tests/") { continue }
                text += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            }
        }
        return text
    }
}
