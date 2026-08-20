import AppKit
import Carbon.HIToolbox
import os

/// Global keyboard shortcuts, via Carbon's `RegisterEventHotKey`.
///
/// Carbon rather than a `CGEventTap` on purpose: event taps need Accessibility permission, which
/// is a heavy thing to ask of someone for a menu bar utility. `RegisterEventHotKey` needs none,
/// and has outlived every framework that was supposed to replace it.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// A combination, in Carbon's terms.
    nonisolated struct Combination: Equatable, Sendable {
        var keyCode: UInt32
        var modifiers: UInt32

        /// ⌥⌘T — opens the panel.
        static let panel = Combination(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(optionKey | cmdKey)
        )
        /// ⌥⌘R — starts or stops the timer.
        static let timer = Combination(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(optionKey | cmdKey)
        )

        var displayName: String {
            var parts = ""
            if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
            return parts + (Self.keyNames[keyCode] ?? "?")
        }

        private static let keyNames: [UInt32: String] = [
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_R): "R",
        ]
    }

    private static let log = Logger(subsystem: Logger.subsystem, category: "HotKeys")
    private static let signature = OSType(0x54_44_53_54) // 'TDST'

    private var actions: [UInt32: () -> Void] = [:]
    private var registered: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Registers `combination`, replacing nothing — call `unregisterAll()` first to rebind.
    ///
    /// A combination another app already owns simply fails to register; that is reported in the
    /// log and otherwise ignored, because there is nothing useful to ask the user at launch.
    func register(_ combination: Combination, action: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            Self.log.notice("Could not register \(combination.displayName, privacy: .public); another app may own it.")
            return
        }
        actions[nextID] = action
        registered.append(ref)
        nextID += 1
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &type, nil, &handler)
    }
}

/// Carbon calls this on the main thread, but it arrives with no isolation the compiler can see,
/// so the identifier is copied out and the work is hopped explicitly.
private nonisolated(unsafe) let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }

    let identifier = id.id
    Task { @MainActor in HotKeyCenter.shared.fire(identifier) }
    return noErr
}
