import SwiftUI
import AppKit
import ServiceManagement

final class Prefs: ObservableObject {
    static let shared = Prefs()

    /// Uninterrupted work before the auto-break fires. Default 6 hours.
    @Published var thresholdMinutes: Int {
        didSet { UserDefaults.standard.set(thresholdMinutes, forKey: "thresholdMinutes") }
    }

    /// Auto-break length. Default 30 minutes.
    @Published var breakMinutes: Int {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: "breakMinutes") }
    }

    /// Master switch for the whole auto-break feature.
    @Published var autoFixGapsOverlaps: Bool {
        didSet { UserDefaults.standard.set(autoFixGapsOverlaps, forKey: "autoFixGapsOverlaps") }
    }

    @Published var autoBreakEnabled: Bool {
        didSet { UserDefaults.standard.set(autoBreakEnabled, forKey: "autoBreakEnabled") }
    }

    /// Autofill the stored password + TOTP into the SSO sign-in form.
    @Published var autofillEnabled: Bool {
        didSet { UserDefaults.standard.set(autofillEnabled, forKey: "autofillEnabled") }
    }

    /// Silently run the headless sign-in the moment the session expires.
    @Published var autoReloginOnExpiry: Bool {
        didSet { UserDefaults.standard.set(autoReloginOnExpiry, forKey: "autoReloginOnExpiry") }
    }

    @Published var notifyAutoBreak: Bool {
        didSet { UserDefaults.standard.set(notifyAutoBreak, forKey: "notifyAutoBreak") }
    }

    @Published var notifyFailures: Bool {
        didSet { UserDefaults.standard.set(notifyFailures, forKey: "notifyFailures") }
    }

    /// Notify once when today's worked time reaches the day's target.
    @Published var notifyTargetReached: Bool {
        didSet { UserDefaults.standard.set(notifyTargetReached, forKey: "notifyTargetReached") }
    }

    /// Notify when the timesheet lock/submission deadline is approaching.
    @Published var notifyDeadline: Bool {
        didSet { UserDefaults.standard.set(notifyDeadline, forKey: "notifyDeadline") }
    }

    /// What to show next to the menu-bar icon.
    enum MenuBarDisplay: String, CaseIterable, Identifiable {
        case none, workedTime, untilBreak, status
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Icon only"
            case .workedTime: return "Worked time today"
            case .untilBreak: return "Time until auto-break"
            case .status: return "Status (Working / Break)"
            }
        }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet {
            UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay")
            NotificationCenter.default.post(name: .updateStatusItem, object: nil)
        }
    }

    /// Tint the menu-bar icon by clock state (green working / orange break).
    @Published var colorMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(colorMenuBarIcon, forKey: "colorMenuBarIcon")
            NotificationCenter.default.post(name: .updateStatusItem, object: nil)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// When on this Wi-Fi network, auto-tag the open work entry with
    /// `wifiReasonName`. Empty SSID / disabled = off.
    @Published var wifiAutoReasonEnabled: Bool {
        didSet { UserDefaults.standard.set(wifiAutoReasonEnabled, forKey: "wifiAutoReasonEnabled") }
    }

    /// Fallback reason applied to the open work entry when no Wi-Fi rule
    /// matches. Empty = no default.
    @Published var defaultReasonName: String {
        didSet { UserDefaults.standard.set(defaultReasonName, forKey: "defaultReasonName") }
    }

    /// One rule per network: SSID → reason. Persisted as JSON.
    @Published var wifiRules: [WiFiRule] {
        didSet {
            if let data = try? JSONEncoder().encode(wifiRules) {
                UserDefaults.standard.set(data, forKey: "wifiRules")
            }
        }
    }

    var threshold: TimeInterval { TimeInterval(thresholdMinutes * 60) }
    var breakLength: TimeInterval { TimeInterval(breakMinutes * 60) }

    private init() {
        let d = UserDefaults.standard
        self.thresholdMinutes = d.object(forKey: "thresholdMinutes") as? Int ?? 360
        self.breakMinutes = d.object(forKey: "breakMinutes") as? Int ?? 30
        self.autoFixGapsOverlaps = d.object(forKey: "autoFixGapsOverlaps") as? Bool ?? true
        self.autoBreakEnabled = d.object(forKey: "autoBreakEnabled") as? Bool ?? true
        self.autofillEnabled = d.object(forKey: "autofillEnabled") as? Bool ?? false
        self.autoReloginOnExpiry = d.object(forKey: "autoReloginOnExpiry") as? Bool ?? false
        self.notifyAutoBreak = d.object(forKey: "notifyAutoBreak") as? Bool ?? true
        self.notifyFailures = d.object(forKey: "notifyFailures") as? Bool ?? true
        self.notifyTargetReached = d.object(forKey: "notifyTargetReached") as? Bool ?? true
        self.notifyDeadline = d.object(forKey: "notifyDeadline") as? Bool ?? true
        // Migrate the old boolean into the new display enum.
        if let raw = d.string(forKey: "menuBarDisplay"), let m = MenuBarDisplay(rawValue: raw) {
            self.menuBarDisplay = m
        } else {
            self.menuBarDisplay = (d.object(forKey: "showTimeInMenuBar") as? Bool ?? false)
                ? .workedTime : .none
        }
        self.colorMenuBarIcon = d.object(forKey: "colorMenuBarIcon") as? Bool ?? false
        self.wifiAutoReasonEnabled = d.object(forKey: "wifiAutoReasonEnabled") as? Bool ?? false
        self.defaultReasonName = d.string(forKey: "defaultReasonName") ?? ""
        if let data = d.data(forKey: "wifiRules"),
           let rules = try? JSONDecoder().decode([WiFiRule].self, from: data) {
            self.wifiRules = rules
        } else if let ssid = d.string(forKey: "wifiSSID"), !ssid.isEmpty {
            // Migrate the previous single-rule setting.
            self.wifiRules = [WiFiRule(ssid: ssid, reasonName: d.string(forKey: "wifiReasonName") ?? "In Office")]
        } else {
            self.wifiRules = []
        }
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Failed to toggle launch-at-login: \(error)")
        }
    }
}

extension Notification.Name {
    static let updateStatusItem = Notification.Name("updateStatusItem")
    static let closePopover     = Notification.Name("closePopover")
}
