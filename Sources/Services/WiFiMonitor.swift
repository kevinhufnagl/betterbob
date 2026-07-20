import Foundation
import CoreWLAN
import CoreLocation

/// Reads the currently-joined Wi-Fi network name (SSID). On modern macOS the
/// SSID is only revealed to apps that hold Location authorization, so this
/// also owns the one-time location prompt. It never uses actual location —
/// just the entitlement that unlocks the SSID.
@MainActor
final class WiFiMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WiFiMonitor()

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// Ask for the Location permission that makes SSID readable. Safe to call
    /// repeatedly; no-op once decided.
    func requestAccess() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    var hasAccess: Bool {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: return true
        default: return false
        }
    }

    /// The SSID of the current Wi-Fi network, or nil if not on Wi-Fi / not
    /// permitted.
    func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.objectWillChange.send() }
    }
}
