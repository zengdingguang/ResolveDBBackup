import Foundation
import SystemConfiguration
import Darwin

/// 一个活跃的 IPv4 网络接口（用于手动添加网络数据库时自动填主机 IP）。
struct NetworkInterface: Equatable {
    /// 接口名，如 en0 / en1。
    let name: String
    /// 类型标签：以太网 / Wi-Fi / 其他。
    let type: String
    /// 该接口的 IPv4 地址。
    let ip: String
}

/// 枚举本机网络接口（getifaddrs 拿 IP，SystemConfiguration 拿接口类型标签）。
enum NetworkInterfaces {
    /// 列出所有持有非回环 IPv4 的活跃接口；为空表示取不到（兜底用 127.0.0.1）。
    static func list() -> [NetworkInterface] {
        var ipByInterface: [String: String] = [:]

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let p = ptr {
            if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: p.pointee.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                            socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                    ipByInterface[name] = ip
                }
            }
            ptr = p.pointee.ifa_next
        }
        guard !ipByInterface.isEmpty else { return [] }

        var result: [NetworkInterface] = []
        // 用 SystemConfiguration 拿接口类型标签（更接近"以太网 / Wi-Fi"）
        if let scInterfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for iface in scInterfaces {
                guard let bsdName = SCNetworkInterfaceGetBSDName(iface) as String?,
                      let ip = ipByInterface[bsdName] else { continue }
                var type = "网络"
                if let raw = SCNetworkInterfaceGetInterfaceType(iface) as String? {
                    if raw == kSCNetworkInterfaceTypeIEEE80211 as String {
                        type = "Wi-Fi"
                    } else if raw == kSCNetworkInterfaceTypeEthernet as String {
                        type = "以太网"
                    } else if raw == kSCNetworkInterfaceTypeBluetooth as String {
                        type = "蓝牙"
                    } else {
                        type = raw
                    }
                }
                result.append(NetworkInterface(name: bsdName, type: type, ip: ip))
            }
        }
        // 兜底：getifaddrs 里有但 SC 未列出的接口
        for (name, ip) in ipByInterface where !result.contains(where: { $0.name == name }) {
            result.append(NetworkInterface(name: name, type: "网络", ip: ip))
        }
        // 排序：以太网/Wi-Fi 优先
        return result.sorted { a, b in
            func rank(_ i: NetworkInterface) -> Int {
                if i.type == "以太网" { return 0 }
                if i.type == "Wi-Fi" { return 1 }
                return 2
            }
            return rank(a) < rank(b)
        }
    }
}
