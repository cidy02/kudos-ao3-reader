import Foundation
import OSLog
import SWCompression

/// Manages the background downloading and extraction of the Kokoro TTS model.
@MainActor
@Observable
public final class TTSDownloadManager: NSObject {
    static let backgroundSessionIdentifier = "com.cidy02.kudos.tts-model-download"
    static let shared = TTSDownloadManager()

    public enum Status: Equatable {
        case idle
        case downloading(progress: Double) // 0.0 to 1.0
        case extracting
        case installing
        case verifying
        case cancelling
        case completed
        case failed(error: String)
    }

    public private(set) var status: Status = .idle
    private(set) var statusPack: KokoroModelPack?
    private var downloadTask: URLSessionDownloadTask?
    @ObservationIgnored
    private var activeOperationPack: KokoroModelPack?
    @ObservationIgnored
    private var activeOperationID: UUID?
    @ObservationIgnored
    private var cancellationFlag = CancellationFlag()
    @ObservationIgnored
    private var activeDownloadTaskIdentifier: Int?
    @ObservationIgnored
    private var backgroundEventsCompletionHandler: (() -> Void)?
    @ObservationIgnored
    private var backgroundEventsDidFinish = false
    // @Observable rewrites stored properties into tracked computed accessors,
    // which lazy can't participate in — @ObservationIgnored opts this one out
    // (it's implementation detail, not observed UI state, so that's correct).
    @ObservationIgnored
    private lazy var urlSession: URLSession = {
        let config: URLSessionConfiguration
        if usesBackgroundSession {
            config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
            config.sessionSendsLaunchEvents = true
        } else {
            config = .ephemeral
        }
        return URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }()

    private let modelsRoot: URL
    public let modelDirectory: URL
    private let usesBackgroundSession: Bool

