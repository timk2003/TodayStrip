import Foundation
import Observation
import os

/// The currently active Focus, read from the files the system writes under
/// `~/Library/DoNotDisturb/DB/`.
///
/// macOS exposes no public API for this, so this source reads the same JSON that Control Center
/// writes: `Assertions.json` says which mode is asserted, `ModeConfigurations.json` maps that
/// identifier to a name and SF Symbol. Both are watched through a directory-level file system
/// event source, because the system replaces these files atomically rather than editing them —
/// a watcher on the file itself would go deaf after the first change.
///
/// This is unsupported territory by definition: if Apple moves or reshapes the files, every
/// read simply yields `nil` and the module drops out of the strip.
@Observable
final class FocusSource: StripSource {
    nonisolated struct Focus: Equatable, Sendable {
        var name: String
        var symbolName: String
        var identifier: String
    }

    let kind = StripItemKind.focus

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var currentItem: StripItem?
    private(set) var focus: Focus?

    /// `false` when the directory is missing entirely, which Settings surfaces to the user.
    private(set) var isAvailable = false

    private static let log = Logger(subsystem: Logger.subsystem, category: "FocusSource")

    private let directory: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: CInt = -1
    private var debounce: Task<Void, Never>?

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.homeDirectory.appending(path: "Library/DoNotDisturb/DB")
    }

    // MARK: - StripSource

    func start() {
        isAvailable = FileManager.default.fileExists(atPath: directory.path(percentEncoded: false))
        refresh()
        startWatching()
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    func refresh() {
        focus = Self.readActiveFocus(in: directory)
        publish()
    }

    // MARK: - Watching

    private func startWatching() {
        guard watcher == nil, isAvailable else { return }

        let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            Self.log.error("Could not open the Focus directory for watching.")
            return
        }
        watchedDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Switching a Focus rewrites several files in a burst; one refresh at the end is enough.
    private func scheduleRefresh() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Parsing

    private nonisolated static func readActiveFocus(in directory: URL) -> Focus? {
        guard let identifier = activeModeIdentifier(in: directory) else { return nil }
        let configuration = modeConfiguration(for: identifier, in: directory)
        return Focus(
            name: configuration?.name ?? "Focus",
            symbolName: configuration?.symbolName ?? "moon.fill",
            identifier: identifier
        )
    }

    private nonisolated static func activeModeIdentifier(in directory: URL) -> String? {
        guard let root = json(at: directory.appending(path: "Assertions.json")),
              let data = root["data"] as? [[String: Any]]
        else { return nil }

        for entry in data {
            guard let records = entry["storeAssertionRecords"] as? [[String: Any]] else { continue }
            for record in records {
                guard let details = record["assertionDetails"] as? [String: Any],
                      let identifier = details["assertionDetailsModeIdentifier"] as? String
                else { continue }
                return identifier
            }
        }
        return nil
    }

    private nonisolated static func modeConfiguration(
        for identifier: String,
        in directory: URL
    ) -> (name: String, symbolName: String)? {
        guard let root = json(at: directory.appending(path: "ModeConfigurations.json")),
              let data = root["data"] as? [[String: Any]]
        else { return nil }

        for entry in data {
            guard let configurations = entry["modeConfigurations"] as? [String: Any],
                  let configuration = configurations[identifier] as? [String: Any],
                  let mode = configuration["mode"] as? [String: Any]
            else { continue }
            let name = mode["name"] as? String ?? "Focus"
            let symbol = mode["symbolImageName"] as? String ?? "moon.fill"
            return (name, symbol)
        }
        return nil
    }

    private nonisolated static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Publishing

    private func publish() {
        let item = focus.map { focus in
            StripItem(
                kind: .focus,
                priority: .normal,
                symbolName: focus.symbolName,
                text: focus.name,
                compactText: focus.name
            )
        }
        guard item != currentItem else { return }
        currentItem = item
        onChange?()
    }
}
