import Foundation
import Security

// MARK: - KeychainStoring
//
// Seam over Keychain Services so tests and agent-local runs can opt out of
// touching the login keychain (which triggers a per-binary authorization
// dialog because SwiftPM test bundles are ad-hoc signed).

public protocol KeychainStoring: Sendable {
    func get(service: String, key: String) -> String?
    func set(service: String, key: String, value: String?)
    func delete(service: String, key: String)
}

/// Production implementation: the real Keychain (legacy file-based keychain on
/// macOS, data protection keychain on iOS/tvOS).
struct SecurityKeychainStore: KeychainStoring {
    func get(service: String, key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(service: String, key: String, value: String?) {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func delete(service: String, key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#if DEBUG
/// Debug-only in-memory stand-in for the Keychain. One instance per
/// `TokenManager` unless a shared instance is injected; tests that need
/// cross-instance persistence share one explicitly.
final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func get(service: String, key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[Self.id(service: service, key: key)]
    }

    func set(service: String, key: String, value: String?) {
        lock.lock()
        defer { lock.unlock() }
        values[Self.id(service: service, key: key)] = value
    }

    func delete(service: String, key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[Self.id(service: service, key: key)] = nil
    }

    private static func id(service: String, key: String) -> String { "\(service)\u{0}\(key)" }
}
#endif

enum KeychainStoreFactory {
    /// `SMARTTUBE_KEYCHAIN=memory` (debug builds only) keeps a process away from
    /// the real Keychain, so agent-launched local runs never hit the
    /// authorization dialog. Release builds compile this branch out entirely.
    static func defaultStore() -> any KeychainStoring {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SMARTTUBE_KEYCHAIN"] == "memory" {
            return InMemoryKeychainStore()
        }
        #endif
        return SecurityKeychainStore()
    }
}
