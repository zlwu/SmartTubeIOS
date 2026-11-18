#if DEBUG
import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - FileKeychainStore / KeychainStoreSelection
//
// Every test uses a throwaway directory so it never reads or writes the
// developer's debug store. The store is DEBUG-only, matching the package's
// debug test build.

@Suite("FileKeychainStore")
struct FileKeychainStoreTests {

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("smarttube-file-keychain-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(in directory: URL) throws -> FileKeychainStore {
        try #require(FileKeychainStore(directory: directory))
    }

    // MARK: - Persistence

    @Test("values persist across store instances")
    func valuesPersistAcrossInstances() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "access-abc")
        store.set(service: "com.smarttube.auth", key: "st_refresh_token", value: "refresh-xyz")

        // A fresh instance models an app relaunch.
        let reopened = try makeStore(in: directory)
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_access_token") == "access-abc")
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_refresh_token") == "refresh-xyz")
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_missing") == nil)
    }

    @Test("set(nil) and delete remove only the targeted key")
    func deletionRemovesOnlyTargetedKey() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "a", value: "1")
        store.set(service: "com.smarttube.auth", key: "b", value: "2")

        store.set(service: "com.smarttube.auth", key: "a", value: nil)
        #expect(store.get(service: "com.smarttube.auth", key: "a") == nil)
        #expect(store.get(service: "com.smarttube.auth", key: "b") == "2")

        store.delete(service: "com.smarttube.auth", key: "b")
        store.delete(service: "com.smarttube.auth", key: "b")  // missing key is a no-op
        #expect(store.get(service: "com.smarttube.auth", key: "b") == nil)
    }

    @Test("services do not see each other's keys")
    func servicesAreIsolated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        store.set(service: "service-a", key: "token", value: "a")
        store.set(service: "service-b", key: "token", value: "b")

        #expect(store.get(service: "service-a", key: "token") == "a")
        #expect(store.get(service: "service-b", key: "token") == "b")
    }

    // MARK: - File handling

    @Test("a missing root directory is created on first write")
    func createsRootDirectory() throws {
        let directory = temporaryDirectory().appendingPathComponent("nested/deeper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let store = try makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "token")

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(store.get(service: "com.smarttube.auth", key: "st_access_token") == "token")
    }

    @Test("a non-UTF8 value file reads as nil and the next write recovers")
    func corruptValueFileRecovers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "placeholder")
        try Data([0xFF, 0xFE, 0x00]).write(to: store.url(service: "com.smarttube.auth", key: "st_access_token"))

        #expect(store.get(service: "com.smarttube.auth", key: "st_access_token") == nil)

        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "recovered")
        #expect(store.get(service: "com.smarttube.auth", key: "st_access_token") == "recovered")
    }

    @Test("value files and directories are private")
    func filePermissionsArePrivate() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "token")

        let fileURL = store.url(service: "com.smarttube.auth", key: "st_access_token")
        #expect(permissions(at: directory) == 0o700)
        #expect(permissions(at: fileURL.deletingLastPathComponent()) == 0o700)
        #expect(permissions(at: fileURL) == 0o600)
    }

    @Test("awkward service and key names stay inside the root and stay distinct")
    func encodesAwkwardNames() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try makeStore(in: directory)
        let services = ["com.smarttube.auth", "a/b", "a%2Fb", ".", "..", "ключ"]
        for (index, service) in services.enumerated() {
            store.set(service: service, key: "../key", value: "value-\(index)")
        }

        for (index, service) in services.enumerated() {
            #expect(store.get(service: service, key: "../key") == "value-\(index)")
        }

        let urls = Set(services.map { store.url(service: $0, key: "../key") })
        #expect(urls.count == services.count)
        let rootPath = directory.standardizedFileURL.path
        for url in urls {
            #expect(url.standardizedFileURL.path.hasPrefix(rootPath + "/"))
        }
    }

    @Test("init fails when the root path is an existing regular file")
    func initFailsWhenRootIsAFile() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)

        #expect(FileKeychainStore(directory: directory) == nil)
    }

    private func permissions(at url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?
            .intValue
    }

    // MARK: - Backend selection

    @Test("backend selection follows the documented precedence")
    func backendSelection() {
        func backend(
            _ value: String?, debug: Bool, runningTests: Bool = false, arguments: [String] = []
        ) -> KeychainBackend {
            KeychainStoreSelection.resolve(
                environment: value.map { ["SMARTTUBE_KEYCHAIN": $0] } ?? [:],
                arguments: arguments,
                isRunningTests: runningTests,
                isDebugBuild: debug
            )
        }

        #expect(backend(nil, debug: true) == .file)
        #expect(backend(nil, debug: false) == .security)
        #expect(backend("file", debug: false) == .file)
        #expect(backend(" FILE ", debug: false) == .file)
        #expect(backend("keychain", debug: true) == .security)
        #expect(backend("memory", debug: true) == .memory)
        #expect(backend("memory", debug: false) == .security)
        #expect(backend(nil, debug: true, runningTests: true) == .memory)
        #expect(backend(nil, debug: true, arguments: ["--uitesting"]) == .memory)
        #expect(backend(nil, debug: true, runningTests: true, arguments: ["--uitesting"]) == .memory)
        #expect(backend("file", debug: true, runningTests: true) == .file)
        #expect(backend("bogus", debug: true) == .file)
        #expect(backend("bogus", debug: false) == .security)
        #expect(backend("  ", debug: false) == .security)
    }

    @Test("the test runner is detected so default stores stay in memory")
    func detectsTestRunner() {
        #expect(KeychainStoreSelection.isRunningTests())
        #expect(
            KeychainStoreSelection.resolve(
                environment: [:], arguments: [], isRunningTests: KeychainStoreSelection.isRunningTests(),
                isDebugBuild: true) == .memory)
    }

    @Test("SMARTTUBE_KEYCHAIN_DIR accepts absolute and tilde paths")
    func directoryOverride() {
        let absolute = KeychainStoreSelection.directory(
            environment: ["SMARTTUBE_KEYCHAIN_DIR": "/tmp/smarttube-debug-keychain"])
        #expect(absolute.path == "/tmp/smarttube-debug-keychain")

        let tilde = KeychainStoreSelection.directory(
            environment: ["SMARTTUBE_KEYCHAIN_DIR": "~/smarttube-debug-keychain"])
        #expect(tilde.path.hasPrefix("/"))
        #expect(tilde.lastPathComponent == "smarttube-debug-keychain")
        #expect(!tilde.path.contains("~"))

        let relative = KeychainStoreSelection.directory(
            environment: ["SMARTTUBE_KEYCHAIN_DIR": "relative/path"])
        #expect(relative.lastPathComponent == FileKeychainStore.defaultDirectoryName)

        let empty = KeychainStoreSelection.directory(environment: ["SMARTTUBE_KEYCHAIN_DIR": "  "])
        #expect(empty.lastPathComponent == FileKeychainStore.defaultDirectoryName)
        #expect(empty.deletingLastPathComponent().lastPathComponent == appSubsystem)
    }
}
#endif
