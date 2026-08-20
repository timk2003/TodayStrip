import Foundation
import ServiceManagement
import os

/// Thin wrapper over `SMAppService.mainApp` so Preferences doesn't have to deal with throwing
/// registration calls. Failures are logged rather than surfaced: the switch simply reflects the
/// real state on the next read.
enum LoginItem {
    private static let log = Logger(subsystem: Logger.subsystem, category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Could not \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
    }
}
