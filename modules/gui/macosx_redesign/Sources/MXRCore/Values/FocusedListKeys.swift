/// Keys that a keyboard-focused panel list (queue, bookmarks) handles itself, so the app's key
/// monitor and bare menu equivalents let them through instead of running VLC's hotkeys (G-03):
/// Return plays or jumps, ↑/↓ move the selection, ←/→ stay with the list, ⌥↑/⌥↓ reorder and
/// Delete removes. Space is not one of them: it stays play/pause everywhere.
public enum FocusedListKeys {
    public static func contains(_ binding: KeyBinding) -> Bool {
        if binding.modifiers.isEmpty {
            return ["Enter", "Up", "Down", "Left", "Right", "Backspace", "Delete"].contains(binding.key)
        }
        return binding.modifiers == .option && ["Up", "Down"].contains(binding.key)
    }
}
