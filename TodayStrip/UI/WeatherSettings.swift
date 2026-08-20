import SwiftUI

struct WeatherSettings: View {
    @Bindable var source: WeatherSource
    @Bindable var preferences: Preferences

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Location") {
                Picker("Use", selection: $preferences.useCurrentLocation) {
                    Text("Current location").tag(true)
                    Text("A specific place").tag(false)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: preferences.useCurrentLocation) { source.refresh() }

                if preferences.useCurrentLocation {
                    Text("Weather is fetched for your approximate location, rounded to a few hundred metres before it leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    placePicker
                }
            }

            Section("Units") {
                Picker("Temperature", selection: $preferences.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .onChange(of: preferences.temperatureUnit) { source.refresh() }
            }

            Section("Status") {
                if let conditions = source.conditions {
                    LabeledContent("Now") {
                        Label(
                            "\(WeatherSource.formatted(conditions.temperature, unit: conditions.unitSymbol)) · \(WeatherCode.description(conditions.code))",
                            systemImage: WeatherCode.symbol(conditions.code, isDay: conditions.isDay)
                        )
                    }
                    LabeledContent("Updated") {
                        Text(conditions.fetched, style: .relative) + Text(" ago")
                    }
                }
                if let error = source.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Button("Refresh now") { source.refresh() }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var placePicker: some View {
        if let place = preferences.manualPlace {
            LabeledContent("Selected") {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(place.name)
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }

        HStack {
            TextField("Search for a city", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
                .onChange(of: query) { scheduleSearch() }
            if isSearching {
                ProgressView().controlSize(.small)
            }
        }

        if let searchError {
            Text(searchError).font(.caption).foregroundStyle(.secondary)
        }

        ForEach(results) { place in
            Button {
                preferences.manualPlace = place
                results = []
                query = ""
                source.refresh()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.name)
                        if !place.subtitle.isEmpty {
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if preferences.manualPlace == place {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Debounced so typing a city name is one request, not one per keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        guard query.trimmed.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            search()
        }
    }

    private func search() {
        let term = query
        guard term.trimmed.count >= 2 else { return }
        isSearching = true
        searchError = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await OpenMeteo.search(place: term)
                if results.isEmpty { searchError = "No place found for “\(term.trimmed)”." }
            } catch {
                searchError = error.localizedDescription
            }
        }
    }
}
