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

    /// SwiftUI text fields use AppKit's field editor. Focused native controls retain arrows, space
    /// and other keys for their own editing behavior.
    @MainActor
    static func isEditing(_ firstResponder: NSResponder?) -> Bool {
        firstResponder is NSTextView || firstResponder is NSControl
    }

    /// The window key monitor's gate, ``WindowKeyPolicy/monitorHandles(_:hasSheet:isCapturing:isEditing:listFocused:)``.
    /// - Parameter listFocused: a SwiftUI library, queue or bookmark list has keyboard focus
    ///   (``InterfaceModel/listHasKeyboardFocus``).
    @MainActor
    static func shouldHandle(firstResponder: NSResponder?, hasSheet: Bool, isCapturing: Bool,
                             listFocused: Bool = false, binding: KeyBinding? = nil) -> Bool {
        WindowKeyPolicy.monitorHandles(binding, hasSheet: hasSheet, isCapturing: isCapturing,
                                       isEditing: isEditing(firstResponder), listFocused: listFocused)
    }

    /// Whether the menu bar may run `event` as a key equivalent (SD-09, D026): Command equivalents
    /// always run, also with a dialog open; bare playback keys never act behind a dialog or in a
    /// text field; the shortcut recorder gets every key but ⌘Q. See ``MenuKeyEquivalentPolicy``.
    @MainActor
    static func shouldPerformMenuEquivalent(_ event: NSEvent, firstResponder: NSResponder?,
                                            isCapturing: Bool, hasModal: Bool, listFocused: Bool = false) -> Bool {
        guard let binding = KeyBinding(event: event) else { return true }
        if listFocused, !isCapturing, FocusedListKeys.contains(binding) { return false }
        return MenuKeyEquivalentPolicy.allows(binding, isRecording: isCapturing, hasModal: hasModal,
                                              isEditing: isEditing(firstResponder))
    }
}
