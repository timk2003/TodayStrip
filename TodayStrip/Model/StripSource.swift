import Foundation

/// A producer of at most one `StripItem`.
///
/// Sources know nothing about rotation, the menu bar, or each other. They observe some part of
/// the system, and whenever their answer to "what should the strip say about me right now?"
/// changes, they publish a new item (or `nil` to drop out of the rotation) and call `onChange`.
@MainActor
protocol StripSource: AnyObject {
    var kind: StripItemKind { get }

    /// The current candidate, or `nil` if this source has nothing worth showing.
    var currentItem: StripItem? { get }

    /// Called after `currentItem` changes to a genuinely different value.
    var onChange: (() -> Void)? { get set }

    /// Begin observing. Safe to call twice.
    func start()

    /// Stop observing and release any system resources.
    func stop()

    /// Re-read the underlying state now, ignoring any polling schedule.
    func refresh()
}

extension StripSource {
    func refresh() {}
}
