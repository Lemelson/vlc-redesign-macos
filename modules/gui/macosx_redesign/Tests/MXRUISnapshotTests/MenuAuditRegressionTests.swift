import AppKit
import MXRCore
@testable import MXRDesign
import MXRMockBackend
@testable import MXRUI
import XCTest

/// Menu fixes of the final wave (D-menus review): HDR choices, overflow composition, the menu
/// bar's Video menu, the shared Add to Playlist rows, VoiceOver menu attributes and the rule that
/// product UI uses the design-system popup only (D024/D025).
@MainActor
final class MenuAuditRegressionTests: XCTestCase {
    private func playing() -> AppModel {
        MockBackend(scenario: .playingMovie).makeAppModel(clockTicks: false)
    }

    // D-04 / D039: manual HDR modes are visible and disabled, with the reason below them.
    func testHDRMenuListsChoicesWithOnlyAutomaticEnabled() {
        let rows = MXRPlayerMenus.hdrModes(playing())
        let choices = rows.prefix { !$0.isSeparator }
        // Figma HDR Options 2372:8733: Auto, Off, HDR10, HDR10+, Dolby Vision, HLG.
        XCTAssertEqual(choices.map(\.title), ["Auto", "Off", "HDR10", "HDR10+", "Dolby Vision", "HLG"])
        XCTAssertEqual(choices.filter(\.isChecked).map(\.title), ["Auto"])
        XCTAssertEqual(choices.filter(\.isEnabled).map(\.title), ["Auto"])
        let reason = try? XCTUnwrap(rows.last)
        XCTAssertEqual(reason?.isEnabled, false)
        XCTAssertEqual(reason?.isSecondary, true)
        XCTAssertTrue(rows.dropLast().last?.isSeparator == true)
    }

    // D-08: an overflowed control is not repeated by the right-click rows below it, and every
    // overflow row carries its bar icon.
    func testOverflowDoesNotRepeatContextRowsAndShowsBarIcons() {
        let app = playing()
        let controls: [PlayerControl] = [.stop, .record, .previous, .next, .playbackSpeed, .chapters]
        let rows = MXRPlayerMenus.overflowMenu(controls, app: app)
        for command in [AppCommand.stop, .record, .previous, .next] {
            XCTAssertEqual(rows.filter { $0.title == command.title }.count, 1, command.title)
        }
        let overflow = MXRPlayerMenus.overflow(controls, app: app)
        XCTAssertEqual(overflow.map(\.icon), controls.map(\.barIcon))
        XCTAssertFalse(overflow.contains { $0.icon == nil || $0.icon == .blank })
    }

    func testOverflowRowsFollowTheCommandGate() {
        let app = playing()
        app.interface.present(.about)
        let rows = MXRPlayerMenus.overflow([.replay, .playlists, .chapters, .bookmarks], app: app)
        XCTAssertTrue(rows.allSatisfy { !$0.isEnabled }, "Behind a dialog the overflow rows wait like the bar buttons")
    }

    // D-05: the menu bar's Video menu leaves Full Screen to View (⌘F once).
    func testVideoMenuForMenuBarOmitsFullscreen() {
        let app = playing()
        let fullscreen = AppCommand.toggleFullscreen.title
        XCTAssertTrue(MXRPlayerMenus.video(app).contains { $0.title == fullscreen })
        XCTAssertFalse(MXRPlayerMenus.video(app, includesFullscreen: false).contains { $0.title == fullscreen })
    }

    // D-07: one Add to Playlist builder; playlists load when the submenu opens, not while built.
    func testAddToPlaylistLoadsOnOpenAndSeparatesNewPlaylist() throws {
        let app = playing()
        let submenu = MXRPlayerMenus.addToPlaylist(app, newPlaylist: {}, media: { [] }, onError: { _, _ in })
        XCTAssertTrue(submenu.isSubmenu)
        XCTAssertNotNil(submenu.onOpen)
        submenu.onOpen?()
        let rows = try XCTUnwrap(submenu.children)
        XCTAssertEqual(rows.first?.title, "New Playlist…")
        if !app.library.playlists.isEmpty { XCTAssertTrue(rows[1].isSeparator) }
        let playerPlaylist = MXRPlayerMenus.playlist(app)
        XCTAssertNotNil(playerPlaylist.first { $0.title == "Add to Playlist" }?.onOpen)
    }

