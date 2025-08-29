//
//  BarServerWSDaemonClient.swift
//  portlandApp
//
//  Created by Matthew Masters on 8/27/25.
//
import Foundation

class WebSocketDaemonClient {
    private var url: String
    private var ws: URLSessionWebSocketTask?
    private var onRequestData: () -> Void

    init(_ url: String, _ handler: @escaping () -> Void) {
        onRequestData = handler
        self.url = url
        connect(withURL: self.url)
    }

    func connect(withURL url: String) {
        guard let url = URL(string: "ws://localhost:3000/listen") else {
            print("Invalid url client not initialized")
            return
        }

        ws = URLSession(configuration: .default).webSocketTask(with: url)

        if let ws = ws {
            ws.resume()
            register()
        }
    }

    func register() {
        guard let ws = ws else {
            print("couldn't register, Websocket task not initialized")
            return
        }

        let data: [String: Any] = [
            "type": "daemon",
            "name": "NETWORK_DAEMON",
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: data) else {
            print("failed to create registration payload")
            return
        }

        guard let payload = String(data: json, encoding: .utf8) else {
            print("failed to create registration payload")
            return
        }

        ws.send(URLSessionWebSocketTask.Message.string(payload)) { [self] error in
            if let error = error {
                print("error sending registration message \(error)")
                return
            }
            onRequestData()
            receive()
        }
    }

    func send(data: [String: Any]) {
        guard let ws = ws else {
            print("couldn't send, Websocket task not initialized")
            return
        }

        guard let json = try? JSONSerialization.data(withJSONObject: data) else {
            print("couldn't serialize message")
            return
        }

        guard let payload = String(data: json, encoding: .utf8) else {
            print("couldn't serialize message")
            return
        }

        ws.send(URLSessionWebSocketTask.Message.string(payload)) { error in
            if let error = error {
                print("error sending message \(error)")
            }
        }
    }

    func receive() {
        guard let ws = ws else {
            print("couldn't receive, Websocket task not initialized")
            return
        }

        ws.receive { [self] result in
            switch result {
            case .success:
                onRequestData()
                receive()
                break
            case .failure:
                connect(withURL: url)
                break
            }
        }
    }

}
