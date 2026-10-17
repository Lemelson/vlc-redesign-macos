import AppKit
import MXRCore

enum MXRKeyRouting {
    static func volumeSteps(actionID: String) -> Int? {
        switch actionID {
        case "vol-up": 1
        case "vol-down": -1
        default: nil
        }
    }

    /// - Parameter panelListFocused: a SwiftUI queue or bookmark row has keyboard focus. The window's
    ///   first responder is then still the hosting view, so ``FocusedListKeys`` are let through here
    ///   for the row's own handlers.
    @MainActor
    static func shouldHandle(firstResponder: NSResponder?, hasSheet: Bool, isCapturing: Bool,
                             panelListFocused: Bool = false, binding: KeyBinding? = nil) -> Bool {
        guard !hasSheet, !isCapturing else { return false }
        if panelListFocused, let binding, FocusedListKeys.contains(binding) { return false }
        // SwiftUI text fields use AppKit's field editor. Focused native controls
        // retain arrows, space and other keys for their own editing behavior.
        return !(firstResponder is NSTextView) && !(firstResponder is NSControl)
    }

    /// Whether the menu bar may run `event` as a key equivalent (SD-09, D026): Command equivalents
    /// always run, also with a dialog open; bare playback keys never act behind a dialog or in a
    /// text field; the shortcut recorder gets every key but ⌘Q. See ``MenuKeyEquivalentPolicy``.
    @MainActor
    static func shouldPerformMenuEquivalent(_ event: NSEvent, firstResponder: NSResponder?,
                                            isCapturing: Bool, hasModal: Bool, panelListFocused: Bool = false) -> Bool {
        guard let binding = KeyBinding(event: event) else { return true }
        if panelListFocused, !isCapturing, FocusedListKeys.contains(binding) { return false }
        let isEditing = firstResponder is NSTextView || firstResponder is NSControl
        return MenuKeyEquivalentPolicy.allows(binding, isRecording: isCapturing, hasModal: hasModal, isEditing: isEditing)
    }
}
