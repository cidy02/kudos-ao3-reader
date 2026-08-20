import Foundation
import OSLog
import SWCompression

/// Manages the background downloading and extraction of the Kokoro TTS model.
@MainActor
@Observable
public final class TTSDownloadManager: NSObject {
    public enum Status: Equatable {
        case idle
        case downloading(progress: Double) // 0.0 to 1.0
        case extracting
        case completed
        case failed(error: String)
    }

    public private(set) var status: Status = .idle
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "tts_model_download")
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public let modelDirectory: URL

    public override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelDirectory = appSupport.appendingPathComponent("TTS_Models/kokoro-int8-en-v0_19", isDirectory: true)
        super.init()
        
        if isModelDownloaded() {
            self.status = .completed
        }
    }

    public func isModelDownloaded() -> Bool {
        let fm = FileManager.default
        let requiredFiles = ["model.int8.onnx", "voices.bin", "tokens.txt"]
        let requiredDirs = ["espeak-ng-data"]
        
        for file in requiredFiles {
            let path = modelDirectory.appendingPathComponent(file).path
            if !fm.fileExists(atPath: path) { return false }
            if (try? fm.attributesOfItem(atPath: path)[.size] as? Int) == 0 { return false }
        }
        
        for dir in requiredDirs {
            var isDir: ObjCBool = false
            let path = modelDirectory.appendingPathComponent(dir).path
            if !fm.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue { return false }
        }
        
        return true
    }

    public func downloadModel() async throws {
        // Space pre-check (approx 200MB expected for kokoro-int8-en-v0_19)
        let fm = FileManager.default
        let sysAttrs = try fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        if let freeSpace = sysAttrs[.systemFreeSize] as? NSNumber, freeSpace.int64Value < 300_000_000 {
            status = .failed(error: "Not enough storage space. At least 300MB required.")
            throw NSError(domain: "TTSDownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not enough storage space."])
        }

        if isModelDownloaded() {
            status = .completed
            return
        }

        let url = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2")!
        
        status = .downloading(progress: 0)
        let task = urlSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    public func pause() {
        downloadTask?.suspend()
    }
    
    public func resume() {
        downloadTask?.resume()
    }
    
    public func cancel() {
        downloadTask?.cancel()
        status = .idle
    }
}

extension TTSDownloadManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                if case .downloading = self.status {
                    self.status = .downloading(progress: progress)
                }
            }
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            self.status = .extracting
        }
        
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }
            
            let data = try Data(contentsOf: location)
            let decompressedData = try BZip2.decompress(data: data)
            let entries = try TarContainer.open(container: decompressedData)
            
            for entry in entries {
                guard let info = entry.info.name else { continue }
                
                // Remove the top-level folder prefix (kokoro-int8-en-v0_19/) from paths
                var relativePath = info
                let prefix = "kokoro-int8-en-v0_19/"
                if relativePath.hasPrefix(prefix) {
                    relativePath = String(relativePath.dropFirst(prefix.count))
                }
                if relativePath.isEmpty { continue }
                
                let targetURL = self.modelDirectory.appendingPathComponent(relativePath)
                
                if entry.info.type == .directory {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                } else if let fileData = entry.data {
                    let parent = targetURL.deletingLastPathComponent()
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                    try fileData.write(to: targetURL)
                }
            }
            
            Task { @MainActor in
                if self.isModelDownloaded() {
                    self.status = .completed
                } else {
                    self.status = .failed(error: "Extraction completed but verification failed.")
                    try? fm.removeItem(at: self.modelDirectory)
                }
            }
        } catch {
            Task { @MainActor in
                self.status = .failed(error: error.localizedDescription)
            }
            try? fm.removeItem(at: self.modelDirectory)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.status = .failed(error: error.localizedDescription)
            }
        }
    }
}
