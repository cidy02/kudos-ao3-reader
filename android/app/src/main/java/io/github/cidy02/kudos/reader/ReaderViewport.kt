package io.github.cidy02.kudos.reader

import kotlin.math.roundToInt

/** Transient rendered resource metrics. Never stored in a work or backup. */
data class ReaderViewport(
    val spineIndex: Int,
    val page: Int,
    val pageCount: Int,
    /** Scrolled mode: actual offset, visible extent and full resource extent. */
    val scrollOffset: Double? = null,
    val scrollExtent: Double? = null,
    val scrollRange: Double? = null
) {
    companion object {
        fun scrolled(spineIndex: Int, offset: Double, extent: Double, range: Double): ReaderViewport? {
            if (!offset.isFinite() || !extent.isFinite() || !range.isFinite() ||
                offset < 0 || extent <= 0 || range <= 0
            ) return null
            // iOS's swipe-scale readout rounds both measurements. A displayed
            // last page is not itself a scrolled end; completion uses the extent.
            val count = (range / extent).roundToInt().coerceAtLeast(1)
            val page = ((offset / extent).roundToInt() + 1).coerceIn(1, count)
            return ReaderViewport(spineIndex, page, count, offset, extent, range)
        }
    }
}
