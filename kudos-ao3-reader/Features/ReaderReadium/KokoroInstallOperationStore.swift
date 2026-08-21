import Foundation

/// Durable state for a single user-initiated Kokoro download or its local
/// installation. It lets a background URLSession callback bind itself after
/// relaunch and lets a preserved download resume installation before iOS can
/// discard the work.
nonisolated struct KokoroInstallOperation: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case downloading
        case installing
    }

    let id: UUID
    let packIdentifier: String
    let phase: Phase
    let preservedFileName: String?

    init(
        id: UUID,
        pack: KokoroModelPack,
        phase: Phase,
        preservedFileName: String? = nil
    ) {
        self.id = id
        self.packIdentifier = pack.rawValue
        self.phase = phase
        self.preservedFileName = preservedFileName
    }

    var pack: KokoroModelPack? {
        KokoroModelPack(rawValue: packIdentifier)
    }

    var isValid: Bool {
        guard pack != nil else { return false }
        switch phase {
        case .downloading:
            return preservedFileName == nil
        case .installing:
            guard let preservedFileName,
                  preservedFileName.hasPrefix(".incoming-"),
                  preservedFileName == URL(fileURLWithPath: preservedFileName).lastPathComponent
            else {
                return false
            }
            return true
        }
    }
}

nonisolated enum KokoroInstallOperationStore {
    static let fileName = ".kudos-kokoro-install-operation.json"

    static func url(in modelsRoot: URL) -> URL {
        modelsRoot.appendingPathComponent(fileName, isDirectory: false)
    }

    static func read(in modelsRoot: URL, fileManager: FileManager = .default) -> KokoroInstallOperation? {
        let url = url(in: modelsRoot)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let operation = try? JSONDecoder().decode(KokoroInstallOperation.self, from: data),
              operation.isValid
        else {
            return nil
        }
        return operation
    }

    static func write(
        _ operation: KokoroInstallOperation,
        in modelsRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard operation.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(operation)
        try data.write(to: url(in: modelsRoot), options: .atomic)
    }

    static func remove(in modelsRoot: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url(in: modelsRoot))
    }
}
