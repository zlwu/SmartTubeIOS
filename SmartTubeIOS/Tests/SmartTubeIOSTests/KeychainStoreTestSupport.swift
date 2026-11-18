import Foundation

@testable import SmartTubeIOSCore

/// Isolated on-disk store for tests. Every call gets its own directory, so tests
/// never read or write the app's real credential files.
func makeTemporaryKeychainStore() -> (store: FileKeychainStore, directory: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("smarttube-keychain-tests-\(UUID().uuidString)", isDirectory: true)
    return (FileKeychainStore(directory: directory), directory)
}
