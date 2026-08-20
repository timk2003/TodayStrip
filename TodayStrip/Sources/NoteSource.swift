import Foundation
import Observation

/// Today's one-line note.
///
/// Owns the `NoteStore` so that reads and writes take a single path: the popover edits through
/// this source, which persists and republishes in one step. A midnight timer rolls the note over
/// so the field is empty when the user's day is.
@Observable
final class NoteSource: StripSource {
    let kind = StripItemKind.note

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?

    @ObservationIgnored private let store: NoteStore
    private var rollover: Timer?

    /// Today's note. Setting it persists (debounced) and updates the strip.
    var text: String {
        get {
            access(keyPath: \.text)
            return store.note()
        }
        set {
            withMutation(keyPath: \.text) {
                store.setNote(newValue)
                publish()
            }
        }
    }

    init(store: NoteStore = NoteStore()) {
        self.store = store
    }

    func start() {
        publish()
        scheduleRollover()
    }

    func stop() {
        rollover?.invalidate()
        rollover = nil
        store.flush()
    }

    func refresh() {
        publish()
    }

    /// Previous days that have a note, newest first.
    func recentDays(limit: Int = 7) -> [(day: Date, text: String)] {
        store.recent(limit: limit)
    }

    func flush() {
        store.flush()
    }

    // MARK: - Day rollover

    private func scheduleRollover() {
        rollover?.invalidate()
        let calendar = Calendar.current
        guard let midnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) else { return }

        let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.publish()
                self.scheduleRollover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rollover = timer
    }

    // MARK: - Publishing

    private func publish() {
        let note = store.note().trimmed
        let item: StripItem? = note.isEmpty
            ? nil
            : StripItem(
                kind: .note,
                priority: .ambient,
                symbolName: "square.and.pencil",
                text: note,
                compactText: String(note.prefix(24))
            )

        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }
}
