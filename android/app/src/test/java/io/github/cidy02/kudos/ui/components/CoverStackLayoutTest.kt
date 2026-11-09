package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class CoverStackLayoutTest {
    private val sizes = listOf(
        CoverStackLayout.Size(48, 48),       // Queue organizer row
        CoverStackLayout.Size(52, 52),       // Home queue row
        CoverStackLayout.Size(64, 64),       // 64dp stack
        CoverStackLayout.Size(72, 72),       // Queue card
        CoverStackLayout.Size(76, 76),       // Collection header
        CoverStackLayout.Size(88, 120),      // New queue preview
        CoverStackLayout.Size(96, 96),       // Queue page header
        CoverStackLayout.Size(150, 140),     // Spec collection card
        CoverStackLayout.Size(164, 153),     // App collection card at scale 1
        CoverStackLayout.Size(164, 104),     // Wide queue card
        CoverStackLayout.Size(343, 320),     // Collection card at AX5
        CoverStackLayout.Size(343, 217.5),   // Queue card at AX5
        CoverStackLayout.Size(120, 112),     // Narrow pane grid
        CoverStackLayout.Size(30, 30),
        CoverStackLayout.Size(300, 40)
    )

    private val degenerateSizes = listOf(
        CoverStackLayout.Size(10, 100),
        CoverStackLayout.Size(20, 200),
        CoverStackLayout.Size(1, 1)
    )

    private fun isInside(rect: CoverStackLayout.Rect, bounds: CoverStackLayout.Rect): Boolean {
        val epsilon = 0.01
        return rect.minX >= bounds.minX - epsilon &&
            rect.minY >= bounds.minY - epsilon &&
            rect.maxX <= bounds.maxX + epsilon &&
            rect.maxY <= bounds.maxY + epsilon &&
            rect.width >= 0.0 &&
            rect.height >= 0.0
    }

    @Test
    fun everyCardStaysInsideItsFrameForOneToFiveCovers() {
        for (kind in CoverStackKind.entries) {
            for (size in sizes + degenerateSizes) {
                val frame = CoverStackLayout.Rect(0.0, 0.0, size.width, size.height)
                for (covers in 1..5) {
                    val layout = CoverStackLayout(kind = kind, size = size, backCount = covers - 1)
                    assertTrue("$kind $size $covers: front", isInside(layout.front, frame))
                    for (back in layout.backs) {
                        assertTrue("$kind $size $covers: $back", isInside(back.drawnBounds, frame))
                    }
                    layout.ribbon?.let { ribbon ->
                        val face = CoverStackLayout.Rect(0.0, 0.0, layout.front.width, layout.front.height)
                        assertTrue("$kind $size: tab", isInside(ribbon, face))
                    }
                }
            }
        }
    }

    @Test
    fun ordinaryFramesKeepUpToTwoCoversBehind() {
        for (kind in CoverStackKind.entries) {
            for (size in sizes) {
                assertEquals(0, CoverStackLayout(kind = kind, size = size, backCount = 0).backs.size)
                assertEquals(1, CoverStackLayout(kind = kind, size = size, backCount = 1).backs.size)
                assertEquals(2, CoverStackLayout(kind = kind, size = size, backCount = 2).backs.size)
                assertEquals(2, CoverStackLayout(kind = kind, size = size, backCount = 4).backs.size)
            }
        }
    }

    @Test
    fun queueStacksCoversStraightUpBehindTheFront() {
        val layout = CoverStackLayout(
            kind = CoverStackKind.Queue,
            size = CoverStackLayout.Size(96, 96),
            backCount = 3
        )
        assertEquals(2, layout.backs.size)

        var nearer = layout.front
        for ((index, back) in layout.backs.withIndex()) {
            assertEquals(0.0, back.rotation, 0.0)
            assertTrue(back.frame.minY < nearer.minY)
            assertTrue(back.frame.width < nearer.width)
            assertEquals(layout.front.midX, back.frame.midX, 0.001)
            assertEquals(0.12 * (index + 1), back.dimming, 0.0001)
            nearer = back.frame
        }
        assertEquals(0.0, layout.backs.last().frame.minY, 0.001)
        assertEquals(96.0, layout.front.maxY, 0.001)
    }

    @Test
    fun collectionTiltsEachCardFurtherBehindTheFront() {
        val layout = CoverStackLayout(
            kind = CoverStackKind.Collection,
            size = CoverStackLayout.Size(150, 140),
            backCount = 3
        )
        assertEquals(listOf(5.0, 10.0), layout.backs.map { it.rotation })
        assertEquals(listOf(0.1, 0.2), layout.backs.map { it.dimming })
        assertEquals(0.0, layout.front.minX, 0.0)
        assertEquals(140.0, layout.front.height, 0.0)
        assertEquals(100.8, layout.front.width, 0.01)
        for (back in layout.backs) {
            assertTrue(back.drawnBounds.maxX > layout.front.maxX)
            assertEquals(140.0, back.drawnBounds.maxY, 0.01)
        }
    }

    @Test
    fun smallStacksOmitTheCornerTabIncludingAtSixtyFourDp() {
        assertNull(CoverStackLayout(kind = CoverStackKind.Queue, size = CoverStackLayout.Size(48, 48), backCount = 2).ribbon)
        assertNull(CoverStackLayout(kind = CoverStackKind.Queue, size = CoverStackLayout.Size(64, 64), backCount = 2).ribbon)
        assertNull(CoverStackLayout(kind = CoverStackKind.Collection, size = CoverStackLayout.Size(64, 64), backCount = 2).ribbon)
        assertNull(CoverStackLayout(kind = CoverStackKind.Queue, size = CoverStackLayout.Size(72, 72), backCount = 2).ribbon)
        assertNotNull(CoverStackLayout(kind = CoverStackKind.Queue, size = CoverStackLayout.Size(88, 120), backCount = 0).ribbon)
        assertNotNull(CoverStackLayout(kind = CoverStackKind.Queue, size = CoverStackLayout.Size(96, 96), backCount = 2).ribbon)
        assertNotNull(CoverStackLayout(kind = CoverStackKind.Collection, size = CoverStackLayout.Size(150, 140), backCount = 0).ribbon)
    }

    @Test
    fun queueFrontKeepsTheDefaultCoverAspect() {
        val layout = CoverStackLayout(
            kind = CoverStackKind.Queue,
            size = CoverStackLayout.Size(72, 72),
            backCount = 2
        )
        assertTrue(abs(layout.front.width / layout.front.height - CoverStackLayout.coverAspect) < 0.001)
        assertEquals(36.0, layout.front.midX, 0.001)
    }
}
