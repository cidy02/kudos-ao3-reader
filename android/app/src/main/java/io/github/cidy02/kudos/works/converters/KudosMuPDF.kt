package io.github.cidy02.kudos.works.converters

/**
 * Kotlin face of the MuPDF structured-text shim (iOS `KudosMuPDF`).
 *
 * Only strings cross the JNI boundary — MuPDF's C API and its manual reference
 * counting stay on the native side.
 *
 * [isAvailable] is false when `libkudosmupdf.so` isn't in the APK. That is a
 * real state, not a defect: `jniLibs/` is deliberately not committed (the
 * library is AGPL-3.0 and built locally by `android/Scripts/build-mupdf.sh`),
 * so a checkout that hasn't run that script still builds and runs — PDF import
 * simply falls back to refusing honestly, exactly as it did before MuPDF.
 */
object KudosMuPDF {

    val isAvailable: Boolean by lazy {
        runCatching { System.loadLibrary("kudosmupdf") }.isSuccess
    }

    /**
     * One entry per page, each holding that page's paragraphs in reading order.
     *
     * A paragraph is one MuPDF structured-text *block*, its lines joined with a
     * single space — those lines are wrapped display lines, not sentences.
     *
     * Null when the document can't be opened, so the caller can fall back.
     */
    fun paragraphsPerPage(path: String): List<List<String>>? {
        if (!isAvailable) return null
        return runCatching { nativeParagraphsPerPage(path)?.map { it.toList() } }.getOrNull()
    }

    /**
     * One entry per page, each holding that page's *lines* — not paragraphs.
     *
     * Needed for the calibre/FanFicFare metadata page, whose `Label: value` rows
     * have to be read one line at a time. Feeding it assembled paragraphs merges
     * those rows into one blob and makes the parser read `Storylink:` as part of
     * `Story:`'s value — the exact failure `CalibreMetadata`'s longest-label-first
     * matching also guards against.
     */
    fun linesPerPage(path: String): List<List<String>>? {
        if (!isAvailable) return null
        return runCatching { nativeLinesPerPage(path)?.map { it.toList() } }.getOrNull()
    }

    @JvmStatic private external fun nativeParagraphsPerPage(path: String): Array<Array<String>>?
    @JvmStatic private external fun nativeLinesPerPage(path: String): Array<Array<String>>?
}
