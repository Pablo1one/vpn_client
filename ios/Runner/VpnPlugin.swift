import Flutter
import NetworkExtension

// Bundle ID of the PacketTunnel extension target.
// Must match CFBundleIdentifier in ios/PacketTunnel/Info.plist.
private let tunnelBundleId = "com.example.vpn-client.tunnel"

class VpnPlugin: NSObject, FlutterStreamHandler {

    private static let methodCh = "com.example.vpn_client/vpn"
    private static let eventCh  = "com.example.vpn_client/vpn_events"

    private var eventSink: FlutterEventSink?
    private var manager: NETunnelProviderManager?

    static func register(with messenger: FlutterBinaryMessenger) {
        let plugin = VpnPlugin()

        FlutterMethodChannel(name: methodCh, binaryMessenger: messenger)
            .setMethodCallHandler(plugin.handle(_:result:))

        FlutterEventChannel(name: eventCh, binaryMessenger: messenger)
            .setStreamHandler(plugin)
    }

    // MARK: – Method calls

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let config = args["config"] as? String else {
                result(FlutterError(code: "INVALID_ARG", message: "config required", details: nil))
                return
            }
            connect(config: config, completion: result)
        case "disconnect":
            disconnect(completion: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: – VPN management

    private func connect(config: String, completion: @escaping FlutterResult) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let err = error {
                return completion(FlutterError(code: "LOAD_ERR", message: err.localizedDescription, details: nil))
            }
            let mgr = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == tunnelBundleId
            }) ?? NETunnelProviderManager()

            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = tunnelBundleId
            proto.providerConfiguration   = ["config": config]
            proto.serverAddress            = "VPN"

            mgr.protocolConfiguration  = proto
            mgr.localizedDescription   = "VPN Client"
            mgr.isEnabled              = true

            mgr.saveToPreferences { error in
                if let err = error {
                    return completion(FlutterError(code: "SAVE_ERR", message: err.localizedDescription, details: nil))
                }
                // Reload after save to get a valid session object.
                mgr.loadFromPreferences { _ in
                    do {
                        try (mgr.connection as? NETunnelProviderSession)?.startTunnel()
                        self?.manager = mgr
                        completion(nil)
                    } catch {
                        completion(FlutterError(code: "START_ERR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func disconnect(completion: @escaping FlutterResult) {
        (manager?.connection as? NETunnelProviderSession)?.stopTunnel()
        completion(nil)
    }

    // MARK: – EventChannel (VPN status stream)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusChanged(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        eventSink = nil
        return nil
    }

    @objc private func statusChanged(_ note: Notification) {
        guard let conn = note.object as? NEVPNConnection else { return }
        let s: String = switch conn.status {
        case .connected:     "connected"
        case .connecting:    "connecting"
        case .disconnecting: "disconnecting"
        case .reasserting:   "connecting"
        case .invalid:       "error: invalid configuration"
        default:             "disconnected"
        }
        eventSink?(s)
    }
}
