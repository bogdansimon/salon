import Foundation
import Security

/// API keys, stored only in the login Keychain (generic passwords, one per source).
public struct KeychainStore: Sendable {
    public static let standard = KeychainStore(service: "xyz.bogdansimon.salon.api-keys")

    private let service: String

    public init(service: String) { self.service = service }

    public func key(for source: SourceID) -> String? {
        var query = baseQuery(source)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func setKey(_ key: String?, for source: SourceID) -> Bool {
        SecItemDelete(baseQuery(source) as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var item = baseQuery(source)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Salon API key (\(source.rawValue))"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(_ source: SourceID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: source.rawValue]
    }
}
