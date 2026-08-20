import SwiftUI

/// One line about today, plus the last few days for context.
struct NoteSection: View {
    @Bindable var source: NoteSource
    @State private var showHistory = false

    private var history: [(day: Date, text: String)] {
        source.recentDays(limit: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(symbol: "square.and.pencil", title: "Today")
                Spacer()
                if !history.isEmpty {
                    Button(showHistory ? "Hide" : "History") {
                        withAnimation(.easeInOut(duration: 0.15)) { showHistory.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What matters today?", text: $source.text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(1...3)

                    if showHistory {
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(history, id: \.day) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(entry.day, format: .dateTime.day().month(.abbreviated))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(entry.text)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
