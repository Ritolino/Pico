import Foundation
import ServiceManagement

enum LoginItemManager {
    static var status: SMAppService.Status {
        return SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        return status == .enabled
    }

    static func statusDescription(_ s: SMAppService.Status) -> String {
        switch s {
        case .enabled:
            return "Active (.enabled)"
        case .requiresApproval:
            return "Requires Approval (.requiresApproval)"
        case .notRegistered:
            return "Not Registered (.notRegistered)"
        case .notFound:
            return "Bundle Not Found (.notFound)"
        @unknown default:
            return "Unknown"
        }
    }

    /// Toggles Pico login item registration.
    /// Returns true if the item is enabled afterwards.
    @discardableResult
    static func toggle() -> Bool {
        if isEnabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                NSLog("[Pico] Error unregistering SMAppService: %@", error.localizedDescription)
            }
        } else {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("[Pico] Error registering SMAppService: %@", error.localizedDescription)
            }
        }
        return isEnabled
    }

    /// Automatically registers on first launch when running inside /Applications
    static func registerIfFirstLaunchInApplications() {
        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasPrefix("/Applications/") else {
            return
        }

        let defaults = UserDefaults.standard
        let key = "Pico_DidAttemptInitialLoginItemRegistration"
        guard !defaults.bool(forKey: key) else {
            return
        }
        defaults.set(true, forKey: key)

        if status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("[Pico] Initial registration in /Applications: %@", error.localizedDescription)
            }
        }
    }
}
