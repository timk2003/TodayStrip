import SwiftUI

/// The detail panel behind the strip.
///
/// Ordered by how often it is opened for each thing: the next event first, the timer under it
/// (the only genuinely interactive part), then the note, then the ambient readings as a footer.
struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    if model.preferences.isEnabled(.event) {
                        EventSection(source: model.calendar)
                    }
                    if model.preferences.isEnabled(.timer) {
                        TimerSection(timer: model.timer, presets: model.preferences.timerPresets)
                    }
                    if model.preferences.isEnabled(.note) {
                        NoteSection(source: model.note)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            StatusFooter(model: model)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.system(size: 13, weight: .semibold))
                Text(Date(), format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                Button {
                    model.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Menu {
                    Button("Quit TodayStrip") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .frame(width: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }
}

/// Small caps label that introduces each block.
struct SectionLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.tertiary)
    }
}

/// Rounded container shared by the sections, so they read as one family.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}
