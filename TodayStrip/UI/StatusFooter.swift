import SwiftUI

/// The ambient readings: Focus, battery, weather. Nothing here is interactive, so it sits in a
/// quiet footer rather than competing with the sections above.
struct StatusFooter: View {
    let model: AppModel

    var body: some View {
        let chips = chips
        if !chips.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    ForEach(chips) { chip in
                        Label {
                            Text(chip.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: chip.symbol)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(chip.isAlert ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(.bar)
        }
    }

    private struct Chip: Identifiable {
        let id: StripItemKind
        let symbol: String
        let text: String
        let isAlert: Bool
    }

    private var chips: [Chip] {
        var chips: [Chip] = []

        if model.preferences.isEnabled(.focus), let focus = model.focus.focus {
            chips.append(Chip(id: .focus, symbol: focus.symbolName, text: focus.name, isAlert: false))
        }
        if model.preferences.isEnabled(.battery), let battery = model.battery.state {
            chips.append(
                Chip(
                    id: .battery,
                    symbol: BatterySource.symbol(for: battery),
                    text: "\(battery.percentage)%",
                    isAlert: battery.percentage < 20 && !battery.isPluggedIn
                )
            )
        }
        if model.preferences.isEnabled(.weather), let weather = model.weather.conditions {
            chips.append(
                Chip(
                    id: .weather,
                    symbol: WeatherCode.symbol(weather.code, isDay: weather.isDay),
                    text: WeatherSource.formatted(weather.temperature, unit: weather.unitSymbol),
                    isAlert: false
                )
            )
        }
        return chips
    }
}
