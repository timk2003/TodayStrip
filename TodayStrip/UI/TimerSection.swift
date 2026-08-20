import SwiftUI

/// Countdown and stopwatch controls.
///
/// Idle shows the presets; running shows the clock and the controls that matter mid-session.
/// Nothing is hidden behind a mode switch, because deciding "countdown or stopwatch" is the same
/// gesture as starting one.
struct TimerSection: View {
    @Bindable var timer: TimerSource
    let presets: [Int]

    @State private var customMinutes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(symbol: "timer", title: "Timer")

            Card {
                switch timer.mode {
                case .idle:
                    idleControls
                case .countdown, .stopwatch:
                    runningControls
                case .finished:
                    finishedControls
                }
            }
        }
    }

    // MARK: - Idle

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)m") { timer.startCountdown(minutes: minutes) }
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                TextField("min", text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 52)
                    .onSubmit(startCustom)

                Button("Start", action: startCustom)
                    .controlSize(.small)
                    .disabled(Int(customMinutes) == nil)

                Spacer(minLength: 0)

                Button {
                    timer.startStopwatch()
                } label: {
                    Label("Stopwatch", systemImage: "stopwatch")
                }
                .controlSize(.small)
            }
        }
    }

    private func startCustom() {
        guard let minutes = Int(customMinutes), minutes > 0 else { return }
        timer.startCountdown(minutes: minutes)
        customMinutes = ""
    }

    // MARK: - Running

    private var runningControls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(clock)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text(timer.mode == .stopwatch ? "elapsed" : "left")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let progress = timer.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(timer.remaining <= 60 ? .orange : .accentColor)
            }

            HStack(spacing: 6) {
                Button {
                    timer.toggle()
                } label: {
                    Label(
                        timer.isRunning ? "Pause" : "Resume",
                        systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                    )
                }
                .controlSize(.small)

                if timer.mode == .countdown {
                    Button("+5m") { timer.extend(by: 5 * 60) }
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                Button("Reset") { timer.reset() }
                    .controlSize(.small)
            }
        }
    }

    private var clock: String {
        TimerSource.clock(timer.mode == .stopwatch ? timer.elapsed : timer.remaining)
    }

    // MARK: - Finished

    private var finishedControls: some View {
        HStack {
            Label("Time's up", systemImage: "bell.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
            Spacer()
            Button("+5m") { timer.extend(by: 5 * 60) }
                .controlSize(.small)
            Button("Dismiss") { timer.reset() }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
    }
}
