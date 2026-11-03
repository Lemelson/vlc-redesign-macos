import AppKit

/// Turns on the application's accessibility tree so offscreen hosting tests can find SwiftUI
/// elements (buttons, rows, custom actions) without VoiceOver running.
///
/// AppKit builds the tree only when an assistive client asks for it; setting the private
/// `AXManualAccessibility` (and, for SwiftUI's enhanced elements, `AXEnhancedUserInterface`)
/// attribute on NSApp is how a client does that. The only setter for an arbitrary attribute is the
/// informal `accessibilitySetValue:forAttribute:`, deprecated in Swift since macOS 10.10 but still
/// the method AppKit dispatches. It is called through the runtime once, here, so the test target
/// stays warning-free.
@MainActor
func enableAccessibilityTree(enhanced: Bool = true) {
    let app = NSApplication.shared
    typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject) -> Void
    let selector = NSSelectorFromString("accessibilitySetValue:forAttribute:")
    let set = unsafeBitCast(app.method(for: selector), to: Setter.self)
    var attributes = ["AXManualAccessibility"]
    if enhanced { attributes.append("AXEnhancedUserInterface") }
    for attribute in attributes { set(app, selector, NSNumber(value: true), attribute as NSString) }
}
