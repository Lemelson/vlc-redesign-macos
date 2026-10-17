// Run from the repository root:
// (MXRKeyRouting uses MXRCore's KeyBinding: add the MXRCore sources or build through the package.)
// swiftc -parse-as-library -swift-version 6 -module-cache-path /private/tmp/mxr-native-cache \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRVideoHost.swift \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRKeyRouting.swift \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRFirstLaunchOnboarding.swift \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRLaunchFileOpening.swift \
//   modules/gui/macosx_redesign/Sources/MXRPlugin/MXRNativePreferences.swift \
//   redesign/tools/test-native-host.swift -o /private/tmp/mxr-native-host-test
// /private/tmp/mxr-native-host-test

import AppKit

@main
struct NativeHostTests {
    @MainActor
    static func main() {
        let surface = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        let decoderView = NSView()
        surface.addSubview(decoderView)
        let host = MXRVideoHostView(surface: surface)
        let player = NSView()
        let miniPlayer = NSView()
        player.addSubview(host)
        miniPlayer.addSubview(host)
        player.addSubview(host)
        precondition(host.surface === surface)
        precondition(surface.subviews.first === decoderView)
        precondition(surface.superview === host)

        // PiP owns the surface until its close callback restores it. A host layout
        // triggered by switching library presentation must not steal it back.
        let pictureInPicture = NSView()
        pictureInPicture.addSubview(surface)
        host.frame.size = NSSize(width: 320, height: 180)
        host.layout()
        precondition(surface.superview === pictureInPicture)
        host.addSubview(surface)
        host.layout()
        precondition(surface.frame == host.bounds)
        precondition(surface.subviews.first === decoderView)

        precondition(MXRKeyRouting.shouldHandle(firstResponder: host, hasSheet: false, isCapturing: false))
        precondition(!MXRKeyRouting.shouldHandle(firstResponder: NSTextView(), hasSheet: false, isCapturing: false))
        precondition(!MXRKeyRouting.shouldHandle(firstResponder: NSTextField(), hasSheet: false, isCapturing: false))
        precondition(!MXRKeyRouting.shouldHandle(firstResponder: host, hasSheet: true, isCapturing: false))
        precondition(!MXRKeyRouting.shouldHandle(firstResponder: host, hasSheet: false, isCapturing: true))
        let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        let copy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        precondition(!MXRKeyRouting.shouldPerformMenuEquivalent(space, firstResponder: NSTextView(), isCapturing: false, hasModal: false))
        precondition(MXRKeyRouting.shouldPerformMenuEquivalent(copy, firstResponder: NSTextView(), isCapturing: false, hasModal: false))
        precondition(!MXRKeyRouting.shouldPerformMenuEquivalent(copy, firstResponder: host, isCapturing: true, hasModal: false))
        // These are the actual VLC action identifiers (key-vol-up/down), not
        // the display labels. Only volume actions bypass engine step defaults.
        precondition(MXRKeyRouting.volumeSteps(actionID: "vol-up") == 1)
        precondition(MXRKeyRouting.volumeSteps(actionID: "vol-down") == -1)
        precondition(MXRKeyRouting.volumeSteps(actionID: "volume-up") == nil)
        precondition(MXRKeyRouting.volumeSteps(actionID: "play-pause") == nil)
        testFirstLaunchOnboarding()
        testLaunchFileOpening()
        testNativePreferences()
        print("PASS: stable video surface, PiP ownership, input routing, onboarding, launch files, and native preferences")
    }

