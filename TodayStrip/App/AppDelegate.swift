import AppKit
import SwiftUI
import UserNotifications
import os

/// Assembles the menu bar item, the popover and the model, and keeps them in step.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: Logger.subsystem, category: "AppDelegate")

    private let model = AppModel.shared
    private var statusItem: StatusItemController?
    private var popover: PopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no app switcher entry: the menu bar is the whole app.
        NSApp.setActivationPolicy(.accessory)
        requestNotificationPermission()

        let statusItem = StatusItemController()
        let popover = PopoverController(size: CGSize(width: 340, height: 430)) {
            PopoverView()
                .environment(model)
        }

        statusItem.onPrimaryClick = { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            switch AppModel.clickAction(displayed: model.displayed, nextEvent: model.calendar.nextEvent) {
            case .join(let url):
                NSWorkspace.shared.open(url)
            case .openPanel:
                popover.toggle(relativeTo: button)
            }
        }
        statusItem.onSecondaryClick = { [weak self] in
            self?.showContextMenu()
        }
        statusItem.onScroll = { [weak self] _ in
            self?.model.rotator.advance()
        }

        // Reading the strip is easier when it holds still, so rotation stops while the panel is up.
        popover.onOpen = { [weak self] in self?.model.pauseRotation() }
        popover.onClose = { [weak self] in self?.model.resumeRotation() }

        self.statusItem = statusItem
        self.popover = popover

        model.onDisplayChange = { [weak self] item in
            guard let self else { return }
            statusItem.maxWidth = model.preferences.maxWidth
            statusItem.iconOnly = model.preferences.iconOnly
            statusItem.display(item)
        }

        installHotKeysIfEnabled()

        model.start()
        statusItem.display(model.displayed)
    }

    // MARK: - Commands

    /// Handles `todaystrip://` URLs. Same entry point as the global hotkeys.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand(url: url) else {
                Self.log.notice("Ignoring unrecognised URL: \(url.absoluteString, privacy: .public)")
                continue
            }
            perform(command)
        }
    }

    private func perform(_ command: URLCommand) {
        switch command {
        case .startCountdown(let minutes):
            model.timer.startCountdown(minutes: minutes)
        case .startStopwatch:
            model.timer.startStopwatch()
        case .stopTimer:
            model.timer.reset()
        case .setNote(let text):
            model.note.text = text
        case .openPanel:
            guard let button = statusItem?.button else { return }
            popover?.toggle(relativeTo: button)
        }
    }

    private func installHotKeysIfEnabled() {
        guard model.preferences.hotKeysEnabled else { return }

        HotKeyCenter.shared.register(.panel) { [weak self] in
            self?.perform(.openPanel)
        }
        HotKeyCenter.shared.register(.timer) { [weak self] in
            guard let self else { return }
            // Idle means "start something"; anything else means "pause or resume what is running".
            if model.timer.mode == .idle {
                perform(.startCountdown(minutes: model.preferences.timerPresets.first ?? 25))
            } else {
                model.timer.toggle()
            }
        }
    }

    /// Re-reads the preference and rebinds. Called when the switch in Settings changes.
    func refreshHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        installHotKeysIfEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.note.flush()
        model.stop()
    }

    // MARK: - Context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit TodayStrip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.popUp(menu: menu)
    }

    @objc private func refresh() {
        model.refreshAll()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Renamed in macOS 14; the older selector keeps this working if it is ever built back.
        let selectors = [Selector(("showSettingsWindow:")), Selector(("showPreferencesWindow:"))]
        for selector in selectors where NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
