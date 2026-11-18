import Foundation
import os

private let keychainLog = Logger(subsystem: appSubsystem, category: "Keychain")

// MARK: - KeychainStoring
//
// Seam over credential storage so tests can substitute a store.

public protocol KeychainStoring: Sendable {
    func get(service: String, key: String) -> String?
    func set(service: String, key: String, value: String?)
    func delete(service: String, key: String)
}

#if DEBUG
/// In-memory stand-in for tests. One instance per `TokenManager` unless a
/// shared instance is injected; tests that need cross-instance persistence
/// share one explicitly.
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

// MARK: - Factory

enum KeychainStoreFactory {
    /// Every build stores auth tokens in a file-backed store: no Keychain
    /// authorization dialogs in local runs, and the sign-in survives relaunches.
    /// Tokens are plaintext inside the app sandbox (0600), by design.
    static func defaultStore() -> any KeychainStoring {
        let directory = FileKeychainStore.defaultDirectory()
        keychainLog.notice(
            "KeychainStore: using file store at \(directory.path, privacy: .public)")
        return FileKeychainStore(directory: directory)
    }
}
