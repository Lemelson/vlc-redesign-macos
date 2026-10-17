import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// Editable hotkeys (S64). Saving commits the draft; Cancel, Esc and close discard it.
///
/// A key field records in place (SD-17): click it, it shows "Press keys…" in the accent outline,
/// the next key combination is assigned, Esc cancels and Delete clears. A key already used by
/// another action is shown under the row with "Reassign", which moves it here.
/// The Global Hotkey column appears only when the engine supports global hotkeys (SD-M1, D035).
public struct MXRKeyboardShortcutsView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShortcutsModel.self) private var shortcuts
    @Environment(InterfaceModel.self) private var interface
    @Environment(\.colorScheme) private var scheme
    @State private var recording: ShortcutField?
    @State private var conflict: ShortcutConflict?

    public init() {}

    private var supportsGlobal: Bool { app.capabilities.supportsGlobalHotkeys }

    public var body: some View {
        @Bindable var shortcuts = shortcuts
        GeometryReader { geometry in
            let layout = SettingsShortcutLayout(width: geometry.size.width, showsGlobal: supportsGlobal)
            VStack(spacing: 0) {
                VStack(spacing: Theme.Spacing.gap12) {
                    HStack {
                        Text("Keyboard Shortcuts").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                            .padding(.leading, Theme.Spacing.gap10)
                        Spacer(minLength: 0)
                        Button(action: cancel) { MXRIcon(.close).frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight) }
                            .buttonStyle(.plain).accessibilityLabel("Close keyboard shortcuts")
                    }.frame(height: Theme.Metric.iconButtonHeight)
                    HStack(spacing: Theme.Spacing.gap10) {
                        SettingsSearch(text: $shortcuts.searchText, placeholder: "Search Keyboard Shortcuts...")
                        SettingsChoiceMenu(title: shortcuts.searchField.title,
                                           choices: searchFields.map { SettingChoice(value: .string($0.rawValue), title: $0.title) },
                                           selected: .string(shortcuts.searchField.rawValue), select: { choice in
                            if let raw = choice.value.stringValue, let field = ShortcutsModel.SearchField(rawValue: raw) { shortcuts.searchField = field }
                        }, compact: true).frame(width: layout.filterWidth)
                    }
                }
                .padding(Theme.Metric.Dialogs.addSubtitlesHeader.padding.edgeInsets)
                .frame(height: Theme.Metric.dialogHeaderWithToolbarHeight)
                .background(Theme.Color.bgB2)
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                        HStack(spacing: 0) {
                            if layout.stacksFields {
                                Text("Action").frame(width: layout.contentWidth, alignment: .leading)
                            } else if supportsGlobal {
                                Text("Action").frame(width: layout.headerActionWidth, alignment: .leading)
                                Text("Hotkey").frame(width: layout.headerHotkeyWidth, alignment: .leading)
                                Text("Global Hotkey").frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                // One key column: its heading is centred over the fields at the trailing edge.
                                Text("Action").frame(width: layout.leadingWidth, alignment: .leading)
                                Text("Hotkey").frame(width: layout.fieldWidth)
                            }
                        }.mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fgA3)
                        separator
                        if shortcuts.filteredGroups.isEmpty {
                            Text("No keyboard shortcuts match “\(shortcuts.searchText)”.").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA1)
                        }
                        ForEach(shortcuts.filteredGroups, id: \.group) { group, actions in
                            VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
                                Text(group.title).mxrTextStyle(Theme.Font.dialogSectionTitle).foregroundStyle(Theme.Color.fgA1)
                                VStack(spacing: Theme.Spacing.gap14) {
                                    ForEach(actions) { action in
                                        shortcutRow(action, layout: layout)
                                    }
                                }.padding(.bottom, Theme.Spacing.gap5)
                                separator
                            }
                        }
                    }
                    .frame(width: layout.contentWidth, alignment: .leading)
                    .padding(Theme.Spacing.gap20)
                }.scrollIndicators(.automatic)
                HStack {
                    SettingsButton(title: "Cancel", surface: DialogButton.secondaryFill(for: scheme), action: cancel)
                    Spacer(minLength: 0)
                    SettingsButton(title: "Save", primary: true) {
                        shortcuts.saveDraft()
                        close()
                    }
                    .disabled(!shortcuts.hasChanges)
                    // Return saves, except while a field records (Return can be a hotkey).
                    .keyboardShortcut(recording == nil ? .defaultAction : nil)
                }
                .padding(Theme.Metric.Dialogs.dialogFooter.padding.edgeInsets)
                .frame(height: Theme.Metric.Dialogs.dialogFooter.height)
            }
        }
        .frame(idealWidth: Theme.Metric.Dialogs.keyboardShortcuts.width, idealHeight: Theme.Metric.Dialogs.keyboardShortcuts.height)
        .background { MXRDialogSurface(tint: Theme.Color.bgA3Transparent) }
        .clipShape(.rect(cornerRadius: Theme.Radius.xxl))
        .onChange(of: recording) { _, value in interface.isCapturingShortcut = value != nil }
        .onDisappear { shortcuts.discardDraft(); interface.isCapturingShortcut = false }
    }

    private var searchFields: [ShortcutsModel.SearchField] {
        ShortcutsModel.SearchField.allCases.filter { supportsGlobal || $0 != .globalHotkey }
    }

    private var separator: some View {
        // Figma's line has zero layout height and a centered one-point stroke.
        Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Spacing.gap1).frame(height: 0)
    }

    @ViewBuilder
    private func shortcutRow(_ action: ShortcutAction, layout: SettingsShortcutLayout) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
            if layout.stacksFields {
                VStack(alignment: .leading, spacing: Theme.Spacing.gap14) {
                    Text(action.title).mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(supportsGlobal ? [false, true] : [false], id: \.self) { global in
                        VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                            if supportsGlobal {
                                Text(global ? "Global Hotkey" : "Hotkey").mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                            }
                            shortcutField(action, global: global, width: layout.fieldWidth)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    Text(action.title).mxrTextStyle(Theme.Font.dialogHint).foregroundStyle(Theme.Color.fg2)
                        .frame(width: layout.leadingWidth, alignment: .leading)
                    shortcutField(action, global: false, width: layout.fieldWidth)
                    if supportsGlobal {
                        Spacer().frame(width: layout.rowGap)
                        shortcutField(action, global: true, width: layout.fieldWidth)
                    }
                }
            }
            if let conflict, conflict.field.actionID == action.id {
                conflictNotice(conflict, layout: layout)
            }
        }
    }

    private func conflictNotice(_ conflict: ShortcutConflict, layout: SettingsShortcutLayout) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            Text("“\(conflict.binding.displayString)” is used by \(conflict.others.map(\.title).joined(separator: ", ")).")
                .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.accentMain)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            SettingsButton(title: "Cancel", surface: DialogButton.secondaryFill(for: scheme)) { self.conflict = nil }
            SettingsButton(title: "Reassign", primary: true) {
                for other in conflict.others { shortcuts.removeBinding(conflict.binding, from: other.id) }
                shortcuts.setBinding(conflict.binding, for: conflict.field.actionID, global: conflict.field.global)
                self.conflict = nil
            }
        }
        // Under the key fields when there are two columns; across the row when there is one.
        .padding(.leading, layout.stacksFields || !layout.showsGlobal ? 0 : layout.leadingWidth)
        .accessibilityElement(children: .contain)
    }

    private func shortcutField(_ action: ShortcutAction, global: Bool, width: CGFloat) -> some View {
        let field = ShortcutField(actionID: action.id, global: global)
        let bindings = global ? action.globalHotkeys : action.hotkeys
        let conflicting = bindings.contains { !conflicts(for: $0, excluding: action.id).isEmpty }
        return ShortcutKeyField(text: bindings.map(\.displayString).joined(separator: ", "),
                                isRecording: recording == field, isConflicting: conflicting, width: width,
                                label: "\(global ? "Global hotkey" : "Hotkey") for \(action.title)") {
            conflict = nil
            recording = field
        } onKey: { binding in
            recording = nil
            guard let binding else { shortcuts.setBinding(nil, for: action.id, global: global); return }
            let others = conflicts(for: binding, excluding: action.id)
            if others.isEmpty { shortcuts.setBinding(binding, for: action.id, global: global) }
            else { conflict = ShortcutConflict(field: field, binding: binding, others: others) }
        } onCancel: {
            if recording == field { recording = nil }
        }
    }

    /// Other actions using `binding`; global bindings count only where global hotkeys exist.
    private func conflicts(for binding: KeyBinding, excluding actionID: String) -> [ShortcutAction] {
        shortcuts.editedActions.filter {
            $0.id != actionID && ($0.hotkeys.contains(binding) || (supportsGlobal && $0.globalHotkeys.contains(binding)))
        }
    }

    private func cancel() { shortcuts.discardDraft(); close() }
    private func close() {
        if interface.sheet == .keyboardShortcuts { interface.dismissSheet() }
    }
}

