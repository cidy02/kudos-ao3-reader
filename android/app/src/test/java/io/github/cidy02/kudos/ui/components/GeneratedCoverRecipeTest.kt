package io.github.cidy02.kudos.ui.components

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import java.text.BreakIterator
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class GeneratedCoverRecipeTest {
    private val jvmGraphemeCounter: (String) -> Int = { text ->
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        var graphemes = 0
        while (iterator.next() != BreakIterator.DONE) graphemes += 1
        graphemes
    }
    private lateinit var productionGraphemeCounter: (String) -> Int

    @Before
    fun installJvmGraphemeCounter() {
        productionGraphemeCounter = GeneratedCoverRecipe.graphemeCounter
        GeneratedCoverRecipe.graphemeCounter = jvmGraphemeCounter
    }

    @After
    fun restoreGraphemeCounter() {
        GeneratedCoverRecipe.graphemeCounter = productionGraphemeCounter
    }

    @Test
    fun productionGraphemeCounterSelectsAndroidIcuAndNotJvmCounter() {
        assertSame(GeneratedCoverRecipe.AndroidIcuGraphemeCounter, productionGraphemeCounter)
        assertNotSame(jvmGraphemeCounter, productionGraphemeCounter)
        // Pure JVM unit tests lack Robolectric shadows, so invoking the production counter
        // directly proves it targets Android's android.icu.text.BreakIterator stub rather than
        // silently using java.text.BreakIterator.
        val stubFailure = runCatching { productionGraphemeCounter("A") }.exceptionOrNull()
        assertTrue(
            "Expected production counter to invoke Android ICU, got $stubFailure",
            stubFailure is RuntimeException
        )
    }

    @Test
    fun fnv1aHashMatchesSwift() {
        val expected = listOf(
            "" to 2_166_136_261u,
            "a" to 3_826_002_220u,
            "author:fogandlamplight" to 680_142_949u,
            "fine:1001" to 1_781_545_991u,
            "series-kind:77" to 1_850_416_515u,
            "source:The Brontës" to 2_741_367_937u,
            "fandom:Jane Eyre" to 4_036_158_255u,
            "collection:00000000-0000-0000-0000-000000000077" to 3_261_677_827u,
            "work:Salt & Starlight|wrenfield" to 4_067_641_358u,
            "emoji:✨📚" to 3_874_962_677u
        )
        for ((input, hash) in expected) {
            assertEquals("Mismatch for $input", hash, GeneratedCoverRecipe.hash(input))
        }
    }

    @Test
    fun fandomLabelUsesBareFandomNameAndDeduplicates() {
        val doctor = GeneratedCoverRecipe.create(
            id = 1L,
            title = "Sodium Lights",
            author = "a",
            fandoms = listOf("Doctor Who (2005)")
        )
        val frozen = GeneratedCoverRecipe.create(
            id = 2L,
            title = "Winter Garden",
            author = "b",
            fandoms = listOf("Frozen (Disney Movies)")
        )
        val media = GeneratedCoverRecipe.create(
            id = 3L,
            title = "T",
            author = "c",
            fandoms = listOf("Avatar: The Last Airbender - All Media Types")
        )
        assertEquals("Doctor Who", doctor.fandom)
        assertEquals("Frozen", frozen.fandom)
        assertEquals("Avatar: The Last Airbender", media.fandom)

        // Two tags for one fandom: one name, one colour (commit 48aac1f0a).
        val twice = GeneratedCoverRecipe.create(
            id = 4L,
            title = "T",
            author = "d",
            fandoms = listOf("Doctor Who (2005)", "Doctor Who")
        )
        assertEquals("Doctor Who", twice.fandom)
        assertEquals(1, twice.hues.size)
        assertNotEquals(GeneratedCoverRecipe.Ground.CROSSOVER, twice.ground)
    }

    @Test
    fun referenceShelf() {
        data class Golden(
            val id: Long,
            val title: String,
            val author: String,
            val fandom: String,
            val words: Int,
            val done: Boolean,
            val year: Int,
            val tags: List<String>,
            val series: Long?,
            val part: Int,
            val motif: String,
            val hue: Int,
            val lightness: Double,
            val ground: GeneratedCoverRecipe.Ground,
            val spot: Int,
            val rotation: Double,
            val scale: Double,
            val lineWidth: Double,
            val opacity: Double
        )

        val cases = listOf(
            Golden(
                1001L, "The Long Frost", "fogandlamplight", "Sherlock Holmes", 92_000, true, 2019,
                listOf("Slow Burn", "Angst"), 77L, 1,
                "sigil", 55, 0.40, GeneratedCoverRecipe.Ground.GRADIENT, 1, 284.36, 1.03, 1.01, 0.47
            ),
            Golden(
                1002L, "Thaw", "fogandlamplight", "Sherlock Holmes", 41_000, true, 2020,
                listOf("Fluff"), 77L, 2,
                "sigil", 73, 0.41, GeneratedCoverRecipe.Ground.GRADIENT, 1, 284.36, 1.03, 1.01, 0.47
            ),
            Golden(
                1004L, "The Lamplight Cases", "gaslitgrey", "Sherlock Holmes", 30_000, true, 2016,
                listOf("Case Fic"), 91L, 1,
                "petals", 55, 0.37, GeneratedCoverRecipe.Ground.SPLIT, 0, 310.17, 0.96, 1.36, 0.45
            ),
            Golden(
                1007L, "A Study in Small Hours", "baskervilled", "Sherlock Holmes", 3_100, true, 2023,
                listOf("Fluff", "Domestic Fluff"), null, 0,
                "petals", 55, 0.43, GeneratedCoverRecipe.Ground.SOLID, 0, 64.92, 1.15, 1.29, 0.4
            ),
            Golden(
                1008L, "Salt & Starlight", "wrenfield", "Original Work", 118_000, false, 2024,
                listOf("Fantasy", "Magic"), null, 0,
                "rings", 220, 0.44, GeneratedCoverRecipe.Ground.BAND, 1, 57.36, 1.11, 1.1, 0.48
            ),
            Golden(
                1009L, "Letters Never Sent", "marginalia", "Persuasion", 18_000, true, 2018,
                listOf("Romance", "Angst"), null, 0,
                "orbit", 141, 0.39, GeneratedCoverRecipe.Ground.BAND, 0, 143.39, 1.02, 1.28, 0.5
            )
        )

        for (c in cases) {
            val recipe = GeneratedCoverRecipe.create(
                id = c.id,
                title = c.title,
                author = c.author,
                fandoms = listOf(c.fandom),
                tags = c.tags,
                words = c.words,
                complete = c.done,
                seriesID = c.series,
                part = c.part,
                postedYear = c.year
            )
            assertEquals("motif for ${c.id}", c.motif, recipe.motif)
            assertEquals("hue for ${c.id}", c.hue, recipe.hues[0])
            assertEquals("lightness for ${c.id}", c.lightness, recipe.lightness, 0.0001)
            assertEquals("ground for ${c.id}", c.ground, recipe.ground)
            assertEquals("placement for ${c.id}", c.spot, recipe.placement)
            assertEquals("rotation for ${c.id}", c.rotation, recipe.rotation, 0.0001)
            assertEquals("scale for ${c.id}", c.scale, recipe.scale, 0.0001)
            assertEquals("lineWidth for ${c.id}", c.lineWidth, recipe.lineWidth, 0.0001)
            assertEquals("opacity for ${c.id}", c.opacity, recipe.opacity, 0.0001)
            assertEquals("closedRing for ${c.id}", c.done, recipe.closedRing)
        }
    }

    @Test
    fun inputsChooseOnlyTheirAssignedParts() {
        val base = GeneratedCoverRecipe.create(
            id = 1008L,
            title = "Salt & Starlight",
            author = "wrenfield",
            fandoms = listOf("Original Work"),
            words = 8_000,
            complete = false
        )
        assertEquals(
            base,
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Original Work"),
                words = 8_000,
                complete = false
            )
        )
        val otherID = GeneratedCoverRecipe.create(
            id = 1009L,
            title = "Salt & Starlight",
            author = "wrenfield",
            fandoms = listOf("Original Work"),
            words = 8_000,
            complete = false
        )
        assertNotEquals(base.shapeSeed, otherID.shapeSeed)
        assertEquals(base.hues, otherID.hues)
        assertEquals(0, base.tier)
        assertEquals(
            3,
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Original Work"),
                words = 150_000
            ).tier
        )
        assertTrue(
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Original Work"),
                complete = true
            ).closedRing
        )
        assertEquals(
            GeneratedCoverRecipe.Ground.CROSSOVER,
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Sherlock Holmes", "Jane Eyre")
            ).ground
        )
        assertEquals(
            "rings",
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Original Work"),
                tags = listOf("Fantasy")
            ).motif
        )
        assertNotEquals(
            "rings",
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Original Work"),
                tags = listOf("Angst")
            ).motif
        )
        assertNotEquals(
            base.hues,
            GeneratedCoverRecipe.create(
                id = 1008L,
                title = "Salt & Starlight",
                author = "wrenfield",
                fandoms = listOf("Persuasion")
            ).hues
        )
        val shuffled = GeneratedCoverRecipe.create(
            id = 1008L,
            title = "Salt & Starlight",
            author = "wrenfield",
            fandoms = listOf("Original Work"),
            salt = 1
        )
        assertNotEquals(base.shapeSeed, shuffled.shapeSeed)
        assertNotEquals(base.motif, shuffled.motif)
    }

    @Test
    fun seriesKeepsItsLook() {
        val first = GeneratedCoverRecipe.create(
            id = 1001L,
            title = "The Long Frost",
            author = "fogandlamplight",
            fandoms = listOf("Sherlock Holmes"),
            seriesID = 77L,
            part = 1
        )
        val second = GeneratedCoverRecipe.create(
            id = 1002L,
            title = "Thaw",
            author = "another author",
            fandoms = listOf("Sherlock Holmes"),
            seriesID = 77L,
            part = 2
        )
        assertEquals(first.motif, second.motif)
        assertEquals(first.ground, second.ground)
        assertEquals(first.rotation, second.rotation, 0.0001)
        assertEquals(first.scale, second.scale, 0.0001)
        assertEquals(first.hues[0] + 18, second.hues[0])
    }

    @Test
    fun subtitlesAndFirstAuthor() {
        for (title in listOf("The Work (A Subtitle)", "The Work [A Subtitle]")) {
            val recipe = GeneratedCoverRecipe.create(
                id = 42L,
                title = title,
                author = "First, Second",
                fandoms = listOf("Original Work")
            )
            assertEquals("The Work", recipe.title)
            assertTrue(recipe.subtitle.isNotEmpty())
            assertEquals(2, recipe.placement)
        }
        val orTitle = GeneratedCoverRecipe.create(
            id = 42L,
            title = "The Work; or, A Subtitle",
            author = "First",
            fandoms = listOf("Original Work")
        )
        assertEquals("The Work", orTitle.title)
        assertEquals("A Subtitle", orTitle.subtitle)

        val onlyParentheses = GeneratedCoverRecipe.create(
            id = 42L,
            title = "(Only)",
            author = "First",
            fandoms = listOf("Original Work")
        )
        assertEquals("(Only)", onlyParentheses.title)
        assertTrue(onlyParentheses.subtitle.isEmpty())

        val first = GeneratedCoverRecipe.create(
            id = 42L,
            title = "The Work",
            author = "First",
            fandoms = listOf("Original Work")
        )
        val joined = GeneratedCoverRecipe.create(
            id = 42L,
            title = "The Work",
            author = "First, Second",
            fandoms = listOf("Original Work")
        )
        assertEquals(first.motif, joined.motif)
        assertEquals(first.titleStyle, joined.titleStyle)
    }

    @Test
    fun unrelatedTagsDoNotChangeRecipe() {
        val base = GeneratedCoverRecipe.create(
            id = 42L,
            title = "The Work",
            author = "First",
            fandoms = listOf("Original Work"),
            tags = listOf("Fantasy")
        )
        val extra = GeneratedCoverRecipe.create(
            id = 42L,
            title = "The Work",
            author = "First",
            fandoms = listOf("Original Work"),
            tags = listOf("Fantasy", "Coffee Shops & Cafés")
        )
        assertEquals(base, extra)
    }

    @Test
    fun threePartsShareSeriesArtAndBuildersAgree() {
        val recipes = (1..3).map { part ->
            GeneratedCoverRecipe.create(
                id = 42L + part,
                title = "Part $part",
                author = "Different $part",
                fandoms = listOf("Original Work"),
                tags = if (part == 2) listOf("Angst") else listOf("Fluff"),
                seriesID = 77L,
                part = part
            )
        }
        assertTrue(recipes.all { it.motif == recipes[0].motif })
        assertTrue(recipes.all { it.ground == recipes[0].ground })
        assertTrue(recipes.all { it.rotation == recipes[0].rotation })

        val saved = SavedWork(
            title = "Part 2",
            author = "First, Second",
            ao3WorkID = 44,
            workFandoms = listOf("Original Work"),
            workTags = listOf("Angst"),
            ao3SeriesID = 77,
            seriesPosition = 2
        )
        val listed = AO3WorkSummary(
            id = 44L,
            title = "Part 2",
            authors = listOf("First", "Second"),
            fandoms = listOf("Original Work"),
            rating = "",
            warnings = emptyList(),
            categories = emptyList(),
            freeforms = listOf("Angst"),
            wordCount = saved.wordCount,
            isComplete = saved.isComplete,
            seriesUrl = "https://archiveofourown.org/series/77",
            seriesPosition = 2
        )
        assertEquals(saved.generatedCoverRecipe(), listed.generatedCoverRecipe())
    }

    @Test
    fun crossoverBandsHaveRequestedArea() {
        val height = 112.0 * 1.42
        fun squared(value: Double): Double = max(value, 0.0) * max(value, 0.0)
        for (fraction in listOf(0.6, 1.0 / 3.0, 2.0 / 3.0)) {
            val cut = GeneratedCoverMath.crossoverCut(fraction, height)
            val area = (squared(cut) - squared(cut - 112.0) - squared(cut - height) +
                squared(cut - 112.0 - height)) / 2.0
            assertTrue(abs(area / (112.0 * height) - fraction) < 0.0001)
        }
    }

    @Test
    fun whiteContrastAcrossGroundRange() {
        assertEquals(0.86, GeneratedCoverMath.BYLINE_OPACITY, 0.0001)
        assertEquals(0.88, GeneratedCoverMath.FANDOM_OPACITY, 0.0001)
        assertEquals(0.50, GeneratedCoverMath.lighterGroundLightness(0.46), 0.0001)

        fun linear(value: Double): Double =
            if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)

        val pairs = listOf(0.32 to 0.085, 0.46 to 0.085, 0.50 to 0.09, 0.27 to 0.08, 0.47 to 0.017)
        for (hue in 0 until 360) {
            for ((lightness, chroma) in pairs) {
                val rgb = GeneratedCoverMath.oklchToRgb(lightness, chroma, hue.toDouble())
                val luminance = 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
                for (opacity in listOf(GeneratedCoverMath.BYLINE_OPACITY, GeneratedCoverMath.FANDOM_OPACITY, 1.0)) {
                    val fg = listOf(rgb.r, rgb.g, rgb.b).map { opacity + (1.0 - opacity) * it }
                    val textLuminance = 0.2126 * linear(fg[0]) + 0.7152 * linear(fg[1]) + 0.0722 * linear(fg[2])
                    assertTrue((textLuminance + 0.05) / (luminance + 0.05) >= 4.5)
                }
            }
        }
    }

    @Test
    fun zeroWidthStrokeFloorAndZeroHeightCrossoverCutAreFinite() {
        assertTrue(GeneratedCoverMath.strokeFloor(0.0).isFinite())
        assertEquals(GeneratedCoverMath.strokeFloor(0.0), GeneratedCoverMath.strokeFloor(1.0), 0.0001)
        assertTrue(GeneratedCoverMath.crossoverCut(0.6, 0.0).isFinite())
    }

    @Test
    fun collectionColourSnapsToPalette() {
        val palette = listOf(20, 55, 85, 125, 150, 180, 205, 230, 260, 290, 320, 350)
        assertEquals(260, GeneratedCoverRecipe.collectionHue("#808080", fallback = 20))
        assertEquals(0.012, GeneratedCoverRecipe.collectionSwatch("#808080", fallback = 20).second, 0.0001)
        assertTrue(GeneratedCoverRecipe.collectionHue(null, fallback = 137) in palette)
        val identity = UUID.fromString("00000000-0000-0000-0000-000000000077")
        assertTrue(GeneratedCoverRecipe.collectionHue(identity) in palette)
        assertFalse(GeneratedCoverRecipe.forCollection(name = "Next", hue = 150).hasRing)
        val renamed = GeneratedCoverRecipe.forCollection(name = "Renamed", identity = "same-id", hue = 150)
        val original = GeneratedCoverRecipe.forCollection(name = "Original", identity = "same-id", hue = 150)
        assertEquals(renamed.motif, original.motif)
        assertEquals(renamed.shapeSeed, original.shapeSeed)
        assertEquals(renamed.placement, original.placement)
    }

    @Test
    fun postingYearIsMonotoneAndClamped() {
        assertEquals(2010.0, GeneratedCoverRecipe.year(-1L), 0.0001)
        assertEquals(2010.0, GeneratedCoverRecipe.year(0L), 0.0001)
        assertEquals(2026.0, GeneratedCoverRecipe.year(72_000_000L), 0.0001)
        assertEquals(2026.0, GeneratedCoverRecipe.year(90_000_000L), 0.0001)
        var previous = 2010.0
        var id = 0L
        while (id <= 72_000_000L) {
            val year = GeneratedCoverRecipe.year(id)
            assertTrue("Non-monotone at id=$id: $year < $previous", year >= previous)
            previous = year
            id += 100_000L
        }
    }

    @Test
    fun collectionUuidIdentityMatchesIosUppercase() {
        val lower = "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"
        val upper = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
        assertEquals(upper, GeneratedCoverRecipe.canonicalCollectionIdentity(lower))
        assertEquals(upper, GeneratedCoverRecipe.canonicalCollectionIdentity(upper))
        assertEquals("same-id", GeneratedCoverRecipe.canonicalCollectionIdentity("same-id"))
        assertEquals("SAME-ID", GeneratedCoverRecipe.canonicalCollectionIdentity("SAME-ID"))

        val fromLower = GeneratedCoverRecipe.forCollection(name = "Shelf", identity = lower, hue = 150)
        val fromUpper = GeneratedCoverRecipe.forCollection(name = "Shelf", identity = upper, hue = 150)
        assertEquals(fromUpper.motif, fromLower.motif)
        assertEquals(fromUpper.shapeSeed, fromLower.shapeSeed)
        assertEquals(fromUpper.rotation, fromLower.rotation, 0.0)
        assertEquals(fromUpper.scale, fromLower.scale, 0.0)

        val upperId = GeneratedCoverRecipe.hash("collection:$upper").toLong().toString()
        assertEquals(GeneratedCoverRecipe.hash("shape:$upperId"), fromLower.shapeSeed)
        val lowerId = GeneratedCoverRecipe.hash("collection:$lower").toLong().toString()
        assertNotEquals(GeneratedCoverRecipe.hash("shape:$lowerId"), fromLower.shapeSeed)

        val plain = GeneratedCoverRecipe.forCollection(name = "Shelf", identity = "same-id", hue = 150)
        val shouted = GeneratedCoverRecipe.forCollection(name = "Shelf", identity = "SAME-ID", hue = 150)
        assertNotEquals(plain.shapeSeed, shouted.shapeSeed)

        assertEquals("1-2-3-4-5", GeneratedCoverRecipe.canonicalCollectionIdentity("1-2-3-4-5"))
        assertEquals("a-b-c-d-e", GeneratedCoverRecipe.canonicalCollectionIdentity("a-b-c-d-e"))
        val shortHex = GeneratedCoverRecipe.forCollection(name = "Shelf", identity = "1-2-3-4-5", hue = 150)
        val paddedUuid = GeneratedCoverRecipe.forCollection(
            name = "Shelf",
            identity = "00000001-0002-0003-0004-000000000005",
            hue = 150
        )
        assertNotEquals(paddedUuid.shapeSeed, shortHex.shapeSeed)
        val shortHexId = GeneratedCoverRecipe.hash("collection:1-2-3-4-5").toLong().toString()
        assertEquals(GeneratedCoverRecipe.hash("shape:$shortHexId"), shortHex.shapeSeed)
    }

    @Test
    fun fandomCleanTrimsNonBreakingSpacesLikeSwift() {
        val recipe = GeneratedCoverRecipe.create(
            id = 21L,
            title = "T",
            author = "a",
            fandoms = listOf("Doctor Who\u00A0(2005)", "\u202FDoctor Who\u00A0", "\u2007\u0085")
        )
        assertEquals("Doctor Who", recipe.fandom)
        assertEquals(1, recipe.hues.size)
        assertNotEquals(GeneratedCoverRecipe.Ground.CROSSOVER, recipe.ground)
    }

    @Test
    fun unicodeSeparatorsSplitTitlesLikeIos() {
        val subtitle = GeneratedCoverRecipe.create(
            id = 9L,
            title = "The Work\u00A0(Subtitle)",
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals("The Work", subtitle.title)
        assertEquals("(Subtitle)", subtitle.subtitle)
        assertEquals(2, subtitle.placement)

        val nextLine = GeneratedCoverRecipe.create(
            id = 9L,
            title = "The Work\u0085(Subtitle)",
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals("The Work", nextLine.title)
        assertEquals("(Subtitle)", nextLine.subtitle)
        assertEquals(2, nextLine.placement)

        val numbered = GeneratedCoverRecipe.create(
            id = 10L,
            title = "1.\u00A0Title",
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals("Title", numbered.title)
        assertEquals("", numbered.subtitle)

        val ascii = GeneratedCoverRecipe.create(
            id = 11L,
            title = "1. Title (Sub)",
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals("Title", ascii.title)
        assertEquals("(Sub)", ascii.subtitle)
        assertEquals(2, ascii.placement)
    }

    @Test
    fun zwjEmojiCountsAsOneGraphemeOnThePlacementBoundary() {
        val family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67\u200D\uD83D\uDC66"
        assertEquals(1, GeneratedCoverRecipe.graphemeCount(family))
        val sixteen = "AAAAAAAAAAAAAAA$family"
        assertEquals(16, GeneratedCoverRecipe.graphemeCount(sixteen))
        val atBoundary = GeneratedCoverRecipe.create(
            id = 16L,
            title = sixteen,
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals(1, atBoundary.placement)
        val seventeen = "AAAAAAAAAAAAAAAA$family"
        assertEquals(17, GeneratedCoverRecipe.graphemeCount(seventeen))
        val past = GeneratedCoverRecipe.create(
            id = 17L,
            title = seventeen,
            author = "a",
            fandoms = listOf("Original Work")
        )
        assertEquals(0, past.placement)
    }
}
