import Foundation
import Security
import os

private let keychainLog = Logger(subsystem: appSubsystem, category: "Keychain")

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

// MARK: - Selection

enum KeychainBackend: Equatable {
    case security
    case file
    case memory
}

enum KeychainStoreSelection {
    /// Resolves the backend from environment and launch arguments. Pure so tests
    /// can cover every branch; the factory supplies the process values.
    static func resolve(
        environment: [String: String],
        arguments: [String],
        isRunningTests: Bool,
        isDebugBuild: Bool
    ) -> KeychainBackend {
        switch environment["SMARTTUBE_KEYCHAIN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        {
        case "keychain":
            return .security
        case "file":
            return .file
        case "memory":
            // Release stays on the real Keychain: plaintext persistence is only
            // ever an explicit `file` opt-in, never a side effect of an old variable.
            return isDebugBuild ? .memory : .security
        default:
            break
        }

        guard isDebugBuild else { return .security }
        if isRunningTests || arguments.contains("--uitesting") { return .memory }
        return .file
    }

    /// `SMARTTUBE_KEYCHAIN_DIR` wins when it names an absolute path (a leading
    /// `~` is expanded); otherwise the store lives under Application Support.
    /// The app is sandboxed, so the default resolves inside its container.
    static func directory(environment: [String: String]) -> URL {
        if let raw = environment["SMARTTUBE_KEYCHAIN_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        {
            let expanded = NSString(string: raw).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
            keychainLog.notice(
                "KeychainStore: SMARTTUBE_KEYCHAIN_DIR is not absolute; using the default")
        }

        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return
            base
            .appendingPathComponent(appSubsystem, isDirectory: true)
            .appendingPathComponent(FileKeychainStore.defaultDirectoryName, isDirectory: true)
    }

    static func isRunningTests(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

enum KeychainStoreFactory {
    /// Debug builds default to the file-backed store: local runs must never
    /// trigger the macOS Keychain authorization dialog, and sign-in has to
    /// survive an app relaunch. Test and `--uitesting` runs keep the in-memory
    /// store so they stay hermetic. Release defaults to the real Keychain; only
    /// an explicit `SMARTTUBE_KEYCHAIN=file` opts a local Release run in.
    ///
    /// Overrides (all builds): `SMARTTUBE_KEYCHAIN=keychain|file|memory`,
    /// `SMARTTUBE_KEYCHAIN_DIR=<absolute path>`.
    static func defaultStore() -> any KeychainStoring {
        let environment = ProcessInfo.processInfo.environment
        let backend = KeychainStoreSelection.resolve(
            environment: environment,
            arguments: ProcessInfo.processInfo.arguments,
            isRunningTests: KeychainStoreSelection.isRunningTests(environment: environment),
            isDebugBuild: KeychainStoreSelection.isDebugBuild
        )

        switch backend {
        case .security:
            keychainLog.notice("KeychainStore: using the real Keychain")
            return SecurityKeychainStore()

        case .file:
            let directory = KeychainStoreSelection.directory(environment: environment)
            if let store = FileKeychainStore(directory: directory) {
                keychainLog.notice(
                    "KeychainStore: using file store at \(store.directory.path, privacy: .public)")
                return store
            }
            keychainLog.error(
                "KeychainStore: file store unavailable at \(directory.path, privacy: .public); falling back"
            )
            #if DEBUG
            return InMemoryKeychainStore()
            #else
            return SecurityKeychainStore()
            #endif

        case .memory:
            #if DEBUG
            keychainLog.notice("KeychainStore: using in-memory store")
            return InMemoryKeychainStore()
            #else
            keychainLog.error(
                "KeychainStore: memory store is unavailable in Release; using the real Keychain")
            return SecurityKeychainStore()
            #endif
        }
    }
}