    private static func testNativePreferences() {
        let defaults = MXRNativePreferences(value: { _ in nil })
        precondition(defaults.autoresize == .never && defaults.remembersWindow)
        precondition(!defaults.startsMinimized && defaults.showsMenubarIcon)
        precondition(defaults.raiseOnPlay.shouldRaise(hasVideo: true))
        precondition(!defaults.raiseOnPlay.shouldRaise(hasVideo: false))
        precondition(defaults.trackNotification.shouldShow(isMinimized: true))
        precondition(!defaults.trackNotification.shouldShow(isMinimized: false))
        precondition(defaults.windowAlpha == 1 && defaults.notificationDuration == 5)
        let changed: [String: MXRNativePreferences.Value] = [
            "autoresize": .text("first"), "window-opacity": .number(2),
            "raise-on-play": .text("never"), "notification-duration": .number(.infinity),
            "reverse-scroll": .bool(true), "click-action": .text("controls"),
            "double-click-action": .text("none"), "hotkeys-y-wheel-mode": .number(-1)]
        let selected = MXRNativePreferences(value: { changed[$0] })
        precondition(selected.autoresize == .first && selected.windowAlpha == 0.1)
        precondition(!selected.raiseOnPlay.shouldRaise(hasVideo: true))
        precondition(selected.notificationDuration == 5 && selected.singleClick == .controls)
        precondition(!selected.doubleClickFullscreen && selected.verticalScroll == .none)
        let invalid = MXRNativePreferences(value: { _ in .text("unknown") })
        precondition(invalid.autoresize == .never && invalid.raiseOnPlay == .video)
        var resize = MXRAutoresizePolicy()
        precondition(!resize.consume(mode: .never, isFullscreen: false, hasPlayerLayout: true, validSize: true))
        precondition(!resize.consume(mode: .first, isFullscreen: true, hasPlayerLayout: true, validSize: true))
        precondition(!resize.consume(mode: .first, isFullscreen: false, hasPlayerLayout: false, validSize: true))
        precondition(!resize.consume(mode: .first, isFullscreen: false, hasPlayerLayout: true, validSize: false))
        precondition(resize.consume(mode: .first, isFullscreen: false, hasPlayerLayout: true, validSize: true))
        precondition(!resize.consume(mode: .first, isFullscreen: false, hasPlayerLayout: true, validSize: true))
        precondition(resize.consume(mode: .always, isFullscreen: false, hasPlayerLayout: true, validSize: true))

        var scroll = MXRVideoScrollAccumulator()
        precondition(scroll.consume(x: 0, y: 0.6, timestamp: 0, natural: false, preferences: defaults) == nil)
        precondition(scroll.consume(x: 0, y: 0.6, timestamp: 0.1, natural: false, preferences: defaults) == .init(mode: .volume, steps: 1))
        // Gesture gaps and axis changes discard fractions, preventing an old
        // volume gesture from becoming an unrelated seek after a pause.
        precondition(scroll.consume(x: -0.6, y: 0, timestamp: 1, natural: false, preferences: defaults) == nil)
        precondition(scroll.consume(x: -0.6, y: 0, timestamp: 1.1, natural: false, preferences: defaults) == .init(mode: .seek, steps: 1))
        precondition(scroll.consume(x: 0, y: 1, timestamp: 2, natural: true, preferences: defaults) == .init(mode: .volume, steps: -1))
        let reversed = MXRNativePreferences(value: { $0 == "reverse-scroll" ? .bool(true) : nil })
        precondition(scroll.consume(x: 0, y: 1, timestamp: 3, natural: true, preferences: reversed) == .init(mode: .volume, steps: 1))
        precondition(scroll.consume(x: 0, y: 4, timestamp: 4, natural: false, preferences: selected) == nil)
        // Huge/nonfinite events cannot create an unbounded command loop.
        precondition(scroll.consume(x: 0, y: .infinity, timestamp: 5, natural: false, preferences: defaults) == nil)
        precondition(scroll.consume(x: 0, y: 1000, timestamp: 6, natural: false, preferences: defaults)?.steps == 20)
    }

