#if DEBUG
import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - FileKeychainStore
//
// Every test uses a throwaway directory so it never reads or writes the real
// credential store.

@Suite("FileKeychainStore")
struct FileKeychainStoreTests {

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("smarttube-file-keychain-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(in directory: URL) -> FileKeychainStore {
        FileKeychainStore(directory: directory)
    }

    // MARK: - Persistence

    @Test("values persist across store instances")
    func valuesPersistAcrossInstances() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "access-abc")
        store.set(service: "com.smarttube.auth", key: "st_refresh_token", value: "refresh-xyz")

        // A fresh instance models an app relaunch.
        let reopened = makeStore(in: directory)
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_access_token") == "access-abc")
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_refresh_token") == "refresh-xyz")
        #expect(reopened.get(service: "com.smarttube.auth", key: "st_missing") == nil)
    }

    @Test("set(nil) and delete remove only the targeted key")
    func deletionRemovesOnlyTargetedKey() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(in: directory)
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
    func servicesAreIsolated() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(in: directory)
        store.set(service: "service-a", key: "token", value: "a")
        store.set(service: "service-b", key: "token", value: "b")

        #expect(store.get(service: "service-a", key: "token") == "a")
        #expect(store.get(service: "service-b", key: "token") == "b")
    }

    // MARK: - File handling

    @Test("a missing root directory is created on init")
    func createsRootDirectory() {
        let directory = temporaryDirectory().appendingPathComponent("nested/deeper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        let store = makeStore(in: directory)
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

        let store = makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "placeholder")
        try Data([0xFF, 0xFE, 0x00]).write(to: store.url(service: "com.smarttube.auth", key: "st_access_token"))

        #expect(store.get(service: "com.smarttube.auth", key: "st_access_token") == nil)

        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "recovered")
        #expect(store.get(service: "com.smarttube.auth", key: "st_access_token") == "recovered")
    }

    @Test("value files and directories are private")
    func filePermissionsArePrivate() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(in: directory)
        store.set(service: "com.smarttube.auth", key: "st_access_token", value: "token")

        let fileURL = store.url(service: "com.smarttube.auth", key: "st_access_token")
        #expect(permissions(at: directory) == 0o700)
        #expect(permissions(at: fileURL.deletingLastPathComponent()) == 0o700)
        #expect(permissions(at: fileURL) == 0o600)
    }

    @Test("awkward service and key names stay inside the root and stay distinct")
    func encodesAwkwardNames() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(in: directory)
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

    private func permissions(at url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?
            .intValue
    }

    // MARK: - Default directory

    @Test("the default directory lives under Application Support")
    func defaultDirectory() {
        let directory = FileKeychainStore.defaultDirectory
        #expect(directory.lastPathComponent == FileKeychainStore.defaultDirectoryName)
        #expect(directory.deletingLastPathComponent().lastPathComponent == appSubsystem)
        #expect(directory.path.contains("Application Support"))
    }
}
#endif
