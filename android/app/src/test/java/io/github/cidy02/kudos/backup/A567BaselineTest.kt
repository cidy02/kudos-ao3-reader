package io.github.cidy02.kudos.backup

import android.content.Context
import android.net.Uri
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.documentfile.provider.DocumentFile
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.PickedDocumentReader
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** One device: Room, stores, repositories and a fake SAF folder, every directory a measured disk root. */
class A567Rig : AutoCloseable {
    val context: Context = ApplicationProvider.getApplicationContext()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    var clock: Instant = Instant.parse("2026-06-26T12:00:00Z")
    val filesRoot: File = Files.createTempDirectory("a567-files").toFile()
    val settingsRoot: File = Files.createTempDirectory("a567-settings").toFile()
    val cacheRoot: File = Files.createTempDirectory("a567-cache").toFile()
    val safRoot: File = Files.createTempDirectory("a567-saf").toFile()
    val database: KudosDatabase = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
        .allowMainThreadQueries().build()
    val settings = SettingsRepository(PreferenceDataStoreFactory.create(
        scope = scope, produceFile = { File(settingsRoot, "settings.preferences_pb") }
    ))
    val workFiles = WorkFileStore(filesRoot.toPath())
    val fontFiles = FontFileStore(filesRoot.toPath())
    val gate = PersistenceGate()
    val repository = BackupRepository(
        database, workFiles, fontFiles, settings, gate,
        clock = { clock }, appVersion = "test", cacheDirectory = cacheRoot
    )
    val provider = FakeTempDocumentsProvider()
    val treeUri: Uri = provider.install(context, safRoot)
    val sync = SyncRepository(
        context = context, settingsRepository = settings, backupRepository = repository,
        workFileStore = workFiles, fontFileStore = fontFiles, persistenceGate = gate,
        clock = { clock }, scheduleBackgroundSync = {}
    )

    val diskRoots get() = listOf(filesRoot, settingsRoot, cacheRoot, safRoot)

    init {
        runBlocking {
            settings.updateSyncFolderUri(treeUri.toString())
            settings.updateSyncIsEnabled(true)
        }
    }

    fun kudosFolder(): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, treeUri)!!
        return root.findFile("KudosLibrary") ?: root.createDirectory("KudosLibrary")!!
    }

    fun writeChild(dir: DocumentFile, name: String, bytes: ByteArray) {
        val file = dir.findFile(name) ?: dir.createFile("application/json", name)!!
        context.contentResolver.openOutputStream(file.uri, "wt")!!.use { it.write(bytes) }
    }

    fun package_(bytes: ByteArray): KudosBackupPackage = BackupImporter.importV2Zip(zipOf(bytes), cacheRoot)

    override fun close() {
        database.close()
        scope.cancel()
        listOf(filesRoot, settingsRoot, cacheRoot, safRoot).forEach { it.deleteRecursively() }
    }

    companion object {
        fun zipOf(manifest: ByteArray, epubs: Map<String, ByteArray> = emptyMap()): ByteArray {
            val out = ByteArrayOutputStream()
            ZipOutputStream(out).use { zip ->
                zip.putNextEntry(ZipEntry(BackupPaths.MANIFEST)); zip.write(manifest); zip.closeEntry()
                epubs.forEach { (id, bytes) ->
                    zip.putNextEntry(ZipEntry("${BackupPaths.WORKS_DIRECTORY}/$id.epub")); zip.write(bytes); zip.closeEntry()
                }
            }
            return out.toByteArray()
        }

        /** A valid EPUB of about [bytes] bytes (incompressible text so the archive size follows). */
        fun epubOf(bytes: Int, seed: Int): ByteArray {
            val rnd = Random(seed)
            val html = buildString {
                while (length < bytes) append("<p>").append(String(CharArray(200) { ('a' + rnd.nextInt(26)) })).append("</p>\n")
            }
            return EpubBuilder.buildEpub("Asset $seed", html)
        }
    }
}

