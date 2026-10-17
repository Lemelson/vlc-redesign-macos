import Foundation

/// A main-actor multicast channel used by backends to notify models.
///
/// Listeners are registered with an owner object and are dropped automatically when the owner is
/// deallocated, so models never need to unregister in `deinit` (which is nonisolated in Swift 6).
/// Backend implementations (mock and VLC) should use this type to implement `addListener`.
@MainActor
public final class EventChannel<Event> {
    private struct Entry {
        weak var owner: AnyObject?
        let handler: @MainActor (Event) -> Void
    }

    private var entries: [Entry] = []

    /// Creates an empty channel.
    public init() {}

    /// Registers `handler`, called on the main actor for every event until `owner` is deallocated
    /// or ``remove(_:)`` is called with it.
    public func add(_ owner: AnyObject, handler: @escaping @MainActor (Event) -> Void) {
        entries.append(Entry(owner: owner, handler: handler))
    }

    /// Unregisters every handler registered with `owner`.
    public func remove(_ owner: AnyObject) {
        entries.removeAll { $0.owner == nil || $0.owner === owner }
    }

    /// The number of live listeners (for tests and diagnostics).
    public var listenerCount: Int { entries.lazy.filter { $0.owner != nil }.count }

    /// Delivers `event` synchronously to every live listener, in registration order.
    public func send(_ event: Event) {
        entries.removeAll { $0.owner == nil }
        for entry in entries where entry.owner != nil {
            entry.handler(event)
        }
    }
}
