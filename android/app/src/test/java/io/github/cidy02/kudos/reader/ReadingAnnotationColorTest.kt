package io.github.cidy02.kudos.reader

import android.app.Application
import android.graphics.Color as AndroidColor
import io.github.cidy02.kudos.backup.toBackupAnnotation
import io.github.cidy02.kudos.backup.toReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class ReadingAnnotationColorTest {
    @Test fun customHexRoundTripsInUppercase() {
        assertEquals("#AABBCC", ReadingAnnotationColor.customHex("  #aabbcc "))
        assertEquals("#AABBCC", ReadingAnnotationColor.normalizedRaw("#aabbcc"))
        assertNull(ReadingAnnotationColor.customHex("#abc"))
        assertNull(ReadingAnnotationColor.customHex("aabbcc"))
        assertEquals(ReadingAnnotationColor.YELLOW.raw, ReadingAnnotationColor.normalizedRaw("BLUE"))
    }

    @Test fun customHexRoundTripsThroughBackupWithoutBecomingAPreset() {
        val annotation = ReadingAnnotation(
            id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            workID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            kindRaw = "highlight",
            colorRaw = "#2468AC"
        )
        val restored = annotation.toBackupAnnotation().toReadingAnnotation()
        assertEquals("#2468AC", restored.colorRaw)
    }

    @Test fun customHexDrawsExactlyAndInvalidRawDrawsYellowWithoutChangingStorage() {
        assertEquals(AndroidColor.parseColor("#2468AC"), ReadiumNavigatorController.colorForName("#2468ac"))
        assertEquals(AndroidColor.parseColor("#FFF59D"), ReadiumNavigatorController.colorForName("future-colour"))
        assertEquals(AndroidColor.parseColor("#FFF59D"), ReadiumNavigatorController.colorForName("BLUE"))
        val restored = ReadingAnnotation(
            id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            workID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            colorRaw = "future-colour"
        ).toBackupAnnotation().toReadingAnnotation()
        assertEquals(ReadingAnnotationColor.YELLOW.color,
            ReadingAnnotationColor.displayColor(restored.colorRaw))
        assertEquals("future-colour", restored.colorRaw)
    }
}
