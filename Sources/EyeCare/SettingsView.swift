import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var selection: Selection? = .general

    enum Selection: Hashable {
        case general
        case reminder(UUID)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("General", systemImage: "gearshape").tag(Selection.general)
                }
                Section("Reminders") {
                    ForEach(store.reminders) { r in
                        ReminderRow(reminder: r, next: store.nextFire[r.id])
                            .tag(Selection.reminder(r.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        selection = .reminder(store.addReminder())
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(10)
            }
        } detail: {
            switch selection {
            case .reminder(let id):
                if let binding = binding(for: id) {
                    ReminderEditor(reminder: binding, onDelete: {
                        selection = .general
                        store.delete(id)
                    })
                    .id(id)
                } else {
                    Text("Select a reminder").foregroundStyle(.secondary)
                }
            default:
                GeneralSettingsView()
            }
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    private func binding(for id: UUID) -> Binding<Reminder>? {
        guard let current = store.reminders.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.reminders.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                if let i = store.reminders.firstIndex(where: { $0.id == id }) {
                    store.reminders[i] = newValue
                }
            }
        )
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    let next: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reminder.category.symbol)
                .frame(width: 20)
                .foregroundStyle(reminder.enabled ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.name).lineLimit(1)
                Text(reminder.enabled ? reminder.scheduleSummary : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .opacity(reminder.enabled ? 1 : 0.6)
        .padding(.vertical, 2)
    }
}

// MARK: - Reminder editor