    public override convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.init(
            modelsRoot: appSupport.appendingPathComponent("TTS_Models", isDirectory: true),
            usesBackgroundSession: true
        )
    }

    /// Test-only injection point. Production always uses Application Support.
    convenience init(modelsRoot: URL) {
        self.init(modelsRoot: modelsRoot, usesBackgroundSession: false)
    }

    private init(modelsRoot: URL, usesBackgroundSession: Bool) {
        self.modelsRoot = modelsRoot
        self.usesBackgroundSession = usesBackgroundSession
        self.modelDirectory = modelsRoot.appendingPathComponent(
            KokoroModelPack.int8V019.modelDirectoryName,
            isDirectory: true
        )
        super.init()
        excludeFromBackup(modelsRoot)

        if isModelDownloaded() {
            self.statusPack = .int8V019
            self.status = .completed
        }
        recoverPersistedOperationIfNeeded()
        if usesBackgroundSession {
            restorePendingDownloadIfNeeded()
        }
    }

    /// Called by the app delegate when iOS relaunches the app to deliver a
    /// background download completion. The shared manager retains the session
    /// delegate and invokes this handler only after URLSession drains events.
    func handleBackgroundURLSessionEvents(completionHandler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = completionHandler
        backgroundEventsDidFinish = false
        recoverPersistedOperationIfNeeded()
        restorePendingDownloadIfNeeded()
    }

    func modelDirectory(for pack: KokoroModelPack) -> URL {
        guard pack != .int8V019 else { return modelDirectory }
        return modelsRoot.appendingPathComponent(
            pack.modelDirectoryName,
            isDirectory: true
        )
    }

    private func restorePendingDownloadIfNeeded() {
        guard usesBackgroundSession,
              let persisted = KokoroInstallOperationStore.read(in: modelsRoot),
              persisted.phase == .downloading,
              let persistedPack = persisted.pack
        else {
            return
        }
        urlSession.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self, self.activeOperationPack == nil else { return }
                guard let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: {
                    guard let metadata = Self.taskMetadata(from: $0) else { return false }
                    return metadata.id == persisted.id && metadata.pack == persistedPack
                })
                else {
                    guard let current = KokoroInstallOperationStore.read(in: self.modelsRoot),
                          let currentPack = current.pack,
                          current.id == persisted.id,
                          currentPack == persistedPack,
                          current.phase == .downloading
                    else {
                        return
                    }
                    self.statusPack = persistedPack
                    self.finishFailed("The Kokoro download could not be resumed. Please retry.")
                    return
                }
                _ = self.adoptPersistedDownloadIfNeeded(from: task)
            }
        }
    }

    private struct DownloadTaskMetadata {
        let id: UUID
        let pack: KokoroModelPack
    }

    private static func taskDescription(id: UUID, pack: KokoroModelPack) -> String {
        "kudos-kokoro|\(id.uuidString)|\(pack.rawValue)"
    }

    private static func taskMetadata(from task: URLSessionTask) -> DownloadTaskMetadata? {
        guard let description = task.taskDescription else { return nil }
        let pieces = description.split(separator: "|", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0] == "kudos-kokoro",
              let id = UUID(uuidString: String(pieces[1])),
              let pack = KokoroModelPack(rawValue: String(pieces[2]))
        else {
            return nil
        }
        return DownloadTaskMetadata(id: id, pack: pack)
    }

    /// Binds a background callback to the operation that was durably recorded
    /// before `resume()`. Never adopt a task merely because its description
    /// looks valid: a cancelled task must not come back to life after relaunch.
    private func adoptPersistedDownloadIfNeeded(from task: URLSessionTask) -> Bool {
        if let activeOperationPack {
            let metadata = Self.taskMetadata(from: task)
            return Self.isCurrentDownloadTask(
                callbackTaskIdentifier: task.taskIdentifier,
                activeTaskIdentifier: activeDownloadTaskIdentifier
            ) && activeOperationPack == metadata?.pack && activeOperationID == metadata?.id
        }

        guard let persisted = KokoroInstallOperationStore.read(in: modelsRoot),
              persisted.phase == .downloading,
              let persistedPack = persisted.pack,
              let metadata = Self.taskMetadata(from: task),
              metadata.id == persisted.id,
              metadata.pack == persistedPack
        else {
            return false
        }

        downloadTask = task as? URLSessionDownloadTask
        activeDownloadTaskIdentifier = task.taskIdentifier
        activeOperationID = metadata.id
        activeOperationPack = metadata.pack
        cancellationFlag = CancellationFlag()
        statusPack = metadata.pack
        let expected = task.countOfBytesExpectedToReceive
        let received = task.countOfBytesReceived
        let progress = expected > 0 ? Double(received) / Double(expected) : 0
        status = .downloading(progress: progress)
        if let downloadTask = task as? URLSessionDownloadTask,
           downloadTask.state == .suspended {
            // A process can end after the durable record is written but before
            // `resume()`. There is no persistent pause UI, so resume recovery.
            downloadTask.resume()
        }
        return true
    }

    private func recoverPersistedOperationIfNeeded() {
        guard activeOperationPack == nil else { return }
        guard let persisted = KokoroInstallOperationStore.read(in: modelsRoot) else {
            removeOrphanedPreservedDownloads(keeping: nil)
            return
        }

        guard let pack = persisted.pack else {
            KokoroInstallOperationStore.remove(in: modelsRoot)
            removeOrphanedPreservedDownloads(keeping: nil)
            return
        }

        switch persisted.phase {
        case .downloading:
            // URLSession rehydrates this task on its delegate callback or via
            // `getAllTasks`; no local file is ready to install yet.
            return
        case .installing:
            guard let fileName = persisted.preservedFileName else {
                KokoroInstallOperationStore.remove(in: modelsRoot)
                removeOrphanedPreservedDownloads(keeping: nil)
                return
            }
            let preserved = modelsRoot.appendingPathComponent(fileName, isDirectory: false)
            guard (try? KokoroRuntimeFingerprint.byteCount(of: preserved)) != nil else {
                KokoroInstallOperationStore.remove(in: modelsRoot)
                removeOrphanedPreservedDownloads(keeping: nil)
                return
            }

            removeOrphanedPreservedDownloads(keeping: fileName)
            let flag = CancellationFlag()
            activeOperationID = persisted.id
            activeOperationPack = pack
            activeDownloadTaskIdentifier = nil
            cancellationFlag = flag
            statusPack = pack
            status = pack.requiresInt8SupportFiles ? .installing : .extracting
            if pack.requiresInt8SupportFiles {
                finishFP32Download(from: preserved, operationID: persisted.id, flag: flag)
            } else {
                finishInt8Download(from: preserved, operationID: persisted.id, flag: flag)
            }
        }
    }

    private func persistOperation(
        id: UUID,
        pack: KokoroModelPack,
        phase: KokoroInstallOperation.Phase,
        preservedFileName: String? = nil
    ) throws {
        try KokoroInstallOperationStore.write(
            KokoroInstallOperation(
                id: id,
                pack: pack,
                phase: phase,
                preservedFileName: preservedFileName
            ),
            in: modelsRoot
        )
    }

    private func clearPersistedOperation() {
        KokoroInstallOperationStore.remove(in: modelsRoot)
    }

    private func removeOrphanedPreservedDownloads(keeping fileName: String?) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in contents where file.lastPathComponent.hasPrefix(".incoming-") &&
            file.lastPathComponent != fileName {
            try? FileManager.default.removeItem(at: file)
        }
    }

    nonisolated static func isCurrentDownloadTask(
        callbackTaskIdentifier: Int,
        activeTaskIdentifier: Int?
    ) -> Bool {
        callbackTaskIdentifier == activeTaskIdentifier
    }

    public func isModelDownloaded() -> Bool {
        isModelDownloaded(for: .int8V019)
    }

    func isModelDownloaded(for pack: KokoroModelPack) -> Bool {
        let fm = FileManager.default
        let modelDirectory = modelDirectory(for: pack)
        let requiredFiles = pack.requiredFileNames
        let requiredDirs = [KokoroRuntimeFingerprint.eSpeakDirectoryName]

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

        guard pack.validationMarkerFileName != nil else { return true }
        return isVerifiedPack(pack, in: modelDirectory)
    }

    func refreshStatus(for pack: KokoroModelPack) {
        guard activeOperationPack == nil else { return }
        statusPack = pack
        status = isModelDownloaded(for: pack) ? .completed : .idle
    }

    /// Re-fingerprint an already-present FP32 tree (side-load or a previous
    /// install whose marker was cleared). In-app install uses `downloadModel`.
    func verifyDeveloperInstalledModelPack(_ pack: KokoroModelPack) async {
        guard pack.validationMarkerFileName != nil,
              activeOperationPack == nil,
              let expectedFingerprint = pack.expectedRuntimeContentSHA256,
              let markerFileName = pack.validationMarkerFileName,
              let markerContents = pack.validationMarkerContents
        else {
            refreshStatus(for: pack)
            return
        }

        let directory = modelDirectory(for: pack)
        let markerURL = directory.appendingPathComponent(markerFileName)
        try? FileManager.default.removeItem(at: markerURL)
        let operationID = UUID()
        let flag = CancellationFlag()
        activeOperationPack = pack
        activeOperationID = operationID
        cancellationFlag = flag
        statusPack = pack
        status = .verifying

        let modelFileName = pack.modelFileName
        let fingerprint = await Task.detached(priority: .utility) {
            try? KokoroRuntimeFingerprint.runtimeContentSHA256(
                modelFileName: modelFileName,
                in: directory
            )
        }.value

        guard isCurrentOperation(id: operationID, pack: pack) else {
            return
        }
        guard !flag.isCancelled else {
            finishIdle()
            return
        }

        guard fingerprint == expectedFingerprint else {
            finishFailed("FP32 verification failed. Download the official v0.19 model again.")
            return
        }

        guard let markerData = markerContents.data(using: .utf8) else {
            finishFailed("Could not encode FP32 verification marker.")
            return
        }
        do {
            try markerData.write(to: markerURL, options: .atomic)
            guard isCurrentOperation(id: operationID, pack: pack) else {
                return
            }
            guard !flag.isCancelled else {
                finishIdle()
                return
            }
            finishSucceeded(for: pack)
        } catch {
            guard isCurrentOperation(id: operationID, pack: pack) else { return }
            if flag.isCancelled {
                finishIdle()
            } else {
                finishFailed("Could not save FP32 verification: \(error.localizedDescription)")
            }
        }
    }

    func downloadModel(for pack: KokoroModelPack) async throws {
        if pack.requiresInt8SupportFiles, !isModelDownloaded(for: .int8V019) {
            let error = KokoroFP32InstallError.int8SupportMissing
            statusPack = pack
            status = .failed(error: error.localizedDescription)
            throw error
        }
        try await startDownload(for: pack)
    }

    public func downloadModel() async throws {
        try await downloadModel(for: .int8V019)
    }

    public func pause() {
        downloadTask?.suspend()
    }

    public func resume() {
        downloadTask?.resume()
    }

    public func cancel() {
        guard activeOperationPack != nil else {
            status = .idle
            return
        }

        cancellationFlag.cancel()
        // Keep the operation identity until its URLSession callback or detached
        // installer exits. A retry cannot start while an older worker still has
        // the destination directory open.
        status = .cancelling
        // The in-memory fence keeps current-process callbacks valid; removing
        // the durable record prevents a cancelled task or installer from being
        // adopted after a process termination.
        clearPersistedOperation()
        downloadTask?.cancel()
    }

    private func startDownload(for pack: KokoroModelPack) async throws {
        guard activeOperationPack == nil,
              KokoroInstallOperationStore.read(in: modelsRoot) == nil
        else {
            recoverPersistedOperationIfNeeded()
            restorePendingDownloadIfNeeded()
            throw KokoroFP32InstallError.operationInProgress
        }
        try ensureStorage(for: pack)

        if isModelDownloaded(for: pack) {
            statusPack = pack
            status = .completed
            return
        }

        let operationID = UUID()
        let flag = CancellationFlag()
        let task = urlSession.downloadTask(with: pack.downloadURL)
        task.taskDescription = Self.taskDescription(id: operationID, pack: pack)
        do {
            try persistOperation(id: operationID, pack: pack, phase: .downloading)
        } catch {
            statusPack = pack
            status = .failed(error: error.localizedDescription)
            throw error
        }
        self.downloadTask = task
        activeDownloadTaskIdentifier = task.taskIdentifier
        activeOperationID = operationID
        activeOperationPack = pack
        cancellationFlag = flag
        statusPack = pack
        status = .downloading(progress: 0)
        task.resume()
    }

    private func ensureStorage(for pack: KokoroModelPack) throws {
        let required = pack.reservedInstallBytes
        if let available = KokoroFP32Installer.availableBytes(at: modelsRoot) {
            if available < required {
                let error = KokoroFP32InstallError.notEnoughStorage(requiredBytes: required)
                statusPack = pack
                status = .failed(error: error.localizedDescription)
                throw error
            }
            return
        }

        // Fail closed for the large FP32 model if the volume cannot report
        // capacity. Int8 keeps the historical attributes-of-file-system check.
        if pack.requiresInt8SupportFiles {
            let error = KokoroFP32InstallError.notEnoughStorage(requiredBytes: required)
            statusPack = pack
            status = .failed(error: error.localizedDescription)
            throw error
        }

        let fm = FileManager.default
        let sysAttrs = try fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        if let freeSpace = sysAttrs[.systemFreeSize] as? NSNumber,
           freeSpace.int64Value < required {
            statusPack = pack
            status = .failed(error: "Not enough storage space. At least 300MB required.")
            throw NSError(
                domain: "TTSDownloadManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not enough storage space."]
            )
        }
    }

    private func isVerifiedPack(
        _ pack: KokoroModelPack,
        in modelDirectory: URL
    ) -> Bool {
        guard let markerFileName = pack.validationMarkerFileName,
              let expectedMarkerContents = pack.validationMarkerContents
        else {
            return false
        }

        let markerURL = modelDirectory.appendingPathComponent(markerFileName)
        guard (try? String(contentsOf: markerURL, encoding: .utf8)) == expectedMarkerContents,
              let markerValues = try? markerURL.resourceValues(
                  forKeys: [.contentModificationDateKey]
              ),
              let markerDate = markerValues.contentModificationDate,
              let contentFiles = try? KokoroRuntimeFingerprint.runtimeContentFiles(
                  modelFileName: pack.modelFileName,
                  in: modelDirectory
              )
        else {
            return false
        }

        let modificationDates = contentFiles.compactMap {
            (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        guard modificationDates.count == contentFiles.count,
              let newestContentDate = modificationDates.max()
        else {
            return false
        }
        return newestContentDate <= markerDate
    }

    private func finishIdle() {
        clearPersistedOperation()
        activeOperationPack = nil
        activeOperationID = nil
        activeDownloadTaskIdentifier = nil
        downloadTask = nil
        status = .idle
        finishBackgroundEventsIfPossible()
    }

    private func finishFailed(_ message: String) {
        clearPersistedOperation()
        activeOperationPack = nil
        activeOperationID = nil
        activeDownloadTaskIdentifier = nil
        downloadTask = nil
        status = .failed(error: message)
        finishBackgroundEventsIfPossible()
    }

    private func finishSucceeded(for pack: KokoroModelPack) {
        clearPersistedOperation()
        activeOperationPack = nil
        activeOperationID = nil
        activeDownloadTaskIdentifier = nil
        downloadTask = nil
        statusPack = pack
        status = .completed
        finishBackgroundEventsIfPossible()
    }

    private func finishBackgroundEventsIfPossible() {
        guard backgroundEventsDidFinish,
              activeOperationPack == nil,
              let completionHandler = backgroundEventsCompletionHandler
        else {
            return
        }
        backgroundEventsCompletionHandler = nil
        completionHandler()
    }

    private func isCurrentOperation(id: UUID, pack: KokoroModelPack) -> Bool {
        activeOperationID == id && activeOperationPack == pack
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? mutableURL.setResourceValues(values)
    }

    /// Preserves the URLSession download file before the system deletes it.
    private func preserveDownload(at location: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let preserved = modelsRoot.appendingPathComponent(
            ".incoming-\(UUID().uuidString)",
            isDirectory: false
        )
        try fm.moveItem(at: location, to: preserved)
        return preserved
    }

    private func finishFP32Download(
        from preserved: URL,
        operationID: UUID,
        flag: CancellationFlag
    ) {
        let int8Directory = modelDirectory(for: .int8V019)
        let destination = modelDirectory(for: .fp32V019)
        let spec = KokoroFP32Installer.Spec.official()
        Task.detached(priority: .utility) {
            do {
                try KokoroFP32Installer.install(
                    downloadedModel: preserved,
                    int8Directory: int8Directory,
                    destinationDirectory: destination,
                    spec: spec,
                    isCancelled: { flag.isCancelled }
                )
                await MainActor.run {
                    try? FileManager.default.removeItem(at: preserved)
                    guard self.isCurrentOperation(
                        id: operationID,
                        pack: .fp32V019
                    ) else { return }
                    guard !flag.isCancelled else {
                        // No retry can start while this operation is current, so
                        // this can only remove the just-installed FP32 directory.
                        try? FileManager.default.removeItem(at: destination)
                        self.finishIdle()
                        return
                    }
                    if self.isModelDownloaded(for: .fp32V019) {
                        self.finishSucceeded(for: .fp32V019)
                    } else {
                        self.finishFailed("FP32 install completed but verification failed.")
                        try? FileManager.default.removeItem(at: destination)
                    }
                }
            } catch {
                await MainActor.run {
                    try? FileManager.default.removeItem(at: preserved)
                    guard self.isCurrentOperation(
                        id: operationID,
                        pack: .fp32V019
                    ) else { return }
                    if flag.isCancelled ||
                        (error as? KokoroFP32InstallError) == .cancelled {
                        self.finishIdle()
                    } else {
                        self.finishFailed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func finishInt8Download(
        from preserved: URL,
        operationID: UUID,
        flag: CancellationFlag
    ) {
        let destination = modelDirectory
        Task.detached(priority: .utility) {
            do {
                let archiveDigest = try KokoroRuntimeFingerprint.sha256Hex(ofFile: preserved)
                if let expectedArchiveSHA256 = KokoroModelPack.int8V019.expectedArchiveSHA256,
                   archiveDigest != expectedArchiveSHA256 {
                    throw KokoroFP32InstallError.archiveDigestMismatch
                }
                try Self.installInt8Archive(
                    from: preserved,
                    into: destination,
                    isCancelled: { flag.isCancelled }
                )
                await MainActor.run {
                    try? FileManager.default.removeItem(at: preserved)
                    guard self.isCurrentOperation(id: operationID, pack: .int8V019) else { return }
                    guard !flag.isCancelled else {
                        // As above, the active-operation fence means this cannot
                        // delete a newer retry's Voice Pack.
                        try? FileManager.default.removeItem(at: destination)
                        self.finishIdle()
                        return
                    }
                    guard self.isModelDownloaded(for: .int8V019) else {
                        self.finishFailed("Extraction completed but verification failed.")
                        return
                    }
                    self.excludeFromBackup(destination)
                    self.finishSucceeded(for: .int8V019)
                }
            } catch {
                await MainActor.run {
                    try? FileManager.default.removeItem(at: preserved)
                    guard self.isCurrentOperation(id: operationID, pack: .int8V019) else { return }
                    if flag.isCancelled ||
                        (error as? KokoroFP32InstallError) == .cancelled {
                        self.finishIdle()
                    } else {
                        self.finishFailed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private nonisolated static func installInt8Archive(
        from archive: URL,
        into destination: URL,
        isCancelled: () -> Bool
    ) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stagingRoot = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        let staged = stagingRoot.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try throwIfCancelled(isCancelled)
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)
        let data = try Data(contentsOf: archive)
        try throwIfCancelled(isCancelled)
        let decompressedData = try BZip2.decompress(data: data)
        try throwIfCancelled(isCancelled)
        let entries = try TarContainer.open(container: decompressedData)

        for entry in entries {
            try throwIfCancelled(isCancelled)
            let relativePath = try archiveRelativePath(from: entry.info.name)
            guard !relativePath.isEmpty else { continue }
            let target = staged.appendingPathComponent(
                relativePath,
                isDirectory: entry.info.type == ContainerEntryType.directory
            )

            switch entry.info.type {
            case .directory:
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            case .regular:
                guard let fileData = entry.data else { throw CocoaError(.fileReadCorruptFile) }
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileData.write(to: target, options: Data.WritingOptions.atomic)
            default:
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        guard hasCompleteInt8Runtime(in: staged) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: staged,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    private nonisolated static func archiveRelativePath(from archivePath: String) throws -> String {
        let prefix = "kokoro-int8-en-v0_19/"
        if archivePath == String(prefix.dropLast()) { return "" }
        guard archivePath.hasPrefix(prefix) else { throw CocoaError(.fileReadCorruptFile) }
        let relative = String(archivePath.dropFirst(prefix.count))
        guard !relative.hasPrefix("/"),
              !relative.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return relative
    }

    private nonisolated static func hasCompleteInt8Runtime(in directory: URL) -> Bool {
        for fileName in KokoroModelPack.int8V019.requiredFileNames {
            let file = directory.appendingPathComponent(fileName)
            guard (try? KokoroRuntimeFingerprint.byteCount(of: file)) ?? 0 > 0 else { return false }
        }
        return KokoroRuntimeFingerprint.hasCompleteSupportFiles(in: directory)
    }

    private nonisolated static func throwIfCancelled(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw KokoroFP32InstallError.cancelled }
    }
}

extension TTSDownloadManager: @preconcurrency URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            guard adoptPersistedDownloadIfNeeded(from: downloadTask),
                  Self.isCurrentDownloadTask(
                callbackTaskIdentifier: downloadTask.taskIdentifier,
                activeTaskIdentifier: activeDownloadTaskIdentifier
            ),
                  totalBytesExpectedToWrite > 0,
                  case .downloading = status
            else {
                return
            }
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            status = .downloading(progress: progress)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        MainActor.assumeIsolated {
            guard adoptPersistedDownloadIfNeeded(from: downloadTask),
                  Self.isCurrentDownloadTask(
                callbackTaskIdentifier: downloadTask.taskIdentifier,
                activeTaskIdentifier: activeDownloadTaskIdentifier
            ),
                  let pack = activeOperationPack,
                  let operationID = activeOperationID
            else {
                return
            }

            guard !cancellationFlag.isCancelled else {
                finishIdle()
                return
            }

            var preserved: URL?
            do {
                let movedDownload = try preserveDownload(at: location)
                preserved = movedDownload
                try persistOperation(
                    id: operationID,
                    pack: pack,
                    phase: .installing,
                    preservedFileName: movedDownload.lastPathComponent
                )
            } catch {
                try? FileManager.default.removeItem(at: preserved ?? location)
                finishFailed(error.localizedDescription)
                return
            }
            guard let preserved else {
                finishFailed("The downloaded Voice Pack could not be preserved.")
                return
            }

            let flag = cancellationFlag
            self.downloadTask = nil
            activeDownloadTaskIdentifier = nil
            if pack.requiresInt8SupportFiles {
                status = .installing
                finishFP32Download(from: preserved, operationID: operationID, flag: flag)
            } else {
                status = .extracting
                finishInt8Download(from: preserved, operationID: operationID, flag: flag)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        MainActor.assumeIsolated {
            guard adoptPersistedDownloadIfNeeded(from: task),
                  Self.isCurrentDownloadTask(
                callbackTaskIdentifier: task.taskIdentifier,
                activeTaskIdentifier: activeDownloadTaskIdentifier
            ) else { return }
            if cancellationFlag.isCancelled {
                finishIdle()
            } else {
                finishFailed(error.localizedDescription)
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        MainActor.assumeIsolated {
            backgroundEventsDidFinish = true
            finishBackgroundEventsIfPossible()
        }
    }
}

/// Checked from the background installer without hopping to the main actor.
nonisolated final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
