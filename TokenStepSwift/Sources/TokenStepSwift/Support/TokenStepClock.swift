import Foundation

/// The single source of truth for the time zone TokenStep uses to split usage into days.
enum TokenStepClock {
    /// Snapshots and caches written before the zone was recorded were always
    /// computed in this zone, so a missing marker is read as this value.
    static let legacyTimeZoneIdentifier = "Asia/Shanghai"

    /// Follows the system zone, including changes while the app is running.
    /// `TOKENSTEP_TIMEZONE` pins a zone for fixture checks and debugging.
    static var timeZone: TimeZone {
        if let override = ProcessInfo.processInfo.environment["TOKENSTEP_TIMEZONE"],
           let zone = TimeZone(identifier: override) {
            return zone
        }
        return .autoupdatingCurrent
    }

    static var identifier: String {
        timeZone.identifier
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func matchesCurrent(_ storedIdentifier: String?) -> Bool {
        (storedIdentifier ?? legacyTimeZoneIdentifier) == identifier
    }
}
