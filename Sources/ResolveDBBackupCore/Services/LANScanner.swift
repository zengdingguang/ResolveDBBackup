import Foundation
import Darwin

/// 扫描局域网 PostgreSQL 数据库（达芬奇网络库可部署在局域网机器上）。
/// 范围：默认自动全扫本机所在 /24 网段 + 可手动追加指定 IP / CIDR。
enum LANScanner {
    /// 局域网扫描端口（达芬奇默认 5432，少量 5433）。
    static let lanPorts = [5432, 5433]

    // MARK: - 网段推导

    /// 本机非回环 IPv4 地址（getifaddrs）。
    static func localIPv4Addresses() -> [String] {
        var addrs: [String] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return [] }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let p = ptr {
            let family = p.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(p.pointee.ifa_addr,
                            socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.hasPrefix("127."), !ip.hasPrefix("169.254."), !ip.hasPrefix("0.") {
                    addrs.append(ip)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return addrs
    }

    /// 由 IPv4 推导 /24 子网（a.b.c.0/24）。
    static func subnet24(of ip: String) -> String? {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    /// 本机所有 /24 网段（去重）。
    static func localSubnets() -> [String] {
        var set = Set<String>()
        for ip in localIPv4Addresses() {
            if let s = subnet24(of: ip) { set.insert(s) }
        }
        return set.sorted()
    }

    /// /24 网段的 1~254 主机 IP。入参可为 `a.b.c.0` 或 `a.b.c.0/24`。
    static func subnetHosts(_ subnet: String) -> [String] {
        var s = subnet
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[3] == 0 else { return [] }
        return (1...254).map { "\(parts[0]).\(parts[1]).\(parts[2]).\($0)" }
    }

    // MARK: - 输入展开（可单测）

    static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            guard let v = Int(p), v >= 0, v <= 255 else { return false }
            return true
        }
    }

    static func ipString(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    /// 展开 CIDR（如 192.168.3.0/24）为可用主机 IP（排除网络地址与广播地址）；
    /// 前缀 <16（>65535 台）视为输入错误返回 nil。
    static func cidrHosts(_ cidr: String) -> [String]? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix) else { return nil }
        let ipParts = parts[0].split(separator: ".").compactMap { Int($0) }
        guard ipParts.count == 4 else { return nil }
        var addr: UInt32 = 0
        for v in ipParts { addr = (addr << 8) | UInt32(v) }
        let hostBits = 32 - prefix
        guard hostBits <= 16 else { return nil }
        let mask: UInt32 = prefix == 0 ? 0 : (UInt32.max << hostBits)
        let base = addr & mask
        if hostBits == 0 { return [ipString(base)] }
        let total = 1 << hostBits
        var ips: [String] = []
        // 排除网络地址(i=0)与广播地址(最后一个)
        let usableLast = total - 2
        guard usableLast >= 1 else { return ips }
        for i in 1...usableLast {
            let v = base + UInt32(i)
            if v > 0xFFFF_FFFF { break }
            ips.append(ipString(v))
        }
        return ips
    }

    /// 展开用户输入（单 IP / CIDR）为 IP 列表。
    static func expandTargets(_ inputs: [String]) -> [String] {
        var result = Set<String>()
        for raw in inputs {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { continue }
            if s.contains("/") {
                if let ips = cidrHosts(s) { result.formUnion(ips) }
            } else if isIPv4(s) {
                result.insert(s)
            }
        }
        return result.sorted()
    }

    // MARK: - 扫描

    /// 扫描一批目标主机（默认 /24 网段 + 手动 IP/CIDR）上的 PostgreSQL 库。
    /// extraCredentials 来自 dblist.conf 网络库登记（比猜 DaVinci 更准）。
    static func scanLAN(targets: [String],
                        existing: Set<String> = [],
                        preferredToolDir: String? = nil,
                        extraCredentials: [(username: String, password: String)] = []) async -> [DiscoveredDatabase] {
        let dirs = ConnectionScanner.discoverPGToolDirs(preferred: preferredToolDir)
        guard let first = dirs.first, !targets.isEmpty else { return [] }
        let psql = "\(first)/psql"
        let pgIsReady = "\(first)/pg_isready"

        var creds = ConnectionScanner.defaultCredentials
        for c in extraCredentials
        where !creds.contains(where: { $0.0 == c.username && $0.1 == c.password }) {
            creds.append((c.username, c.password))
        }

        var found: [DiscoveredDatabase] = []
        // 分批并发，避免同时拉起过多子进程；用返回值累加（避免在异步上下文共享锁）
        let chunkSize = 24
        for start in stride(from: 0, to: targets.count, by: chunkSize) {
            // 支持"停止扫描"：外部取消时，在下一批开始前尽早返回已发现结果
            if Task.isCancelled {
                let seen = Set(found.map(\.id))
                return found.filter { seen.contains($0.id) }
            }
            let chunk = Array(targets[start..<min(start + chunkSize, targets.count)])
            await withTaskGroup(of: [DiscoveredDatabase].self) { group in
                for host in chunk {
                    group.addTask {
                        await scanHost(host: host, ports: lanPorts, psql: psql,
                                       pgIsReady: pgIsReady, creds: creds,
                                       existing: existing)
                    }
                }
                for await batch in group {
                    found.append(contentsOf: batch)
                }
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    private static func scanHost(host: String, ports: [Int], psql: String, pgIsReady: String,
                                 creds: [(String, String)], existing: Set<String>) async -> [DiscoveredDatabase] {
        var out: [DiscoveredDatabase] = []
        for port in ports {
            guard await ConnectionScanner.probe(host: host, port: port, pgIsReady: pgIsReady) else { continue }
            for (user, pwd) in creds {
                let dbs = await ConnectionScanner.listDatabases(host: host, port: port,
                                                                username: user, password: pwd,
                                                                psqlPath: psql)
                if !dbs.isEmpty {
                    for db in dbs {
                        let item = DiscoveredDatabase(kind: .network, host: host, port: port,
                                                      dbname: db, username: user, password: pwd)
                        if !existing.contains(item.id) { out.append(item) }
                    }
                    break // 该端口已用某组凭据成功
                }
            }
        }
        return out
    }
}
