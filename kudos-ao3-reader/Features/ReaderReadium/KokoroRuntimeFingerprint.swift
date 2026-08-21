import CryptoKit
import Foundation

/// Streaming SHA-256 of a Kokoro runtime tree.
///
/// Root files stay in pack order (`model.onnx` / `model.int8.onnx`, then
/// `voices.bin`, then `tokens.txt`). Only the eSpeak subtree is sorted, so a
/// lexical reorder of the three root names cannot change the digest.
nonisolated enum KokoroRuntimeFingerprint {
    static let rootSupportFileNames = ["voices.bin", "tokens.txt"]
    static let eSpeakDirectoryName = "espeak-ng-data"
    private static let chunkSize = 1_048_576

    static func rootFileNames(modelFileName: String) -> [String] {
        [modelFileName] + rootSupportFileNames
    }

    static func sha256Hex(ofFile url: URL) throws -> String {
        var hasher = SHA256()
        try update(&hasher, withFileAt: url)
        return hex(hasher.finalize())
    }

    static func byteCount(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Int64(fileSize)
    }

    static func runtimeContentSHA256(
        modelFileName: String,
        in modelDirectory: URL
    ) throws -> String {
        var hasher = SHA256()
        for file in try runtimeContentFiles(
            modelFileName: modelFileName,
            in: modelDirectory
        ) {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))
            try update(&hasher, withFileAt: file.url)
            hasher.update(data: Data([0]))
        }
        return hex(hasher.finalize())
    }

    static func runtimeContentFiles(
        modelFileName: String,
        in modelDirectory: URL
    ) throws -> [(relativePath: String, url: URL)] {
        let fileManager = FileManager.default
        var files: [(relativePath: String, url: URL)] = []
        for fileName in rootFileNames(modelFileName: modelFileName) {
            let url = modelDirectory.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            files.append((fileName, url))
        }

        let eSpeakDirectory = modelDirectory.appendingPathComponent(
            eSpeakDirectoryName,
            isDirectory: true
        )
        var isESpeakDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: eSpeakDirectory.path,
            isDirectory: &isESpeakDirectory
        ), isESpeakDirectory.boolValue,
              let enumerator = fileManager.enumerator(
                  at: eSpeakDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              )
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        var eSpeakFiles: [(relativePath: String, url: URL)] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard values.isRegularFile == true else { continue }
            let relativePath = "\(eSpeakDirectoryName)/" + String(
                url.path.dropFirst(eSpeakDirectory.path.count + 1)
            )
            eSpeakFiles.append((relativePath, url))
        }

        guard !eSpeakFiles.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return files + eSpeakFiles.sorted { $0.relativePath < $1.relativePath }
    }

    static func hasCompleteSupportFiles(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        for fileName in rootSupportFileNames {
            let url = directory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: url.path),
                  ((try? byteCount(of: url)) ?? 0) > 0
            else {
                return false
            }
        }
        var isDirectory: ObjCBool = false
        let eSpeak = directory.appendingPathComponent(
            eSpeakDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: eSpeak.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }
        return true
    }

    private static func update(_ hasher: inout SHA256, withFileAt url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            hasher.update(data: data)
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
