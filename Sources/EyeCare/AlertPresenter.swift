import AppKit
import SwiftUI

/// Shows a reminder as a top-right banner, a macOS notification, or a full screen break.
@MainActor
final class AlertPresenter {
    static let shared = AlertPresenter()

    private var banners: [BannerPanel] = []
    private var breakWindows: [NSWindow] = []
    private var breakSession: BreakSession?
    private var keyMonitor: Any?

    var isBreakActive: Bool { breakSession != nil }

    func present(_ r: Reminder) {
        let tip = r.category.randomExercise()
        if r.playChime { Chime.play(r.soundName) }

        switch r.alertStyle {
        case .banner:
            showBanner(r, tip: tip)
        case .system:
            if NotificationManager.shared.isAuthorized {
                NotificationManager.shared.post(r, tip: tip)
            } else {
                showBanner(r, tip: tip)
            }
        case .fullScreen:
            showBreak(r, tip: tip)
        }
    }

    // MARK: - Banner

    private func showBanner(_ r: Reminder, tip: Exercise?) {
        let panel = BannerPanel()
        let view = BannerView(
            reminder: r, tip: tip, snoozeMinutes: ReminderStore.shared.general.snoozeMinutes,
            onDone: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.dismissBanner(panel)
            },
            onSnooze: { [weak self, weak panel] in
                ReminderStore.shared.snooze(r.id)
                guard let self, let panel else { return }
                self.dismissBanner(panel)
            }
        )
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)

        banners.insert(panel, at: 0)
        panel.alphaValue = 0
        layoutBanners()
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        if r.bannerSeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(r.bannerSeconds)) { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.dismissBanner(panel)
            }
        }
    }

    private func dismissBanner(_ panel: BannerPanel) {
        guard banners.contains(panel) else { return }
        banners.removeAll { $0 == panel }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
        layoutBanners()
    }

    /// Stacks banners downward from the top-right corner of the active screen.
    private func layoutBanners() {
        guard let screen = Self.activeScreen() else { return }
        let vf = screen.visibleFrame
        let margin: CGFloat = 12
        var top = vf.maxY - margin
        for panel in banners {
            let size = panel.frame.size
            let frame = NSRect(x: vf.maxX - size.width - margin, y: top - size.height,
                               width: size.width, height: size.height)
            panel.setFrame(frame, display: true, animate: panel.alphaValue > 0)
            top = frame.minY - 8
        }
    }

    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Full screen break

    private func showBreak(_ r: Reminder, tip: Exercise?) {
        if breakSession != nil { endBreak() }

        let session = BreakSession(reminder: r, tip: tip)
        session.onFinish = { [weak self] outcome in self?.finishBreak(outcome) }
        breakSession = session

        let primary = Self.activeScreen()
        for screen in NSScreen.screens {
            let window = BreakWindow(contentRect: screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = NSHostingView(rootView: BreakView(session: session, isPrimary: screen == primary))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            if screen == primary { window.makeKey() }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                window.animator().alphaValue = 1
            }
            breakWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let s = self?.breakSession, s.reminder.allowSkip { // Esc
                s.finish(.skipped)
                return nil
            }
            return event
        }
        session.start()
    }

    private func finishBreak(_ outcome: BreakSession.Outcome) {
        guard let session = breakSession else { return }
        let r = session.reminder
        endBreak()
        switch outcome {
        case .completed:
            if r.playChime { Chime.play(r.soundName) }
            ReminderStore.shared.breakFinished(r.id)
        case .skipped:
            ReminderStore.shared.breakFinished(r.id)
        case .snoozed:
            ReminderStore.shared.snooze(r.id)
        }
    }

    private func endBreak() {
        breakSession?.stop()
        breakSession = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        let windows = breakWindows
        breakWindows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { windows.forEach { $0.orderOut(nil) } }
        })
    }
}

// MARK: - Windows

final class BannerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }
}

final class BreakWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Sound

enum Chime {
    private static var current: NSSound?

    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        current?.stop()
        current = sound
        sound.play()
    }
}
