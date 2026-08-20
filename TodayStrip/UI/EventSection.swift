import SwiftUI
import EventKit

/// Next event, with the join link if the invitation carried one.
struct EventSection: View {
    @Bindable var source: CalendarSource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(symbol: "calendar", title: "Next")

            Card {
                switch (source.authorization, source.nextEvent) {
                case (.fullAccess, .some(let next)):
                    details(for: next)
                case (.fullAccess, .none):
                    empty("Nothing left today.")
                case (.notDetermined, _):
                    permission("TodayStrip needs calendar access.", action: "Allow…")
                default:
                    permission(
                        "Calendar access is off. Turn it on in System Settings › Privacy & Security › Calendars.",
                        action: nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func details(for event: CalendarSource.Event) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(CalendarSource.relativeText(for: event))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(event.minutesUntilStart <= 5 ? .orange : .secondary)
                    .layoutPriority(1)
            }

            HStack(spacing: 4) {
                Text(event.start, format: .dateTime.hour().minute())
                Text("–")
                Text(event.end, format: .dateTime.hour().minute())
                if !event.calendarTitle.isEmpty {
                    Text("·")
                    Text(event.calendarTitle).lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if let location = event.location, !location.isEmpty, event.link == nil {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let link = event.link {
                Button {
                    NSWorkspace.shared.open(link.url)
                } label: {
                    Label("Join \(link.title)", systemImage: link.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func permission(_ text: String, action: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action) {
                    Task { await source.requestAccessIfNeeded() }
                }
                .controlSize(.small)
            }
        }
    }
}
