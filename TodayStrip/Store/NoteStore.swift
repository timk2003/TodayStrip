import Foundation
import os

/// One short note per calendar day, stored as plain JSON in Application Support.
///
/// JSON rather than a database on purpose: the file is small, human-readable, trivially
/// backed up, and a user can recover their notes with a text editor if the app ever breaks.
@MainActor
final class NoteStore {
    private static let log = Logger(subsystem: Logger.subsystem, category: "NoteStore")

    private let fileURL: URL
    private var notes: [String: String]
    private var saveTask: Task<Void, Never>?

    /// Days are keyed `yyyy-MM-dd` in the user's calendar, so a note belongs to the day the
    /// user perceived, not to a UTC instant.
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.notes = Self.load(from: self.fileURL)
    }

    // MARK: - Reading

    func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    func note(for date: Date = Date()) -> String {
        notes[key(for: date)] ?? ""
    }

    /// The most recent days that actually have a note, newest first.
    func recent(limit: Int, before date: Date = Date()) -> [(day: Date, text: String)] {
        let today = key(for: date)
        return notes
            .filter { $0.key < today && !$0.value.trimmed.isEmpty }
            .sorted { $0.key > $1.key }
            .prefix(limit)
            .compactMap { entry in
                dayFormatter.date(from: entry.key).map { (day: $0, text: entry.value) }
            }
    }

    // MARK: - Writing

    func setNote(_ text: String, for date: Date = Date()) {
        let key = key(for: date)
        let trimmed = text.trimmed
        if trimmed.isEmpty {
            guard notes[key] != nil else { return }
            notes.removeValue(forKey: key)
        } else {
            guard notes[key] != trimmed else { return }
            notes[key] = trimmed
        }
        scheduleSave()
    }

    /// Coalesces the writes that a text field produces on every keystroke into one write per
    /// second, so typing a note does not hammer the disk.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = notes
        let url = fileURL
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write(snapshot, to: url)
        }
    }

    /// Writes immediately, for app termination where the debounce would never fire.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write(notes, to: fileURL)
    }

    private func write(_ notes: [String: String], to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(notes).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Could not save notes: \(error.localizedDescription)")
        }
    }

    // MARK: - Loading

    private static func load(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            log.error("Notes file is unreadable, starting empty: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library/Application Support")
        return base.appending(path: "TodayStrip/notes.json")
    }
}

nonisolated extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated extension Logger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "de.timkrisch.TodayStrip"
}
