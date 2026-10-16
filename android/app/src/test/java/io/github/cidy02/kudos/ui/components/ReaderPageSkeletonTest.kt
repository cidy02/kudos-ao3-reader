package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderPageSkeletonTest {
    private fun renderedHeight(paragraphs: List<List<Float?>>): Float =
        ReaderPageSkeletonLayout.headingHeight + 4 + paragraphs.sumOf {
            (ReaderPageSkeletonLayout.paragraphSpacing + ReaderPageSkeletonLayout.paragraphHeight(it.size)).toDouble()
        }.toFloat()

    @Test fun fillNeverOverflowsItsBudget() {
        for (height in 120..1400 step 37) {
            assertTrue("overflow at $height", renderedHeight(ReaderPageSkeletonLayout.paragraphs(height.toFloat())) <= height)
        }
    }

    @Test fun tallPageIsFilledWithProseShapedParagraphs() {
        val paragraphs = ReaderPageSkeletonLayout.paragraphs(700f)
        assertTrue(paragraphs.size >= 5)
        val slack = ReaderPageSkeletonLayout.paragraphHeight(1) + ReaderPageSkeletonLayout.paragraphSpacing
        assertTrue(renderedHeight(paragraphs) > 700 - slack - ReaderPageSkeletonLayout.paragraphSpacing)
        paragraphs.forEach { widths ->
            assertTrue(widths.last()?.isFinite() == true)
            assertTrue(widths.dropLast(1).all { it == null })
        }
    }

    @Test fun tinyAreaStillHasAWireframeForTheClippedView() {
        listOf(0f, 1f, 20f, 60f).forEach {
            assertTrue(ReaderPageSkeletonLayout.paragraphs(it).isNotEmpty())
        }
    }
}
