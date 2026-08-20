import AppKit

/// Owns the `NSStatusItem` and renders one `StripItem` at a time.
///
/// Built on AppKit rather than SwiftUI's `MenuBarExtra` for one reason: the rotation needs to
/// cross-fade between items. A `CATransition` on the button's layer gives that for both the
/// symbol and the text in a single call, which `MenuBarExtra`'s label does not expose.
@MainActor
final class StatusItemController {
    /// Left click, or any click when no context menu is attached.
    var onPrimaryClick: (() -> Void)?
    /// Right click and control-click.
    var onSecondaryClick: (() -> Void)?
    /// Two-finger scroll over the item.
    var onScroll: ((Bool) -> Void)?

    private let statusItem: NSStatusItem
    private var displayed: StripItem?
    private var hasDrawn = false

    /// Longest title before truncation, in characters.
    var maxWidth = 28
    /// Drop the text and show only the symbol.
    var iconOnly = false

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.wantsLayer = true
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("TodayStrip")
        // Draw the placeholder up front: a status item with neither image nor title has zero
        // width, and an invisible item at launch looks like the app failed to start.
        button.image = Self.symbol(named: "square.dashed")

        installScrollMonitor()
    }

    isolated deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    /// Scroll events over a status item are not delivered through the responder chain, so they
    /// are picked up with a local monitor and filtered down to our own status window.
    private func installScrollMonitor() {
        var accumulated: CGFloat = 0
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let button = self.statusItem.button,
                  event.window === button.window
            else { return event }

            // Trackpads deliver many small deltas; accumulate so one flick is one step.
            accumulated += event.scrollingDeltaY
            guard abs(accumulated) >= 6 else { return nil }
            let scrollingDown = accumulated < 0
            accumulated = 0
            self.onScroll?(scrollingDown)
            return nil
        }
    }

    private var scrollMonitor: Any?

    /// Renders `item`, cross-fading from whatever was there before.
    ///
    /// Passing `nil` empties the strip down to a neutral placeholder rather than removing the
    /// status item, so its position in the menu bar is not lost and reshuffled on every gap.
    func display(_ item: StripItem?) {
        guard item != displayed || !hasDrawn else { return }
        let isFirstDraw = !hasDrawn
        hasDrawn = true
        displayed = item

        guard let button = statusItem.button else { return }

        // No fade on the very first draw; an item fading in at launch reads as a glitch.
        if !isFirstDraw {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.22
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(fade, forKey: "stripChange")
        }

        guard let item else {
            button.image = Self.symbol(named: "square.dashed")
            button.attributedTitle = NSAttributedString(string: "")
            button.setAccessibilityLabel("TodayStrip: nothing to show")
            return
        }

        button.image = Self.symbol(named: item.symbolName)
        apply(title: item, to: button)
        button.setAccessibilityLabel("\(item.kind.title): \(item.text)")
    }

    /// Normal items use the plain `title`, so AppKit picks the colour and keeps it in step with
    /// the menu bar — including the inversion while a menu is open. Only a genuine alarm takes
    /// that over with an attributed string, because red is worth the loss of that adaptation.
    private func apply(title item: StripItem, to button: NSStatusBarButton) {
        guard !iconOnly else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            return
        }

        let text = " " + Self.fit(
            full: item.text.trimmed,
            compact: item.compactText?.trimmed,
            limit: maxWidth
        )

        if item.tint == .critical {
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.menuBarFont(ofSize: 0),
                    .foregroundColor: NSColor.systemRed,
                ]
            )
        } else {
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.title = text
        }
    }

    /// Prefers the full text, falls back to the compact form, and only then truncates.
    nonisolated static func fit(full: String, compact: String?, limit: Int) -> String {
        if full.count <= limit { return full }
        if let compact, compact.count <= limit { return compact }
        let candidate = compact ?? full
        guard limit > 1 else { return String(candidate.prefix(max(0, limit))) }
        return String(candidate.prefix(limit - 1)).trimmed + "…"
    }

    private nonisolated static func symbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        // Focus modes report their own symbol names, some of which are not public SF Symbols.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: nil)
        image?.isTemplate = true
        return image?.withSymbolConfiguration(configuration)
    }

    // MARK: - Interaction

    /// Shows `menu` for one click, then detaches it so left clicks keep reaching `onPrimaryClick`.
    func popUp(menu: NSMenu) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    var button: NSStatusBarButton? { statusItem.button }

    @objc private func handleClick() {
        let isSecondary = NSApp.currentEvent.map { event in
            event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        } ?? false

        if isSecondary {
            onSecondaryClick?()
        } else {
            onPrimaryClick?()
        }
    }
}

