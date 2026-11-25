package io.github.cidy02.kudos.backup

import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * A-566 measurement. Not part of the gate (slow): set A566_OUT=<table file> and run
 * `./gradlew :app:testDebugUnitTest --tests '*ManifestMemoryBenchmarkTest*' -i`.
 * Peak = the smallest -Xmx (8 MiB steps, SerialGC so garbage is collected before OOM) a child JVM
 * completes the scenario in; the scenarios are those in [ManifestMemoryProbe]. Sizes above the current
 * BackupLimits.MAX_MANIFEST_BYTES need it raised for the run (the read path rejects them).
 */
class ManifestMemoryBenchmarkTest {
    private fun completes(xmxMib: Int, scenario: String, file: File, extra: String? = null): Boolean {
        val java = File(System.getProperty("java.home"), "bin/java").path
        val process = ProcessBuilder(
            java, "-XX:+UseSerialGC", "-Xmx${xmxMib}m", "-cp", System.getProperty("java.class.path"),
            "io.github.cidy02.kudos.backup.ManifestMemoryProbe", scenario, file.path, *listOfNotNull(extra).toTypedArray()
        ).redirectErrorStream(true).redirectOutput(File("/dev/null")).start()
        return process.waitFor() == 0
    }

    private fun minimumHeapMib(scenario: String, file: File): Int {
        var low = 8
        var high = 4096
        while (high - low > 8) {
            val mid = (low + high) / 2
            if (completes(mid, scenario, file)) high = mid else low = mid
        }
        return high
    }

    @Test
    fun measure() {
        val out = System.getenv("A566_OUT")
        assumeTrue("A-566 measurement is opt-in (A566_OUT)", out != null)
        val dir = File(System.getProperty("java.io.tmpdir"), "a566").apply { mkdirs() }
        val rows = StringBuilder("| manifest MiB | import | sync | sync + pending import |\n|---|---|---|---|\n")
        for (mib in listOf(1, 4, 8, 16, 32, 64)) {
            val file = File(dir, "m$mib.json")
            check(completes(3072, "gen", file, (mib * 1024L * 1024L).toString()))
            val cells = listOf("import", "sync", "syncPending").map { "${minimumHeapMib(it, file)} MiB" }
            rows.append("| $mib (actual ${"%.2f".format(file.length() / 1048576.0)}) | ${cells.joinToString(" | ")} |\n")
            println("A566 $rows")
        }
        File(out).writeText(rows.toString())
    }
}
