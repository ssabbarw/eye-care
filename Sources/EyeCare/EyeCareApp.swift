import AppKit
import SwiftUI

@main
struct EyeCareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            if store.menuBarTitle.isEmpty {
                Image(systemName: store.isPaused ? "eye.slash" : "eye")
            } else {
                Text("\(Image(systemName: store.isPaused ? "eye.slash" : "eye")) \(store.menuBarTitle)")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenuIfNeeded()
        NotificationManager.shared.setup()

        let store = ReminderStore.shared
        store.start()
        if store.reminders.contains(where: { $0.enabled && $0.alertStyle == .system }) {
            NotificationManager.shared.requestAuthorization()
        }

        let firstLaunchKey = "hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            SettingsWindowController.shared.show()
        }
    }

    /// Menu bar apps have no visible main menu, so make sure ⌘C / ⌘V / ⌘A work in text fields.
    private func installEditMenuIfNeeded() {
        let main = NSApp.mainMenu ?? NSMenu()
        if main.items.contains(where: { $0.submenu?.title == "Edit" }) { return }
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
    }
}

struct MenuContent: View {
    @EnvironmentObject var store: ReminderStore

    var body: some View {
        if let paused = store.pausedUntil {
            Text(paused == .distantFuture
                 ? "Paused"
                 : "Paused until \(paused.formatted(date: .omitted, time: .shortened))")
            Button("Resume") { store.resume() }
        } else if store.upcoming.isEmpty {
            Text("No active reminders")
        } else {
            ForEach(store.upcoming, id: \.reminder.id) { item in
                Text("\(item.reminder.name) — \(item.date.formatted(date: .omitted, time: .shortened)) (in \(ReminderStore.shortCountdown(item.date.timeIntervalSinceNow)))")
            }
        }

        Divider()

        Menu("Take a Break Now") {
            ForEach(store.reminders) { r in
                Button(r.name) { store.trigger(r.id) }
            }
        }
        if !store.isPaused {
            Menu("Pause Reminders") {
                Button("For 15 minutes") { store.pause(minutes: 15) }
                Button("For 30 minutes") { store.pause(minutes: 30) }
                Button("For 1 hour") { store.pause(minutes: 60) }
                Button("For 2 hours") { store.pause(minutes: 120) }
                Divider()
                Button("Until I resume") { store.pause(minutes: nil) }
            }
        }
        Button("Restart All Timers") { store.restartAll() }

        Divider()

        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")
        Button("Quit Eye Care") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(ReminderStore.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Eye Care"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 860, height: 620))
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("EyeCareSettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