private struct ShortcutField: Hashable {
    var actionID: String
    var global: Bool
}

private struct ShortcutConflict {
    let field: ShortcutField
    let binding: KeyBinding
    let others: [ShortcutAction]
}

/// A key field that records in place. `onKey(nil)` clears (Delete); Esc or clicking away cancels.
struct ShortcutKeyField: View {
    let text: String
    let isRecording: Bool
    var isConflicting = false
    let width: CGFloat?
    let label: String
    let start: () -> Void
    let onKey: (KeyBinding?) -> Void
    let onCancel: () -> Void

    var body: some View {
        Button(action: start) {
            ZStack(alignment: .trailing) {
                Text(isRecording ? "Press keys…" : text)
                    .mxrTextStyle(Theme.Font.keycap)
                    .foregroundStyle(isRecording ? Theme.Color.accentMain : Theme.Color.fg2)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Metric.iconSize + Theme.Spacing.gap5)
                MXRIcon(.edit, tint: isRecording || isConflicting ? Theme.Color.accentMain : Theme.Color.fgA4)
                    .padding(.trailing, Theme.Spacing.gap5)
            }
            .frame(width: width, height: Theme.Metric.SettingsDetail.shortcutFieldHeight)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
            .overlay {
                if isRecording || isConflicting {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .strokeBorder(isRecording ? Theme.Color.accentMain : Theme.Color.accentDim, lineWidth: Theme.Stroke.iconActive)
                }
            }
            .background {
                if isRecording { KeyCaptureView(capture: onKey, cancel: onCancel).frame(width: 0, height: 0) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isRecording ? "Recording. Press a key combination, Escape to cancel, Delete to clear." : text)
        .accessibilityHint(isConflicting ? "This key is also assigned to another action." : "Press to record a key combination.")
    }
}

/// The first responder while a field records, so recorded keys cannot reach playback.
private struct KeyCaptureView: NSViewRepresentable {
    let capture: (KeyBinding?) -> Void
    let cancel: () -> Void
    func makeNSView(context: Context) -> SettingsKeyCaptureResponder {
        let view = SettingsKeyCaptureResponder()
        view.capture = capture
        view.cancel = cancel
        return view
    }
    func updateNSView(_ nsView: SettingsKeyCaptureResponder, context: Context) {
        nsView.capture = capture
        nsView.cancel = cancel
    }
}

final class SettingsKeyCaptureResponder: NSView {
    var capture: ((KeyBinding?) -> Void)?
    var cancel: (() -> Void)?
    private var finished = false
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in if let self { self.window?.makeFirstResponder(self) } }
    }
    override func resignFirstResponder() -> Bool {
        // Clicking another control ends the recording without a change.
        if !finished { finished = true; DispatchQueue.main.async { [cancel] in cancel?() } }
        return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }
    /// NSApplication offers every key-down to `performKeyEquivalent` before `keyDown`, so plain
    /// Esc and Delete arrive here first and must be interpreted, not recorded.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        return handle(event)
    }
    /// The one place a key is interpreted while recording. Returns whether the key was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        if event.isARepeat { return true }
        let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        switch event.keyCode {
        case 53 where plain: finish { cancel?() } // Esc keeps the old binding
        case 51 where plain, 117 where plain: finish { capture?(nil) } // Delete, Forward Delete clear it
        default:
            // ⌘Q always quits (D026); every other combination is recorded.
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" { return false }
            guard let binding = KeyBinding(event: event) else { return false }
            finish { capture?(binding) }
        }
        return true
    }
    private func finish(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        action()
    }
}

/// A key option in "VLC modules" (engine `key-*` values): records in place like Keyboard Shortcuts.
struct SettingsKeyValueField: View {
    let row: SettingsRow
    @Environment(SettingsModel.self) private var settings
    @Environment(InterfaceModel.self) private var interface
    @State private var recording = false

    var body: some View {
        ShortcutKeyField(text: KeyBinding(vlcString: settings.string(row))?.displayString ?? "None",
                         isRecording: recording, width: nil, label: row.label) {
            recording = true
        } onKey: { binding in
            recording = false
            settings.setValue(.string(binding?.vlcString ?? ""), for: row)
        } onCancel: {
            recording = false
        }
        .onChange(of: recording) { _, value in interface.isCapturingShortcut = value }
        .onDisappear { if recording { interface.isCapturingShortcut = false } }
    }
}
