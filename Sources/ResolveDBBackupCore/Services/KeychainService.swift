import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

/// 密码存储：Keychain 通用密码，service = com.resolvedbbackup.pgpass，account = 连接 id。
enum KeychainService {
    static let service = "com.resolvedbbackup.pgpass"

    static func setString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            // 新建条目：允许所有应用访问（含升级/重签名后的本 App），
            // 避免每次更新后读取都弹"允许访问钥匙串"授权窗（v1.4.1 修复）。
            if let access = allowAllAccess() {
                query[kSecAttrAccess as String] = access
            }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 允许任意应用读取的 ACL（SecTrustedApplicationCreateFromPath(nil) = 匹配所有应用）。
    private static func allowAllAccess() -> SecAccess? {
        var trustedApp: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trustedApp) == errSecSuccess,
              let trusted = trustedApp else { return nil }
        let trustedList: CFArray = [trusted] as CFArray
        var access: SecAccess?
        guard SecAccessCreate("ResolveDBBackup" as CFString, trustedList, &access) == errSecSuccess else {
            return nil
        }
        return access
    }

    static func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
