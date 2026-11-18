import Foundation
import os

private let fileKeychainLog = Logger(subsystem: appSubsystem, category: "Keychain")

// MARK: - FileKeychainStore
//
// Directory-backed credential store used by every build (see ADR-0010).
//
// Layout: <root>/<encoded service>/<encoded key>; the file contents are the raw
// UTF-8 value. One file per key keeps writes atomic and independent, so a
// corrupt entry cannot take down the rest of the store.
//
// The app is sandboxed on macOS/iOS/tvOS, so the default root resolves inside
// the app container. Tests always pass an explicit temporary directory.

final class FileKeychainStore: KeychainStoring, @unchecked Sendable {

    static let defaultDirectoryName = "DebugKeychain"

    /// Serializes file access across every store instance in this process.
    private static let lock = NSLock()

    let directory: URL

    init(directory: URL) {
        self.directory = directory
        prepareDirectory()
    }

    func get(service: String, key: String) -> String? {
        let url = url(service: service, key: key)
        Self.lock.lock()
        defer { Self.lock.unlock() }

        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            fileKeychainLog.error(
                "unreadable credential value at \(url.path, privacy: .public)")
            return nil
        }
        return value
    }

    func set(service: String, key: String, value: String?) {
        let url = url(service: service, key: key)
        Self.lock.lock()
        defer { Self.lock.unlock() }

        guard let value else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        let fileManager = FileManager.default
        let serviceDirectory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: serviceDirectory, withIntermediateDirectories: true)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: serviceDirectory.path)
            try Data(value.utf8).write(to: url, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            fileKeychainLog.error(
                "cannot write credential value at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func delete(service: String, key: String) {
        let url = url(service: service, key: key)
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    /// Root directory: `SMARTTUBE_KEYCHAIN_DIR` when it names an absolute path
    /// (a leading `~` is expanded), otherwise Application Support. The app is
    /// sandboxed, so the default resolves inside its container.
    static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let raw = environment["SMARTTUBE_KEYCHAIN_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        {
            let expanded = NSString(string: raw).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
            fileKeychainLog.notice(
                "SMARTTUBE_KEYCHAIN_DIR is not absolute; using the default directory")
        }

        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return
            base
            .appendingPathComponent(appSubsystem, isDirectory: true)
            .appendingPathComponent(defaultDirectoryName, isDirectory: true)
    }

    /// File URL for a key. Internal so tests can corrupt or inspect files directly.
    func url(service: String, key: String) -> URL {
        directory
            .appendingPathComponent(Self.encode(service), isDirectory: true)
            .appendingPathComponent(Self.encode(key), isDirectory: false)
    }

    /// Percent-encodes everything outside `[A-Za-z0-9._-]`, which keeps the
    /// current identifiers readable (`com.smarttube.auth`, `st_access_token`).
    /// `.`/`..` are encoded so a component can never escape its parent.
    static func encode(_ component: String) -> String {
        var encoded = ""
        for byte in component.utf8 {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E:
                encoded.append(Character(UnicodeScalar(byte)))
            default:
                encoded += String(format: "%%%02X", Int(byte))
            }
        }
        if encoded.isEmpty { return "%" }
        if encoded == "." || encoded == ".." {
            return encoded.replacingOccurrences(of: ".", with: "%2E")
        }
        return encoded
    }

    private func prepareDirectory() {
        let fileManager = FileManager.default
        let path = directory.path
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fileKeychainLog.error(
                "cannot create credential directory at \(path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)

        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }
}