/**
 * A-567 P1, local part: baseline of every Android manifest entry point under Robolectric on the
 * desktop JVM ("JVM", not device). Opt-in: A567_OUT=<fragment file>. Optional A567_RUNS (default 3
 * measured after one warm-up) and A567_SIZES (comma MiB, default 1,4,8).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class A567BaselineTest {
    private class Row(val route: String, val axis: String, val size: String, val r: List<A567Run.Result>) {
        fun cells(): String {
            val m = { f: (A567Run.Result) -> Double -> "%.1f".format(A567Run.median(r.map(f))) }
            val wall = A567Run.medianL(r.map { it.wallMs })
            val stages = r.last().stages.entries.joinToString(", ") { "${it.key} ${it.value}" }.ifEmpty { "-" }
            return "| $route | $axis | $size | ${r.last().outcome} | $wall | ${m { it.peakHeapMiB }} | ${m { it.retainedMiB }} | " +
                "${m { it.diskHighMiB }} | $stages |"
        }
    }

    private val rows = mutableListOf<Row>()
    private val runs = (System.getenv("A567_RUNS") ?: "3").toInt()
    private val sizes = (System.getenv("A567_SIZES") ?: "1,4,8").split(",").map { it.trim().toLong() }
    private val mib = 1024L * 1024L

    /** One warm-up and [runs] measured runs; each on a fresh rig so no run sees another's state. */
    private fun case(route: String, axis: String, size: String, body: (A567Rig, A567Run) -> () -> String) {
        val results = mutableListOf<A567Run.Result>()
        repeat(1 + runs) { index ->
            A567Rig().use { rig ->
                val run = A567Run(rig.diskRoots)
                val measured = body(rig, run) // setup happens here, untimed
                val result = run.measure(measured)
                if (index > 0) results += result
            }
        }
        rows += Row(route, axis, size, results)
        println("A567 ${rows.last().cells()}")
    }

    private fun seedLocal(rig: A567Rig, bytes: Long) = runBlocking {
        val pack = rig.package_(A567Corpus.manifestBytesOfSize(bytes))
        rig.repository.importPackage(pack, BackupImportMode.RECONCILE)
    }

    @Test
    fun measure() {
        val out = System.getenv("A567_OUT")
        assumeTrue("A-567 P1 baseline is opt-in (A567_OUT)", out != null)
        for (s in sizes) {
            val bytes = s * mib
            // --- picked document (PickedDocumentReader, 32 MiB picker cap, 8 MiB manifest cap)
            case("picked.inspect", "incoming rows", "$s MiB") { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(bytes));
                { run.stage("inspect") {
                    PickedDocumentReader.inspect(ByteArrayInputStream(zip), zip.size.toLong(), "b.kudosbackup", rig.cacheRoot).isBackup.toString()
                } }
            }
            case("picked.confirm", "incoming rows", "$s MiB") { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(bytes));
                { run.stage("readBytes") { PickedDocumentReader.readBytes(ByteArrayInputStream(zip), zip.size.toLong()) }
                    .let { b -> run.stage("importV2Zip") { BackupImporter.importV2Zip(b, rig.cacheRoot).manifest.works.size.toString() } } }
            }
            // --- Settings preview / execute
            case("settings.preview", "incoming rows (local empty)", "$s MiB") { rig, run ->
                val pack = rig.package_(A567Corpus.manifestBytesOfSize(bytes));
                { run.stage("preview") { runBlocking { rig.repository.previewImport(pack).toString().take(40) } } }
            }
            case("settings.preview", "local rows (incoming 0.1 MiB)", "$s MiB") { rig, run ->
                seedLocal(rig, bytes)
                val pack = rig.package_(A567Corpus.manifestBytesOfSize(mib / 10));
                { run.stage("preview") { runBlocking { rig.repository.previewImport(pack).toString().take(40) } } }
            }
            for (mode in listOf(BackupImportMode.MERGE, BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
                case("settings.execute ${mode.name}", "incoming rows (local empty)", "$s MiB") { rig, run ->
                    val pack = rig.package_(A567Corpus.manifestBytesOfSize(bytes));
                    { run.stage("importPackage") { runBlocking { rig.repository.importPackage(pack, mode).toString().take(60) } } }
                }
                case("settings.execute ${mode.name}", "local rows (incoming 0.1 MiB)", "$s MiB") { rig, run ->
                    seedLocal(rig, bytes)
                    val pack = rig.package_(A567Corpus.manifestBytesOfSize(mib / 10));
                    { run.stage("importPackage") { runBlocking { rig.repository.importPackage(pack, mode).toString().take(60) } } }
                }
            }
            // --- ZIP import (decode + execute), axes: opaque value, assets
            case("zip.import REPLACE_LIBRARY", "incoming rows", "$s MiB") { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(bytes));
                { run.stage("importV2ZipBytes") { runBlocking { rig.repository.importV2ZipBytes(zip, BackupImportMode.REPLACE_LIBRARY).toString().take(40) } } }
            }
            case("zip.import RECONCILE", "opaque value (rows 0.5 MiB)", "$s MiB") { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(maxOf(bytes, mib), opaqueBytes = maxOf(bytes, mib) - mib / 2));
                { run.stage("importV2ZipBytes") { runBlocking { rig.repository.importV2ZipBytes(zip, BackupImportMode.RECONCILE).toString().take(40) } } }
            }
            case("zip.import RECONCILE", "assets (50 EPUBs, rows ~0.3 MiB)", "$s MiB") { rig, run ->
                val ids = (0 until 50).toSet()
                val manifest = java.io.ByteArrayOutputStream().also {
                    A567Corpus.writeManifest(it, works = 50, sessionsPerWork = 4, annotations = 50, epubWorkIds = ids)
                }.toByteArray()
                val epubs = ids.associate { A567Corpus.uuid(it + 1) to A567Rig.epubOf((bytes / 50).toInt(), it) }
                val zip = A567Rig.zipOf(manifest, epubs);
                { run.stage("importV2ZipBytes") { runBlocking { rig.repository.importV2ZipBytes(zip, BackupImportMode.RECONCILE).toString().take(40) } } }
            }
            // --- legacy v1 directory
            case("legacy directory import", "incoming rows", "$s MiB") { rig, run ->
                val dir = Files.createTempDirectory("a567-legacy").toFile()
                File(dir, BackupPaths.MANIFEST).writeBytes(A567Corpus.manifestBytesOfSize(bytes, version = 1))
                File(dir, BackupPaths.WORKS_DIRECTORY).mkdirs()
                File(dir, BackupPaths.FONTS_DIRECTORY).mkdirs();
                {
                    try {
                        val pack = run.stage("importV1Directory") { BackupImporter.importV1Directory(dir.toPath(), rig.cacheRoot) }
                        run.stage("importPackage") { runBlocking { rig.repository.importPackage(pack, BackupImportMode.RECONCILE).toString().take(40) } }
                    } finally {
                        dir.deleteRecursively()
                    }
                }
            }
            // --- exportV2Zip
            case("exportV2Zip", "local rows", "$s MiB seeded") { rig, run ->
                seedLocal(rig, bytes);
                { run.stage("exportV2Zip") { runBlocking { rig.repository.exportV2Zip().bytes.size.toString() } } }
            }
            // --- Folder Sync
            case("runSync live", "incoming rows", "$s MiB") { rig, run ->
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST, A567Corpus.manifestBytesOfSize(bytes));
                { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
            }
            case("runSync live", "opaque value (rows 0.5 MiB)", "$s MiB") { rig, run ->
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST,
                    A567Corpus.manifestBytesOfSize(maxOf(bytes, mib), opaqueBytes = maxOf(bytes, mib) - mib / 2));
                { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
            }
            case("runSync .bak (live truncated)", "incoming rows", "$s MiB") { rig, run ->
                val good = A567Corpus.manifestBytesOfSize(bytes)
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST, good.copyOf(good.size / 2))
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST_BACKUP, good);
                { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
            }
            case("runSync legacy (v3 manifest)", "incoming rows", "$s MiB") { rig, run ->
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST, A567Corpus.manifestBytesOfSize(bytes, version = 3));
                { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
            }
            for (copies in listOf(1, 4, 16)) {
                case("runSync live + conflict copies", "conflict copies x$copies (0.25 MiB each, live 0.25)", "${copies * 0.25} MiB") { rig, run ->
                    val kudos = rig.kudosFolder()
                    rig.writeChild(kudos, BackupPaths.MANIFEST, A567Corpus.manifestBytesOfSize(mib / 4))
                    for (c in 1..copies) {
                        val bytesC = java.io.ByteArrayOutputStream().also {
                            A567Corpus.writeManifest(it, works = A567Corpus.unitsFor(mib / 4), sessionsPerWork = 4,
                                annotations = A567Corpus.unitsFor(mib / 4), workOffset = c * 100_000)
                        }.toByteArray()
                        rig.writeChild(kudos, "manifest ($c).json", bytesC)
                    };
                    { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
                }
                if (s != sizes.first()) break
            }
            case("runSync upload + steady state", "local rows", "$s MiB seeded") { rig, run ->
                seedLocal(rig, bytes);
                {
                    // First run publishes (upload); second finds a live manifest: precommit reread, .bak copy, prune.
                    val first = run.stage("runSync#1 publish") { runBlocking { rig.sync.runSync().toString().take(30) } }
                    rig.clock = rig.clock.plusSeconds(60)
                    val second = run.stage("runSync#2 steady") { runBlocking { rig.sync.runSync().toString().take(30) } }
                    "$first / $second"
                }
            }
            // --- overlays (manual / folder-scoped / pending) and Replace aside recovery
            case("overlay store save/load/update", "opaque rows", "$s MiB") { rig, run ->
                val json = parseJsonObjectOrNull(A567Corpus.manifestBytesOfSize(bytes))!!
                val dir = rig.filesRoot.toPath()
                val manual = SyncLastManifestStore(dir)
                val folder = SyncLastManifestStore(dir, fileName = "folder-overlay.json")
                val pending = SyncLastManifestStore(dir, fileName = BackupRepository.PENDING_IMPORT_MANIFEST_FILE);
                {
                    run.stage("manual save") { manual.save(json) }
                    run.stage("folder-scoped save") { folder.save(json, folderUri = "content://tree/x") }
                    run.stage("pending save") { pending.save(json, clearStaleFolderTag = true) }
                    run.stage("manual load") { manual.load()!!.size }
                    run.stage("folder load") { folder.load()!!.size }
                    run.stage("pending merge+save") { pending.update { mergeImportedManifestJson(json, it) } }
                    run.stage("replace aside set/restore") { manual.setAside(); manual.restoreAside() }
                    run.stage("replace aside set/drop") { manual.setAside(); manual.dropAside() }
                    "ok"
                }
            }
        }
        // --- cap boundaries and above-cap outcomes of the real routes (cap rejections are outcomes)
        for ((label, size) in listOf("8 MiB - 1 KiB" to 8 * mib - 1024, "8 MiB + 1 MiB" to 9 * mib)) {
            case("cap: picked.inspect", "manifest", label) { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(size));
                { run.stage("inspect") { PickedDocumentReader.inspect(ByteArrayInputStream(zip), zip.size.toLong(), "b.kudosbackup", rig.cacheRoot).isBackup.toString() } }
            }
            case("cap: zip.import", "manifest", label) { rig, run ->
                val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(size));
                { run.stage("importV2ZipBytes") { runBlocking { rig.repository.importV2ZipBytes(zip, BackupImportMode.RECONCILE).toString().take(40) } } }
            }
            case("cap: runSync live", "manifest", label) { rig, run ->
                rig.writeChild(rig.kudosFolder(), BackupPaths.MANIFEST, A567Corpus.manifestBytesOfSize(size));
                { run.stage("runSync") { runBlocking { rig.sync.runSync().toString().take(60) } } }
            }
        }
        case("cap: picker 32 MiB", "assets", "33 MiB archive") { rig, run ->
            val zip = A567Rig.zipOf(A567Corpus.manifestBytesOfSize(mib), mapOf(A567Corpus.uuid(1) to A567Rig.epubOf((32 * mib).toInt(), 1)));
            { run.stage("readBytes") { PickedDocumentReader.readBytes(ByteArrayInputStream(zip), zip.size.toLong()).size.toString() } }
        }
        val header = "| route | axis | size | outcome | wall ms (median) | heap peak MiB (median, upper bound) | retained MiB after GC | temp disk high-water MiB | stage ms (last run) |\n" +
            "|---|---|---|---|---|---|---|---|---|\n"
        File(out!!).writeText(header + rows.joinToString("\n") { it.cells() } + "\n")
    }
}
