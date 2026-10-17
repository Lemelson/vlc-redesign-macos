import Foundation

/// A point or span on a media timeline, stored like VLC's `vlc_tick_t`: signed microseconds.
///
/// Used for playback time, lengths, delays (negative allowed) and chapter/bookmark offsets.
public struct MediaTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Signed microseconds (VLC `vlc_tick_t` without the `VLC_TICK_0` offset).
    public var microseconds: Int64

    /// Creates a time from signed microseconds.
    public init(microseconds: Int64) { self.microseconds = microseconds }

    /// Creates a time from a Swift `Duration` (sub-microsecond parts are truncated).
    public init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        self.microseconds = seconds * 1_000_000 + attoseconds / 1_000_000_000_000
    }

    /// Zero.
    public static let zero = MediaTime(microseconds: 0)

    /// A time of `seconds` seconds (fractions allowed).
    public static func seconds(_ seconds: Double) -> MediaTime {
        MediaTime(microseconds: Int64((seconds * 1_000_000).rounded()))
    }

    /// A time of `milliseconds` milliseconds.
    public static func milliseconds(_ milliseconds: Int64) -> MediaTime {
        MediaTime(microseconds: milliseconds * 1_000)
    }

    /// A time from hours, minutes, seconds and optional milliseconds (e.g. `.hms(0, 25, 40)`).
    public static func hms(_ hours: Int, _ minutes: Int, _ seconds: Int, milliseconds: Int = 0) -> MediaTime {
        let total = Int64(hours) * 3_600_000 + Int64(minutes) * 60_000 + Int64(seconds) * 1_000 + Int64(milliseconds)
        return .milliseconds(total)
    }

    /// The time in (fractional) seconds.
    public var seconds: Double { Double(microseconds) / 1_000_000 }

    /// The time in whole milliseconds (truncated toward zero).
    public var milliseconds: Int64 { microseconds / 1_000 }

    /// The time as a Swift `Duration`.
    public var duration: Duration { .microseconds(microseconds) }

    /// The absolute value.
    public var magnitude: MediaTime { MediaTime(microseconds: microseconds == .min ? .max : abs(microseconds)) }

    public static func < (lhs: MediaTime, rhs: MediaTime) -> Bool { lhs.microseconds < rhs.microseconds }
    public static func + (lhs: MediaTime, rhs: MediaTime) -> MediaTime { MediaTime(microseconds: lhs.microseconds &+ rhs.microseconds) }
    public static func - (lhs: MediaTime, rhs: MediaTime) -> MediaTime { MediaTime(microseconds: lhs.microseconds &- rhs.microseconds) }
    public static prefix func - (value: MediaTime) -> MediaTime { MediaTime(microseconds: -value.microseconds) }
    public static func += (lhs: inout MediaTime, rhs: MediaTime) { lhs = lhs + rhs }
    public static func -= (lhs: inout MediaTime, rhs: MediaTime) { lhs = lhs - rhs }
    public static func * (lhs: MediaTime, rhs: Double) -> MediaTime {
        MediaTime(microseconds: Int64((Double(lhs.microseconds) * rhs).rounded()))
    }

    /// Clamps the value to `range`.
    public func clamped(to range: ClosedRange<MediaTime>) -> MediaTime {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    public var description: String { formatted(.hoursMinutesSeconds) }

    // MARK: Formatting

    /// Text formats used by the design.
    public enum Format: Sendable {
        /// `00:02:10`, always with hours (control bar, chapters, seek preview). Negative: `-00:23:30`.
        case hoursMinutesSeconds
        /// `00:00:42:023`: hours, minutes, seconds and milliseconds (bookmarks).
        case hoursMinutesSecondsMilliseconds
        /// `23:06`, or `1:02:03` when an hour or longer (queue and mini-player durations).
        case compact
        /// `2h 3m`, `47m`, `35s` (queue header summaries).
        case summary
        /// `-2.000 s`, `0.000 s`: signed seconds with three decimals (delay fields).
        case signedSeconds
    }

    /// Formats the time for display. Formatting is locale-independent, as in the design.
    public func formatted(_ format: Format) -> String {
        let negative = microseconds < 0
        let totalMs = Int64(microseconds.magnitude / 1_000)
        let totalSeconds = totalMs / 1_000
        let h = totalSeconds / 3_600
        let m = (totalSeconds % 3_600) / 60
        let s = totalSeconds % 60
        let sign = negative ? "-" : ""
        switch format {
        case .hoursMinutesSeconds:
            return sign + Self.pad(h) + ":" + Self.pad(m) + ":" + Self.pad(s)
        case .hoursMinutesSecondsMilliseconds:
            let ms = totalMs % 1_000
            return sign + Self.pad(h) + ":" + Self.pad(m) + ":" + Self.pad(s) + ":" + Self.pad(ms, width: 3)
        case .compact:
            if h > 0 { return sign + String(h) + ":" + Self.pad(m) + ":" + Self.pad(s) }
            return sign + Self.pad(m) + ":" + Self.pad(s)
        case .summary:
            if h > 0 { return sign + "\(h)h \(m)m" }
            if m > 0 { return sign + "\(m)m" }
            return sign + "\(s)s"
        case .signedSeconds:
            let value = seconds
            return String(format: "%.3f s", value == 0 ? 0 : value)
        }
    }

    private static func pad(_ value: Int64, width: Int = 2) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }

    /// Parses `HH:MM:SS`, `MM:SS`, `SS` or `HH:MM:SS.mmm` (the editable time label, S02).
    /// Returns nil for malformed input.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var negative = false
        var body = Substring(trimmed)
        if body.hasPrefix("-") { negative = true; body = body.dropFirst() }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        self = .seconds(negative ? -total : total)
    }
}

extension MediaTime: ExpressibleByIntegerLiteral {
    /// An integer literal is a number of **seconds** (e.g. `let skip: MediaTime = 10`).
    public init(integerLiteral value: Int64) { self.microseconds = value * 1_000_000 }
}