    private static func testLaunchFileOpening() {
        let directory = URL(fileURLWithPath: "/private/tmp/media", isDirectory: true)
        let first = directory.appendingPathComponent("Test Show S01E01.mp4")
        let second = directory.appendingPathComponent("Test Show S01E02.mp4")
        let finder = directory.appendingPathComponent("Finder.mp4")
        var cli = MXRLaunchFileOpening(arguments: ["VLC", "-I", "macosx_redesign", first.path, second.path],
                                       initialQueue: [first, second], workingDirectory: directory)
        precondition(cli.urlsToOpen([first]).isEmpty)
        precondition(cli.urlsToOpen([second]).isEmpty)
        precondition(cli.urlsToOpen([first, finder, second]) == [finder])
        cli.applicationDidFinishLaunching()
        precondition(cli.urlsToOpen([first, second]) == [first, second])

        // The engine may reject or omit an argument: an empty initial queue
        // must still permit Cocoa to open it, as it does for a Finder launch.
        let emptyQueue = MXRLaunchFileOpening(arguments: ["VLC", first.path],
                                              initialQueue: [], workingDirectory: directory)
        precondition(emptyQueue.urlsToOpen([first, finder]) == [first, finder])
        let finderLaunch = MXRLaunchFileOpening(arguments: ["VLC"],
                                                initialQueue: [first], workingDirectory: directory)
        precondition(finderLaunch.urlsToOpen([first, finder]) == [first, finder])

        // Normalize relative CLI paths, file URLs and percent-encoded names
        // against the actual working directory; preserve callback order.
        let relative = MXRLaunchFileOpening(arguments: ["VLC", "./Test Show S01E01.mp4", second.absoluteString],
                                             initialQueue: [first, second], workingDirectory: directory)
        precondition(relative.urlsToOpen([first, finder, second, finder]) == [finder, finder])
        let remote = URL(string: "https://example.com/video.mp4")!
        let network = MXRLaunchFileOpening(arguments: ["VLC", remote.absoluteString],
                                            initialQueue: [remote], workingDirectory: directory)
        precondition(network.urlsToOpen([finder, remote]) == [finder, remote])
    }

    private static func testFirstLaunchOnboarding() {
        typealias State = MXRFirstLaunchOnboarding.State
        var idle = State(needsOnboarding: true, hasMediaOrQueue: false,
                         hasFileRequest: false, sheet: .none, hasNativeSheet: false)
        var freshLaunch = MXRFirstLaunchOnboarding()
        precondition(freshLaunch.update(idle) == .present)
        idle.sheet = .onboarding
        precondition(freshLaunch.update(idle) == .none)

        // Choosing Open File must make its native panel reachable immediately,
        // before any media has entered the queue. Cancel must not offer again.
        idle.hasFileRequest = true
        precondition(freshLaunch.update(idle) == .dismiss)
        idle.sheet = .none
        idle.hasFileRequest = false
        precondition(freshLaunch.update(idle) == .none)

        // A manual onboarding presentation after that offer is outside the
        // guard's ownership, even if playback starts while it is open.
        idle.sheet = .onboarding
        idle.hasMediaOrQueue = true
        precondition(freshLaunch.update(idle) == .none)

        var commandLineLaunch = MXRFirstLaunchOnboarding()
        idle.sheet = .none
        precondition(commandLineLaunch.update(idle) == .none)
        idle.hasMediaOrQueue = false
        precondition(commandLineLaunch.update(idle) == .none)

        var alreadyCompleted = MXRFirstLaunchOnboarding()
        idle.needsOnboarding = false
        precondition(alreadyCompleted.update(idle) == .none)

        var dialogLaunch = MXRFirstLaunchOnboarding()
        idle.needsOnboarding = true
        idle.hasNativeSheet = true
        precondition(dialogLaunch.update(idle) == .none)
        idle.hasNativeSheet = false
        precondition(dialogLaunch.update(idle) == .none)

        var incomingMedia = MXRFirstLaunchOnboarding()
        precondition(incomingMedia.update(idle) == .present)
        idle.sheet = .onboarding
        idle.hasMediaOrQueue = true
        precondition(incomingMedia.update(idle) == .dismiss)

        var replacedSheet = MXRFirstLaunchOnboarding()
        idle.hasMediaOrQueue = false
        idle.sheet = .none
        precondition(replacedSheet.update(idle) == .present)
        idle.sheet = .other
        precondition(replacedSheet.update(idle) == .none)
        idle.sheet = .onboarding
        idle.hasMediaOrQueue = true
        precondition(replacedSheet.update(idle) == .none)
    }
}