    // D-02: presented rows publish NSMenu's mark and command-key attributes.
    func testMenuKeyAttributesMatchNSMenu() {
        let commandO = MXRMenuKeyAttributes(binding: KeyBinding(key: "o", modifiers: .command))
        XCTAssertEqual(commandO, MXRMenuKeyAttributes(binding: KeyBinding(vlcString: "Command+o")!))
        XCTAssertEqual(commandO.character, "O")
        XCTAssertEqual(commandO.modifiers, 0)
        let shiftCommandS = MXRMenuKeyAttributes(binding: KeyBinding(vlcString: "Command+Shift+s")!)
        XCTAssertEqual(shiftCommandS.modifiers, 1)
        let space = MXRMenuKeyAttributes(binding: KeyBinding(vlcString: "Space")!)
        XCTAssertNil(space.character)
        XCTAssertEqual(space.glyph, 0x09)
        XCTAssertEqual(space.modifiers, 8, "No Command")
        XCTAssertEqual(MXRMenuKeyAttributes(binding: KeyBinding(vlcString: "Command+Left")!).glyph, 0x64)
        XCTAssertEqual(MXRMenuKeyAttributes(binding: KeyBinding(vlcString: "F12")!).glyph, 0x7A)
    }

    @available(macOS, deprecated: 10.10)
    func testPresentedMenuIsAnAXMenuOfMenuItems() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(x: 100, y: 200, width: 40, height: 40))
        window.contentView?.addSubview(view)
        let anchor = MXRPopupAnchor()
        anchor.view = view
        var opened = false
        anchor.present(.menu({ [
            MXRMenuItem("Open File(s)", shortcut: KeyBinding(vlcString: "Command+o")) {},
            MXRMenuItem("1×", isChecked: true) {},
            .separator,
            MXRMenuItem("Disabled", isEnabled: false) {},
            .submenu("More") { [MXRMenuItem("Inner") {}] },
            MXRMenuItem("Press me") { opened = true },
        ] }), placement: .below(), style: .contextMenu, width: nil, surface: true,
            environment: MXRPopupEnvironment(colorScheme: .dark, accent: .orange, themeMode: .dark, backdropEnabled: false),
            onDismiss: {})
        defer { anchor.dismiss(animated: false); window.close() }
        let panel = try XCTUnwrap(window.childWindows?.first)
        let menu = try XCTUnwrap(panel.contentView)
        XCTAssertEqual(menu.accessibilityRole(), .menu)
        let rows = try XCTUnwrap(menu.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(rows.count, 5, "Separators are not menu items")
        XCTAssertTrue(rows.allSatisfy { $0.accessibilityRole() == .menuItem })
        XCTAssertEqual(rows.map { $0.accessibilityTitle() }, ["Open File(s)", "1×", "Disabled", "More", "Press me"])
        let markChar = NSAccessibility.Attribute(rawValue: "AXMenuItemMarkChar")
        let cmdChar = NSAccessibility.Attribute(rawValue: "AXMenuItemCmdChar")
        XCTAssertEqual(rows[0].accessibilityAttributeValue(cmdChar) as? String, "O")
        XCTAssertNil(rows[0].accessibilityAttributeValue(markChar))
        XCTAssertEqual(rows[1].accessibilityAttributeValue(markChar) as? String, "✓")
        XCTAssertFalse(rows[2].isAccessibilityEnabled())
        XCTAssertTrue(rows[0].accessibilityParent() as? NSView === menu)
        XCTAssertTrue(rows[4].accessibilityPerformPress())
        // The action runs after the close animation; with motion it is deferred, so wait briefly.
        let expectation = expectation(description: "press runs the row")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        XCTAssertTrue(opened)
    }

    // D-03 / D024 / D025: product UI uses the design-system popup, never SwiftUI's native menus
    // or an arrowed popover (the menu bar's NSMenu lives in MXRPlugin).
    func testProductUIHasNoNativeMenusOrPopovers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/MXRUI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = [#"\.contextMenu\s*\{"#, #"\.contextMenu\s*\("#, #"(^|[^A-Za-z_.])Menu\s*\{"#,
                      #"(^|[^A-Za-z_.])Menu\s*\(\s*""#, #"\.popover\s*\("#, #"\.menuStyle\s*\("#]
            .map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.components(separatedBy: .newlines).enumerated()
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                if banned.contains(where: { $0.firstMatch(in: line, range: range) != nil }) {
                    offenders.append("\(file.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Use .mxrContextMenu / .mxrPopupMenu / .mxrPopup (D024, D025)")
    }
}

