import AppKit
import SwiftUI

// MARK: - Banner

struct BannerView: View {
    let reminder: Reminder
    let tip: Exercise?
    let snoozeMinutes: Int
    let onDone: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reminder.category.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor.gradient))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(reminder.name).font(.headline)
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                if !reminder.message.isEmpty {
                    Text(reminder.message).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tip {
                    Text("\(tip.title): ").bold() + Text(tip.detail)
                }
                HStack(spacing: 8) {
                    Button("Done", action: onDone).keyboardShortcut(.defaultAction)
                    Button("Snooze \(snoozeMinutes)m", action: onSnooze)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
            .font(.caption)
            .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(VisualEffect(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: - Full screen break

@MainActor
final class BreakSession: ObservableObject {
    enum Outcome { case completed, skipped, snoozed }

    let reminder: Reminder
    let total: Int
    @Published var remaining: Int
    @Published var tip: Exercise?
    var onFinish: ((Outcome) -> Void)?
    private var timer: Timer?

    init(reminder: Reminder, tip: Exercise?) {
        self.reminder = reminder
        self.tip = tip
        total = max(5, reminder.breakSeconds)
        remaining = total
    }

    func start() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.finish(.completed) }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func finish(_ outcome: Outcome) {
        stop()
        let handler = onFinish
        onFinish = nil
        handler?(outcome)
    }

    func shuffleTip() {
        tip = reminder.category.randomExercise(excluding: tip)
    }

    var progress: Double { Double(total - remaining) / Double(total) }
    var remainingText: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }
}

struct BreakView: View {
    @ObservedObject var session: BreakSession
    let isPrimary: Bool

    var body: some View {
        ZStack {
            VisualEffect(material: .fullScreenUI, blending: .behindWindow)
            LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.22).opacity(0.85),
                                    Color(red: 0.03, green: 0.25, blue: 0.28).opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if isPrimary { content } else { secondary }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var secondary: some View {
        VStack(spacing: 12) {
            Text(session.reminder.name).font(.system(size: 32, weight: .bold))
            Text(session.remainingText).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private var content: some View {
        let r = session.reminder
        return VStack(spacing: 28) {
            Image(systemName: r.category.symbol)
                .font(.system(size: 64, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text(r.name).font(.system(size: 44, weight: .bold))
                if !r.message.isEmpty {
                    Text(r.message).font(.title2).opacity(0.85)
                }
            }
            .multilineTextAlignment(.center)

            if let tip = session.tip {
                VStack(spacing: 8) {
                    Text(tip.title).font(.title3.bold())
                    Text(tip.detail).font(.body).opacity(0.85).multilineTextAlignment(.center)
                    Button {
                        session.shuffleTip()
                    } label: {
                        Label("Another one", systemImage: "shuffle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 520)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: session.progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: session.progress)
                Text(session.remainingText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 180, height: 180)

            if r.allowSkip {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Button("Snooze \(ReminderStore.shared.general.snoozeMinutes) min") { session.finish(.snoozed) }
                        Button("Skip break") { session.finish(.skipped) }
                    }
                    .controlSize(.large)
                    Text("Press Esc to skip").font(.caption).opacity(0.5)
                }
            }
        }
        .padding(40)
    }
}

// MARK: - Helpers

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
