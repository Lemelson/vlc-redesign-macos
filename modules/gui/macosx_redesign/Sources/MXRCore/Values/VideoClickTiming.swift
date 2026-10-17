import Foundation

/// Only reserve the double-click interval when a second click can perform an action.
public enum VideoClickTiming {
    public static func singleClickDelay(doubleClickEnabled: Bool, systemInterval: TimeInterval) -> TimeInterval {
        doubleClickEnabled ? systemInterval : 0
    }
}