/// View ▸ Extensions (C-05) and the popup shadow kernel (D-12).
@MainActor
final class MenuExtensionsAndShadowTests: XCTestCase {
    func testExtensionsMenuListsExtensionsAndOpensAnEnabledOnesMenu() throws {
        let backend = MockBackend(scenario: .playingMovie)
        let app = backend.makeAppModel(clockTicks: false)
        var rows = MXRPlayerMenus.extensions(app)
        XCTAssertEqual(rows.map(\.title), ["No Extensions", "", "Manage Extensions…"])
        XCTAssertFalse(rows[0].isEnabled)
        if case .action(let manage) = rows[2].kind { manage() }
        guard case .settings(let category) = app.interface.sheet else { return XCTFail("Settings did not open") }
        XCTAssertEqual(category, "extensions")
        app.interface.sheet = nil

        backend.extensions.seedSamples()
        rows = MXRPlayerMenus.extensions(app)
        XCTAssertEqual(rows.map(\.title), ["VLsub", "Lyrics Finder", "Playlist Exporter", "", "Manage Extensions…"])
        XCTAssertFalse(rows[0].isSubmenu, "a disabled extension has no menu yet")
        XCTAssertFalse(rows[0].isChecked)
        XCTAssertTrue(rows[2].isChecked)

        // Choosing VLsub enables it; its own menu then opens from the row, which shows it enabled.
        if case .action(let enable) = rows[0].kind { enable() }
        rows = MXRPlayerMenus.extensions(app)
        XCTAssertTrue(rows[0].isSubmenu)
        XCTAssertTrue(rows[0].isChecked)
        let entries = try XCTUnwrap(rows[0].children)
        XCTAssertEqual(entries.map(\.title), ["Search subtitles…", "Settings", "", "Disable"])
        if case .action(let disable) = entries[3].kind { disable() }
        XCTAssertFalse(MXRPlayerMenus.extensions(app)[0].isSubmenu)
    }

    // D-12: the bitmap follows Figma's truncated kernel: full strength inside the caster's edge,
    // about half at the edge, nothing past the kernel's reach, and clear inside the card.
    func testPopupShadowFallsOffLikeFigmaAndEndsAtTheKernelReach() throws {
        let shadow = Theme.Shadow(x: 0, y: 0, blur: 20, spread: 0, color: .init(red: 0, green: 0, blue: 0, alpha: 1))
        let card = CGSize(width: 100, height: 100)
        let image = try XCTUnwrap(MXRPopupShadowImage.image(card: card, radius: 0, shadow: shadow, scale: 1))
        let extent = Int(MXRPopupShadowImage.extent(of: shadow))
        XCTAssertEqual(image.width, 100 + extent * 2)
        let alpha = try alphaRow(image, row: image.height / 2)
        let edge = extent + 100 // first pixel right of the card
        XCTAssertEqual(alpha[edge - 50], 0, "clear inside the card")
        XCTAssertEqual(Double(alpha[edge]), 127, accuracy: 12, "half strength at the edge")
        // The bitmap ends at the kernel's reach, where the falloff has already reached ~0.
        let reach = Int((shadow.blur * MXRPopupShadowImage.reachPerBlur).rounded())
        XCTAssertEqual(alpha.count, edge + reach)
        XCTAssertLessThanOrEqual(alpha[alpha.count - 1], 2, "nothing left at the kernel's reach")
        XCTAssertGreaterThan(alpha[edge + reach / 2], alpha[edge + reach - 2])
        // σ = 0.45 × blur (9 px): one σ out a Gaussian edge holds 16 % of its strength.
        XCTAssertEqual(Double(alpha[edge + 9]), 255 * 0.16, accuracy: 10)
    }

    private func alphaRow(_ image: CGImage, row: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<image.width).map { pixels[row * image.width * 4 + $0 * 4 + 3] }
    }
}
