import Foundation

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case interval
    case fixedTimes

    var id: String { rawValue }
    var label: String {
        switch self {
        case .interval: return "Every X minutes"
        case .fixedTimes: return "At fixed times"
        }
    }
}

enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    case banner
    case system
    case fullScreen

    var id: String { rawValue }
    var label: String {
        switch self {
        case .banner: return "Banner (top-right corner)"
        case .system: return "macOS notification"
        case .fullScreen: return "Full screen break"
        }
    }
}

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case eyes, stretch, exercise, posture, hydrate, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .eyes: return "Eye rest"
        case .stretch: return "Stretching"
        case .exercise: return "Exercise"
        case .posture: return "Posture"
        case .hydrate: return "Hydration"
        case .custom: return "No suggestion"
        }
    }
    var symbol: String {
        switch self {
        case .eyes: return "eye"
        case .stretch: return "figure.flexibility"
        case .exercise: return "figure.strengthtraining.functional"
        case .posture: return "figure.stand"
        case .hydrate: return "drop.fill"
        case .custom: return "bell.fill"
        }
    }
}

struct TimeOfDay: Codable, Hashable, Identifiable {
    var id = UUID()
    var hour: Int
    var minute: Int

    var formatted: String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }
}

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var message: String
    var enabled = true

    var scheduleKind: ScheduleKind = .interval
    var intervalMinutes = 30
    var times: [TimeOfDay] = []
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday) on which fixed times fire.
    var weekdays: Set<Int> = Set(1...7)

    var alertStyle: AlertStyle = .banner
    var playChime = true
    var soundName = "Glass"
    /// Banner auto-dismiss delay; 0 keeps it until dismissed.
    var bannerSeconds = 20
    /// Length of a full screen break.
    var breakSeconds = 60
    /// Whether a full screen break can be skipped or snoozed.
    var allowSkip = true
    var category: ExerciseCategory = .stretch

    /// Changes to these fields reset the reminder's countdown.
    var scheduleSignature: String {
        let t = times.map { "\($0.hour):\($0.minute)" }.sorted().joined(separator: ",")
        return "\(enabled)|\(scheduleKind.rawValue)|\(intervalMinutes)|\(t)|\(weekdays.sorted())"
    }

    var scheduleSummary: String {
        switch scheduleKind {
        case .interval:
            return "Every \(Self.durationText(minutes: intervalMinutes))"
        case .fixedTimes:
            if times.isEmpty { return "No times set" }
            let list = times.sorted { $0.minutesSinceMidnight < $1.minutesSinceMidnight }.map(\.formatted).joined(separator: ", ")
            return weekdays.count == 7 ? "Daily at \(list)" : "\(list) on \(weekdays.count) days"
        }
    }

    func nextFire(after date: Date) -> Date? {
        switch scheduleKind {
        case .interval:
            return date.addingTimeInterval(TimeInterval(max(1, intervalMinutes) * 60))
        case .fixedTimes:
            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: date)
            var best: Date?
            for t in times {
                for offset in 0..<8 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: startOfDay),
                          let candidate = cal.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day)
                    else { continue }
                    if candidate > date && weekdays.contains(cal.component(.weekday, from: candidate)) {
                        if best == nil || candidate < best! { best = candidate }
                        break
                    }
                }
            }
            return best
        }
    }

    static func durationText(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static var defaults: [Reminder] {
        [
            Reminder(name: "Eye break (20-20-20)",
                     message: "Look at something 20 feet away for 20 seconds.",
                     intervalMinutes: 20, alertStyle: .banner, soundName: "Glass",
                     bannerSeconds: 20, category: .eyes),
            Reminder(name: "Stretch break",
                     message: "Stand up, stretch and move around for a bit.",
                     intervalMinutes: 60, alertStyle: .fullScreen, soundName: "Hero",
                     breakSeconds: 120, category: .stretch),
            Reminder(name: "Drink water",
                     message: "Grab a glass of water.",
                     scheduleKind: .fixedTimes,
                     times: [TimeOfDay(hour: 11, minute: 0), TimeOfDay(hour: 15, minute: 0)],
                     weekdays: Set(2...6), alertStyle: .system, soundName: "Pop", category: .hydrate),
            Reminder(name: "Quick workout",
                     message: "Time for a 5 minute workout.",
                     enabled: false, scheduleKind: .fixedTimes,
                     times: [TimeOfDay(hour: 17, minute: 30)],
                     weekdays: Set(2...6), alertStyle: .fullScreen, soundName: "Submarine",
                     breakSeconds: 300, category: .exercise),
        ]
    }

    static func new() -> Reminder {
        Reminder(name: "New reminder", message: "Time for a short break.")
    }
}

struct GeneralSettings: Codable, Equatable {
    var activeHoursEnabled = false
    var activeStart = TimeOfDay(hour: 9, minute: 0)
    var activeEnd = TimeOfDay(hour: 18, minute: 0)
    var showCountdown = true
    var snoozeMinutes = 5
    /// Restart interval timers when the Mac wakes from sleep.
    var resetOnWake = true

    func isWithinActiveHours(_ date: Date) -> Bool {
        guard activeHoursEnabled else { return true }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let s = activeStart.minutesSinceMidnight, e = activeEnd.minutesSinceMidnight
        return s <= e ? (m >= s && m < e) : (m >= s || m < e)
    }
}

enum Sounds {
    static let names = ["Glass", "Ping", "Pop", "Hero", "Purr", "Tink", "Submarine",
                        "Blow", "Bottle", "Frog", "Funk", "Morse", "Sosumi", "Basso"]
}
