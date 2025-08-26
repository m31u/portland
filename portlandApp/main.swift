import AppKit
import CoreLocation
import CoreWLAN
import Foundation

enum WifiEvent {
    case SSID_CHANGE
    case WIFI_DISCONNECT
    case WIFI_CONNECT
}

class LSRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    override init() {
        super.init()

        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            print("requesting")
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }
}

let isScreenUnlocked = NSNotification.Name("com.apple.screenIsUnlocked")

class WiFiObserver: CWEventDelegate {
    private let client = CWWiFiClient.shared()
    private let center = DistributedNotificationCenter.default()
    init() {
        client.delegate = self
        try! client.startMonitoringEvent(with: .linkDidChange)
        try! client.startMonitoringEvent(with: .modeDidChange)
        try! client.startMonitoringEvent(with: .ssidDidChange)

        let _ = center.addObserver(forName: isScreenUnlocked, object: nil, queue: .main) {
            [self] _ in
            if let interface = client.interface() {
                postMode(withInterface: interface)
                postSSID(withInterface: interface)
            }
        }

        waitForHeartbeat()
    }

    func waitForHeartbeat() {
        guard let url = URL(string: "http://localhost:3000/heartbeat") else {
            return
        }
        let req = URLRequest(url: url)

        let task = URLSession.shared.dataTask(with: req) { [self] _, _, err in
            if err != nil {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 5.0, execute: waitForHeartbeat)
                return
            }

            if let interface = client.interface() {
                postSSID(withInterface: interface)
            }
        }

        task.resume()
    }

    func postInfo(event: WifiEvent, data: [String: Any]) {
        let payload: [String: Any] = [
            "type": "NETWORK_UPDATE_\(event)",
            "data": data,
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: payload) else {
            print("Couldn't serialize payload")
            return
        }

        guard let url = URL(string: "http://localhost:3000/update-network") else {
            return
        }

        var req = URLRequest(url: url)

        req.httpMethod = "POST"
        req.httpBody = json
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: req) { _, _, err in
            if let err = err {
                print("POST Error: \(err)")
            }
        }

        task.resume()
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        postSSID(withName: interfaceName)
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        postMode(withName: interfaceName)
    }

    func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        postMode(withName: interfaceName)
    }

    func postMode(withInterface interface: CWInterface) {
        let mode = interface.interfaceMode()

        if mode == .none {
            postInfo(event: .WIFI_DISCONNECT, data: ["connected": false])
        }
        if mode == .station {
            postInfo(event: .WIFI_CONNECT, data: ["connected": true])
        }
    }

    func postMode(withName interfaceName: String) {
        guard let interface = client.interface(withName: interfaceName) else {
            print("couldn't get specified interface \(interfaceName)")
            return
        }

        postMode(withInterface: interface)
    }

    func postSSID(withInterface interface: CWInterface) {
        if interface.interfaceMode() == .station {
            postInfo(event: .SSID_CHANGE, data: ["ssid": interface.ssid() ?? "NO_PERMISSIONS"])
        }
    }

    func postSSID(withName interfaceName: String) {
        guard let interface = client.interface(withName: interfaceName) else {
            print("couldn't get specified interface \(interfaceName)")
            return
        }

        postSSID(withInterface: interface)
    }

    deinit {
        try! client.stopMonitoringAllEvents()
    }
}

let request = LSRequester()
let observer = WiFiObserver()

RunLoop.main.run()
