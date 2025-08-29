import CoreLocation
import CoreWLAN
import Foundation

enum WifiEvent {
    case SSID_CHANGE
    case WIFI_DISCONNECT
    case WIFI_CONNECT
}


class WifiObserverPermissionManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let wifiObserver = WiFiObserver()

    var authorizationStatus: CLAuthorizationStatus {
        return manager.authorizationStatus
    }

    override init() {
        super.init()

        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("Auth status changed starting observer")
            wifiObserver.start()
            return
        case .authorized:
            manager.requestAlwaysAuthorization()
            return
        case .denied:
            print("user denied")
            return
        case .notDetermined:
            print("not determined")
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startObserverWithPermissions() {
        print("\(manager.authorizationStatus)")
        if manager.authorizationStatus == .authorizedAlways {
            print("Already authorized starting observer")
            wifiObserver.start()
            return
        }
        print("requesting authorization")
        manager.requestWhenInUseAuthorization()
        return
    }
}

let isScreenUnlocked = NSNotification.Name("com.apple.screenIsUnlocked")

class WiFiObserver: CWEventDelegate {
    private let client = CWWiFiClient.shared()
    private let center = DistributedNotificationCenter.default()
    private var unlockObserver: NSObjectProtocol?
    private var wsDaemonClient: WebSocketDaemonClient?

    init() {
        client.delegate = self
    }

    func start() {
        try! client.startMonitoringEvent(with: .linkDidChange)
        try! client.startMonitoringEvent(with: .modeDidChange)
        try! client.startMonitoringEvent(with: .ssidDidChange)

        unlockObserver = center.addObserver(forName: isScreenUnlocked, object: nil, queue: .main) {
            [self] _ in
            if let interface = client.interface() {
                postMode(withInterface: interface)
                postSSID(withInterface: interface)
            }
        }
        DispatchQueue.main.async(execute: waitForHeartbeat)
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
            
            wsDaemonClient = WebSocketDaemonClient("http://localhost:3000/listen") { [self] in
                if let interface = client.interface() {
                    postMode(withInterface: interface)
                    postSSID(withInterface: interface)
                }
            }
        }

        task.resume()
    }

    func sendInfo(event: WifiEvent, data: [String: Any]) {
        guard let ws = wsDaemonClient else {
            return
        }
        
        let payload: [String: Any] = [
            "type": "NETWORK_UPDATE_\(event)",
            "data": data,
        ]
        
        ws.send(data: payload)
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
            sendInfo(event: .WIFI_DISCONNECT, data: ["connected": false])
        }
        if mode == .station {
            sendInfo(event: .WIFI_CONNECT, data: ["connected": true])
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
            sendInfo(event: .SSID_CHANGE, data: ["ssid": interface.ssid() ?? "NO_PERMISSIONS"])
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
        if let obs = unlockObserver {
            center.removeObserver(obs)
        }
    }
}

WifiObserverPermissionManager().startObserverWithPermissions()

RunLoop.main.run()
