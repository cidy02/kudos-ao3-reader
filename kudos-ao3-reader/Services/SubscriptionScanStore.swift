import Foundation

enum SubscriptionScanStoreError: Error, Equatable {
    /// The file on disk belongs to a different account, or its schema is not
    /// one this build can read. Callers must not overwrite it.
    case notWritable
}

/// One JSON file per authentication scope under Application Support.
/// Excluded from device backup. Not part of `.kudosbackup` or folder sync.
struct SubscriptionScanStore {
    let directoryURL: URL
    let authenticationScope: String

    init(directoryURL: URL, authenticationScope: String) {
        self.directoryURL = directoryURL
        self.authenticationScope = authenticationScope
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appendingPathComponent("KudosSubscriptionScan", isDirectory: true)
    }

    /// Empty when no file exists yet. Throws `notWritable` when a file is there
    /// but must be left untouched (wrong account inside the file, or a schema
    /// this build does not understand).
    func load() throws -> SubscriptionScanFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty(scope: authenticationScope)
        }
        let decoded = try JSONDecoder().decode(SubscriptionScanFile.self, from: Data(contentsOf: fileURL))
        guard decoded.schemaVersion == SubscriptionScanFile.currentSchema,
              decoded.authenticationScope == authenticationScope
        else { throw SubscriptionScanStoreError.notWritable }
        return decoded
    }

    func save(_ file: SubscriptionScanFile) throws {
        guard file.authenticationScope == authenticationScope,
              file.schemaVersion == SubscriptionScanFile.currentSchema
        else { throw SubscriptionScanStoreError.notWritable }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directoryURL
        try directory.setResourceValues(values)
        try fileData(file).write(to: fileURL, options: .atomic)
    }

    var fileURL: URL {
        let allowed = CharacterSet.alphanumerics
        let name = authenticationScope.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? "scope"
        return directoryURL.appendingPathComponent(name).appendingPathExtension("json")
    }

    private func fileData(_ file: SubscriptionScanFile) throws -> Data {
        try JSONEncoder().encode(file)
    }
}
