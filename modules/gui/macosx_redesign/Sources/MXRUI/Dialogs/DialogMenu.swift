import MXRDesign
import SwiftUI

struct DialogMenuChoice {
    let title: String
    var isSelected = false
    let action: () -> Void

    init(title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }
}

/// A dialog dropdown (Figma `Dropdown`, D025): SwiftUI supplies the field label, the design-system
/// popup supplies the open list over the field with hover rows, an orange check on the current
/// choice, arrow-key navigation, Esc and click-outside dismissal.
struct DialogMenu<Label: View>: View {
    let choices: () -> [DialogMenuChoice]
    @ViewBuilder let label: () -> Label
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: { label().contentShape(.rect) }
            .buttonStyle(.plain)
            .mxrDropdownList(isPresented: $isOpen, selectedRow: choices().firstIndex { $0.isSelected } ?? 0, fieldInset: 0,
                             overField: true) { // 06m08.5: the header pop-up opens over its field
                choices().map { choice in MXRMenuItem(choice.title, isChecked: choice.isSelected) { choice.action() } }
            }
    }
}
