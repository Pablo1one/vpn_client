import NetworkExtension

// sing-box iOS library — add LibBox.xcframework to this target in Xcode.
// Download from: https://github.com/SagerNet/sing-box/releases (LibBox.xcframework.zip)
// Then uncomment the import and the LibboxNewService call below.
//
// import LibBox

class PacketTunnelProvider: NEPacketTunnelProvider {

    // private var box: LibboxBoxService?

    override func startTunnel(
        options: [String: NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let config = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["config"] as? String
        else {
            completionHandler(makeErr(1, "Missing sing-box config in providerConfiguration"))
            return
        }

        // ── With LibBox.xcframework ──────────────────────────────────────────
        // Uncomment once LibBox.xcframework is added to the PacketTunnel target:
        //
        // do {
        //     var err: NSError?
        //     box = LibboxNewBoxService(config, &err)
        //     if let e = err { throw e }
        //     let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        //     settings.ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        //     settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        //     settings.ipv6Settings = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        //     settings.ipv6Settings?.includedRoutes = [NEIPv6Route.default()]
        //     settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        //     settings.mtu = 9000
        //     setTunnelNetworkSettings(settings) { [weak self] error in
        //         if let e = error { completionHandler(e); return }
        //         do { try self?.box?.start(); completionHandler(nil) }
        //         catch { completionHandler(error) }
        //     }
        // } catch { completionHandler(error) }
        //
        // ── Stub (no library) ────────────────────────────────────────────────
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(
            addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"]
        )
        settings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        settings.ipv6Settings = NEIPv6Settings(
            addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126]
        )
        settings.ipv6Settings?.includedRoutes = [NEIPv6Route.default()]
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        settings.mtu = 9000
        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        // box?.close()
        // box = nil
        completionHandler()
    }

    private func makeErr(_ code: Int, _ msg: String) -> NSError {
        NSError(domain: "PacketTunnel", code: code,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