struct ReminderEditor: View {
    @EnvironmentObject var store: ReminderStore
    @Binding var reminder: Reminder
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $reminder.enabled)
                TextField("Name", text: $reminder.name)
                TextField("Message", text: $reminder.message, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Suggestion", selection: $reminder.category) {
                    ForEach(ExerciseCategory.allCases) { c in
                        Label(c.label, systemImage: c.symbol).tag(c)
                    }
                }
            } header: {
                Text("Reminder")
            } footer: {
                if reminder.category != .custom {
                    Text("Each reminder includes a random \(reminder.category.label.lowercased()) suggestion.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Schedule") {
                Picker("Repeat", selection: $reminder.scheduleKind) {
                    ForEach(ScheduleKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch reminder.scheduleKind {
                case .interval: intervalSection
                case .fixedTimes: fixedTimesSection
                }

                nextFireRow
            }

            Section("Alert") {
                Picker("Style", selection: $reminder.alertStyle) {
                    ForEach(AlertStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)

                switch reminder.alertStyle {
                case .banner:
                    Stepper(value: $reminder.bannerSeconds, in: 0...300, step: 5) {
                        Text(reminder.bannerSeconds == 0
                             ? "Stay until dismissed"
                             : "Hide after \(reminder.bannerSeconds) seconds")
                    }
                case .system:
                    NotificationPermissionRow()
                case .fullScreen:
                    Stepper(value: $reminder.breakSeconds, in: 10...1800, step: 10) {
                        Text("Break length: \(Self.formatSeconds(reminder.breakSeconds))")
                    }
                    Toggle("Allow skipping or snoozing the break", isOn: $reminder.allowSkip)
                }

                Toggle("Play a chime", isOn: $reminder.playChime)
                if reminder.playChime {
                    HStack {
                        Picker("Sound", selection: $reminder.soundName) {
                            ForEach(Sounds.names, id: \.self) { Text($0).tag($0) }
                        }
                        Button {
                            Chime.play(reminder.soundName)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .help("Preview sound")
                    }
                }
            }

            Section {
                HStack {
                    Button("Test Now") { store.trigger(reminder.id) }
                    Spacer()
                    Button("Delete Reminder", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(reminder.name)
        .onChange(of: reminder.alertStyle) { style in
            if style == .system { NotificationManager.shared.requestAuthorization() }
        }
        .confirmationDialog("Delete “\(reminder.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder private var intervalSection: some View {
        HStack {
            Text("Every")
            TextField("", value: $reminder.intervalMinutes, format: .number)
                .labelsHidden()
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
            Stepper("", value: $reminder.intervalMinutes, in: 1...720).labelsHidden()
            Text("minutes")
            Spacer()
        }
        .onChange(of: reminder.intervalMinutes) { v in
            if v < 1 { reminder.intervalMinutes = 1 }
            if v > 1440 { reminder.intervalMinutes = 1440 }
        }
        HStack(spacing: 6) {
            ForEach([20, 30, 45, 60, 90], id: \.self) { m in
                Button(Reminder.durationText(minutes: m)) { reminder.intervalMinutes = m }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var fixedTimesSection: some View {
        ForEach($reminder.times) { $time in
            HStack {
                DatePicker("Time", selection: Self.dateBinding($time), displayedComponents: .hourAndMinute)
                Button {
                    reminder.times.removeAll { $0.id == time.id }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        Button {
            let last = reminder.times.last
            reminder.times.append(TimeOfDay(hour: min(23, (last?.hour ?? 8) + 1), minute: last?.minute ?? 0))
        } label: {
            Label("Add Time", systemImage: "plus")
        }
        WeekdayPicker(selection: $reminder.weekdays)
    }

    @ViewBuilder private var nextFireRow: some View {
        HStack {
            if !reminder.enabled {
                Text("Reminder is off").foregroundStyle(.secondary)
            } else if let next = store.nextFire[reminder.id] {
                Text("Next: \(next.formatted(date: .abbreviated, time: .shortened)) (\(Text(next, style: .relative)))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not scheduled").foregroundStyle(.secondary)
            }
            Spacer()
            if reminder.enabled && reminder.scheduleKind == .interval {
                Button("Start Counting From Now") { store.restart(reminder.id) }
            }
        }
        .font(.callout)
    }

    static func dateBinding(_ time: Binding<TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: time.wrappedValue.hour, minute: time.wrappedValue.minute,
                                         second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                time.wrappedValue.hour = c.hour ?? 0
                time.wrappedValue.minute = c.minute ?? 0
            }
        )
    }

    static func formatSeconds(_ s: Int) -> String {
        if s < 60 { return "\(s) sec" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) sec"
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            Text("Days")
            Spacer()
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button(symbols[day - 1]) {
                    if on { selection.remove(day) } else { selection.insert(day) }
                }
                .buttonStyle(.bordered)
                .tint(on ? .accentColor : .gray)
                .opacity(on ? 1 : 0.6)
                .controlSize(.small)
            }
        }
    }
}

struct NotificationPermissionRow: View {
    @State private var status = NotificationManager.shared.status

    var body: some View {
        HStack {
            switch status {
            case .authorized, .provisional:
                Label("Notifications allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied:
                Label("Notifications are blocked — a banner is shown instead", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            default:
                Label("Permission not granted yet — a banner is shown instead", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .denied {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            } else if status == .notDetermined {
                Button("Allow Notifications") {
                    NotificationManager.shared.requestAuthorization { status = NotificationManager.shared.status }
                }
            }
        }
        .font(.callout)
        .onAppear {
            NotificationManager.shared.refreshStatus { status = NotificationManager.shared.status }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Eye Care at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Only remind during active hours", isOn: $store.general.activeHoursEnabled)
                if store.general.activeHoursEnabled {
                    DatePicker("From", selection: ReminderEditor.dateBinding($store.general.activeStart),
                               displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: ReminderEditor.dateBinding($store.general.activeEnd),
                               displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Active Hours")
            } footer: {
                Text("Reminders that come due outside these hours are skipped silently.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Show countdown in the menu bar", isOn: $store.general.showCountdown)
                Stepper("Snooze for \(store.general.snoozeMinutes) minutes",
                        value: $store.general.snoozeMinutes, in: 1...60)
                Toggle("Restart interval timers after the Mac wakes from sleep", isOn: $store.general.resetOnWake)
            }

            Section("Status") {
                if let paused = store.pausedUntil {
                    HStack {
                        Text(paused == .distantFuture
                             ? "All reminders are paused."
                             : "Paused until \(paused.formatted(date: .omitted, time: .shortened)).")
                        Spacer()
                        Button("Resume") { store.resume() }
                    }
                } else {
                    HStack {
                        Text("\(store.upcoming.count) active reminder(s).")
                        Spacer()
                        Button("Pause 1 Hour") { store.pause(minutes: 60) }
                        Button("Restart All Timers") { store.restartAll() }
                    }
                }
                NotificationPermissionRow()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
