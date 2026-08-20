import AppKit
import SwiftUI

/// Hosts the SwiftUI detail panel in an `NSPopover` anchored to the status item.
///
/// Open and close are reported through notifications rather than `NSPopoverDelegate` so this
/// type has no isolation-sensitive protocol conformance to reason about.
@MainActor
final class PopoverController {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    private let popover = NSPopover()
    private var observers: [NSObjectProtocol] = []

    init(size: CGSize, @ViewBuilder content: () -> some View) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = size
        popover.contentViewController = NSHostingController(rootView: content())

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSPopover.didShowNotification, object: popover, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen?() }
            }
        )
        observers.append(
            center.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose?() }
            }
        )
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo button: NSStatusBarButton) {
        isShown ? close() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        // An accessory app is never frontmost on its own, and an inactive popover would swallow
        // the first click and refuse keyboard focus for the note field.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
