import Foundation
import Network

// === 本机网络观测 ===
//
// 诊断页要回答两个问题：「手机现在走的是 Wi-Fi 还是蜂窝」「手机自己的内网 IP 是多少」。
// 第二个问题决定了用户会不会把电脑地址写成 `127.0.0.1`——这是最常见的错误。

enum LocalNetwork {

    /// 遍历网卡，取 Wi-Fi（en0）的 IPv4；取不到就退到第一个非蜂窝、非回环地址。
    static func wifiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        var fallback: String?

        while let current = pointer {
            let interface = current.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if !name.hasPrefix("pdp_ip"), name != "lo0" {
                    var address = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &address,
                        socklen_t(address.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let ip = String(cString: address)
                        if name == "en0" { return ip }
                        if fallback == nil { fallback = ip }
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return fallback
    }

    /// 是否像内网地址。用来在设置页提示「这个地址只能在同一 Wi-Fi 下用」。
    static func isPrivateIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        // Tailscale / CGNAT 段
        if parts[0] == 100, (64...127).contains(parts[1]) { return true }
        return false
    }

    /// Tailscale 的地址段（100.64.0.0/10），用来给连接方式做提示。
    static func isTailscaleIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }
}

/// 持续观察系统网络路径，给「概览」和「诊断」提供实时状态。
@MainActor
final class NetworkWatcher: ObservableObject {

    @Published private(set) var isSatisfied = true
    @Published private(set) var isWiFi = false
    @Published private(set) var isCellular = false
    @Published private(set) var isExpensive = false
    @Published private(set) var localIPv4: String?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "panel.console.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            let cellular = path.usesInterfaceType(.cellular)
            let expensive = path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                self.isSatisfied = satisfied
                self.isWiFi = wifi
                self.isCellular = cellular
                self.isExpensive = expensive
                self.localIPv4 = LocalNetwork.wifiIPv4()
            }
        }
        monitor.start(queue: queue)
        localIPv4 = LocalNetwork.wifiIPv4()
    }

    deinit {
        monitor.cancel()
    }

    var interfaceText: String {
        if isWiFi { return "Wi-Fi" }
        if isCellular { return "蜂窝网络" }
        return isSatisfied ? "其他网络" : "无网络"
    }

    /// 诊断用的单行摘要。
    var summary: String {
        var parts = [interfaceText]
        if let ip = localIPv4 { parts.append("本机 \(ip)") }
        if isExpensive { parts.append("计费网络") }
        return parts.joined(separator: " · ")
    }
}
