import SwiftUI
import EventKit

struct CalendarSettings: View {
    @Bindable var source: CalendarSource
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            switch source.authorization {
            case .fullAccess:
                calendarList
                options
            case .notDetermined:
                Section {
                    Button("Allow calendar access…") {
                        Task { await source.requestAccessIfNeeded() }
                    }
                }
            default:
                Section {
                    Label {
                        Text("Calendar access is turned off. Enable TodayStrip under System Settings › Privacy & Security › Calendars.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock")
                    }
                    Button("Open System Settings") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { source.refresh() }
    }

    private var calendarList: some View {
        Section("Calendars") {
            if source.availableCalendars.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(source.availableCalendars) { calendar in
                Toggle(isOn: Binding(
                    get: { !preferences.excludedCalendarIDs.contains(calendar.id) },
                    set: { included in
                        var excluded = preferences.excludedCalendarIDs
                        if included { excluded.remove(calendar.id) } else { excluded.insert(calendar.id) }
                        preferences.excludedCalendarIDs = excluded
                        source.refresh()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(calendar.title)
                        Text(calendar.sourceTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var options: some View {
        Section("Options") {
            Toggle("Hide events I declined", isOn: $preferences.hideDeclinedEvents)
                .onChange(of: preferences.hideDeclinedEvents) { source.refresh() }

            Picker("Look ahead", selection: $preferences.eventLookAheadMinutes) {
                Text("2 hours").tag(120)
                Text("4 hours").tag(240)
                Text("8 hours").tag(480)
                Text("12 hours").tag(720)
                Text("24 hours").tag(1440)
            }
            .onChange(of: preferences.eventLookAheadMinutes) { source.refresh() }
        }
    }
}
