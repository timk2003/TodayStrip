import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            ModuleSettings(model: model)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            CalendarSettings(source: model.calendar, preferences: model.preferences)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            WeatherSettings(source: model.weather, preferences: model.preferences)
                .tabItem { Label("Weather", systemImage: "cloud.sun") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
        .frame(minHeight: 340)
    }
}

private struct GeneralSettings: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences

        Form {
            Section {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
            }

            Section("Strip") {
                Toggle("Show icon only", isOn: $preferences.iconOnly)
                    .help("Hides the text and rotates just the icons.")

                VStack(alignment: .leading) {
                    Slider(value: $preferences.rotationSpeed, in: 0.4...3) {
                        Text("Rotation speed")
                    } minimumValueLabel: {
                        Text("Fast").font(.caption)
                    } maximumValueLabel: {
                        Text("Slow").font(.caption)
                    }
                    Text("Each item stays on screen longer the more urgent it is; this scales all of them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(preferences.iconOnly)

                if !preferences.iconOnly {
                    LabeledContent("Maximum width") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(preferences.maxWidth) },
                                    set: { preferences.maxWidth = Int($0) }
                                ),
                                in: 10...60,
                                step: 1
                            )
                            Text("\(preferences.maxWidth)")
                                .monospacedDigit()
                                .frame(width: 26, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Timer") {
                Toggle("Play a sound when a timer ends", isOn: $preferences.playSoundOnTimerEnd)
            }

            Section {
                Toggle("Enable global shortcuts", isOn: $preferences.hotKeysEnabled)
                    .onChange(of: preferences.hotKeysEnabled) {
                        (NSApp.delegate as? AppDelegate)?.refreshHotKeys()
                    }
                Group {
                    LabeledContent("Open the panel") {
                        Text(HotKeyCenter.Combination.panel.displayName).monospaced()
                    }
                    LabeledContent("Start or pause the timer") {
                        Text(HotKeyCenter.Combination.timer.displayName).monospaced()
                    }
                }
                .foregroundStyle(preferences.hotKeysEnabled ? .primary : .tertiary)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("If another app already owns a combination, it silently stays with that app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TodayStrip answers `todaystrip://` URLs, so Shortcuts, Raycast or a shell script can drive it:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: """
                    todaystrip://timer/25
                    todaystrip://stopwatch
                    todaystrip://timer/stop
                    todaystrip://note?text=Ship%20the%20release
                    todaystrip://open
                    """)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                }
            } header: {
                Text("Automation")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModuleSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(StripItemKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { model.preferences.isEnabled(kind) },
                        set: { model.preferences.setEnabled(kind, $0) }
                    )) {
                        Label(kind.title, systemImage: kind.moduleSymbol)
                    }
                }
            } header: {
                Text("Show in the strip")
            } footer: {
                Text("A module that has nothing to report drops out of the rotation on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.preferences.isEnabled(.focus), !model.focus.isAvailable {
                Section {
                    Label {
                        Text("Focus state is unavailable on this system. macOS offers no API for it, so TodayStrip reads the files Control Center writes — and they are not where they were expected.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            // The real bundle icon rather than a stand-in symbol. `NSImage.applicationIconName`
            // resolves through the asset catalog, so it picks the sharpest representation.
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 72, height: 72)

            Text("TodayStrip")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Everything that matters about today, in one line of your menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Divider().padding(.horizontal, 60)

            VStack(spacing: 4) {
                Text("Weather data by Open-Meteo.com (CC BY 4.0)")
                Text("Open source · MIT licensed")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
