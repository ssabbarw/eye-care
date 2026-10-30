import AppKit
import Combine

/// Owns the reminders, persists them, and fires them when they're due.
@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published var reminders: [Reminder] {
        didSet { persist(); reconcile() }
    }
    @Published var general: GeneralSettings {
        didSet { persist(); updateMenuBarTitle() }
    }
    @Published private(set) var nextFire: [UUID: Date] = [:]
    /// `Date.distantFuture` means paused until manually resumed.
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var menuBarTitle = ""

    private var signatures: [UUID: String] = [:]
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let remindersKey = "reminders.v1"
    private let generalKey = "general.v1"

    private init() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: remindersKey),
           let saved = try? decoder.decode([Reminder].self, from: data) {
            reminders = saved
        } else {
            reminders = Reminder.defaults
        }
        if let data = defaults.data(forKey: generalKey),
           let saved = try? decoder.decode(GeneralSettings.self, from: data) {
            general = saved
        } else {
            general = GeneralSettings()
        }
        reconcile()
    }

    var isPaused: Bool { pausedUntil != nil }

    var upcoming: [(reminder: Reminder, date: Date)] {
        reminders.compactMap { r in
            guard r.enabled, let d = nextFire[r.id] else { return nil }
            return (r, d)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.general.resetOnWake else { return }
                self.restartAll()
            }
        }
        tick()
    }

    private func tick() {
        let now = Date()
        if let paused = pausedUntil {
            if paused > now {
                updateMenuBarTitle()
                return
            }
            resume()
        }

        let presenter = AlertPresenter.shared
        for r in reminders where r.enabled {
            guard let due = nextFire[r.id], due <= now else { continue }
            // Don't stack alerts on top of a running full screen break.
            if presenter.isBreakActive {
                nextFire[r.id] = now.addingTimeInterval(60)
                continue
            }
            // A fixed-time reminder missed by a long time (e.g. Mac was asleep) is skipped.
            let missed = r.scheduleKind == .fixedTimes && now.timeIntervalSince(due) > 10 * 60
            nextFire[r.id] = r.nextFire(after: now)
            if missed || !general.isWithinActiveHours(now) { continue }
            presenter.present(r)
        }
        updateMenuBarTitle()
    }

    /// Recomputes countdowns for reminders that are new or whose schedule changed.
    private func reconcile() {
        let now = Date()
        let ids = Set(reminders.map(\.id))
        var next = nextFire.filter { ids.contains($0.key) }
        signatures = signatures.filter { ids.contains($0.key) }

        for r in reminders {
            let sig = r.scheduleSignature
            if !r.enabled {
                next[r.id] = nil
            } else if signatures[r.id] != sig || next[r.id] == nil {
                next[r.id] = r.nextFire(after: now)
            }
            signatures[r.id] = sig
        }
        if next != nextFire { nextFire = next }
        updateMenuBarTitle()
    }

    private func updateMenuBarTitle() {
        let title: String
        if !general.showCountdown {
            title = ""
        } else if pausedUntil != nil {
            title = "Paused"
        } else if let soonest = upcoming.first {
            title = Self.shortCountdown(soonest.date.timeIntervalSinceNow)
        } else {
            title = ""
        }
        if title != menuBarTitle { menuBarTitle = title }
    }

    static func shortCountdown(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(reminders) { defaults.set(data, forKey: remindersKey) }
        if let data = try? encoder.encode(general) { defaults.set(data, forKey: generalKey) }
    }

    // MARK: - Actions

    func trigger(_ id: UUID) {
        guard let r = reminders.first(where: { $0.id == id }) else { return }
        AlertPresenter.shared.present(r)
        if r.enabled, r.scheduleKind == .interval { nextFire[id] = r.nextFire(after: Date()) }
    }

    /// Restarts the countdown from now (for interval reminders this is "start counting from now").
    func restart(_ id: UUID) {
        guard let r = reminders.first(where: { $0.id == id }), r.enabled else { return }
        nextFire[id] = r.nextFire(after: Date())
        updateMenuBarTitle()
    }

    func restartAll() {
        let now = Date()
        for r in reminders where r.enabled { nextFire[r.id] = r.nextFire(after: now) }
        updateMenuBarTitle()
    }

    func snooze(_ id: UUID) {
        guard reminders.contains(where: { $0.id == id }) else { return }
        nextFire[id] = Date().addingTimeInterval(TimeInterval(general.snoozeMinutes * 60))
        updateMenuBarTitle()
    }

    /// Called when a full screen break ends or is skipped: interval timers count from the end of the break.
    func breakFinished(_ id: UUID) {
        guard let r = reminders.first(where: { $0.id == id }), r.enabled, r.scheduleKind == .interval else { return }
        nextFire[id] = r.nextFire(after: Date())
        updateMenuBarTitle()
    }

    func pause(minutes: Int?) {
        pausedUntil = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) } ?? .distantFuture
        updateMenuBarTitle()
    }

    func resume() {
        pausedUntil = nil
        restartAll()
    }

    func addReminder() -> UUID {
        let r = Reminder.new()
        reminders.append(r)
        return r.id
    }

    func delete(_ id: UUID) {
        reminders.removeAll { $0.id == id }
    }
}
