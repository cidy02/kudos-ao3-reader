import Foundation

/// What the app is actually keeping on this device, in bytes and in counts.
///
/// Spec 1ac states four figures under "Stored on this device" and then offers to
/// clear them. A privacy screen that says "downloads take up space" without
/// saying how much is asking the reader to take it on trust, which is the one
/// thing this screen exists not to do — so the numbers are measured rather than
/// estimated, and the screen shows what the measurement found even when that is
/// zero.
nonisolated struct LocalStorageFootprint: Sendable, Equatable {
    /// `Storage.worksDirectory` — the EPUBs a reader can open offline.
    var downloadedWorkBytes: Int64 = 0
    /// `Storage.originalsDirectory` — the bytes a converted import arrived as,
    /// kept verbatim because a redistributed work is often the last copy left.
    /// Counted separately from the EPUB rather than folded into it: they are
    /// freed by different actions, so one figure covering both would be a number
    /// no button can move.
    var preservedOriginalBytes: Int64 = 0
    /// `Storage.fontsDirectory` — fonts the reader imported themselves.
    var importedFontBytes: Int64 = 0
    /// The evictable caches: scraped AO3 metadata and the reader's unzip scratch.
    /// Grouped because the OS may purge either at any time, so the distinction
    /// between them is not one the reader can act on.
    var cacheBytes: Int64 = 0

    var totalBytes: Int64 {
        downloadedWorkBytes + preservedOriginalBytes + importedFontBytes + cacheBytes
    }

    /// The spec's `412 MB`. `.file` rather than `.memory` so the units match
    /// what iOS Settings reports for the same bytes.
    static func formatted(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

/// Measures `LocalStorageFootprint` by walking the app's own directories.
///
/// `nonisolated` and `async`: this is a filesystem walk over a directory that
/// can hold hundreds of EPUBs, and the screen that shows it is a settings page
/// the reader opened expecting it to appear immediately. Running it on the main
/// actor would stutter the push animation on exactly the libraries where the
/// figure matters most.
nonisolated enum LocalDataFootprintScanner {
    static func measure() async -> LocalStorageFootprint {
        await Task.detached(priority: .utility) {
            LocalStorageFootprint(
                downloadedWorkBytes: directorySize(of: Storage.worksDirectory),
                preservedOriginalBytes: directorySize(of: Storage.originalsDirectory),
                importedFontBytes: directorySize(of: Storage.fontsDirectory),
                cacheBytes: directorySize(of: Storage.metadataCacheDirectory)
                    + directorySize(of: readerScratchDirectory)
            )
        }.value
    }

    /// The parent of every per-work `Storage.readerDirectory(for:)`. Built here
    /// rather than added to `Storage` because nothing else needs the parent —
    /// production code only ever addresses one work's scratch at a time.
    private static var readerScratchDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Reader", isDirectory: true)
    }

    /// Recursive byte total for one directory, skipping anything unreadable.
    ///
    /// Reports **allocated** size where the filesystem gives it, falling back to
    /// logical size: a directory of small files occupies more than the sum of
    /// their lengths, and the figure this screen offers to free is the one the
    /// device's storage settings would also show.
    private static func directorySize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            if let allocated = values.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let logical = values.fileSize {
                total += Int64(logical)
            }
        }
        return total
    }
}
