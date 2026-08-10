package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.ReaderLocatorCodec
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Fix 1: foreign (or bare) locators must not navigate. [locatorFromJson] used to
 * fall back to parsing the raw string when [decodeCompatibleLocator] returned
 * null, which let iOS-written bare Readium locators open on Android.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LocatorFromJsonTest {

    @Test
    fun rejectedByDecodeCompatibleLocatorProducesNoLocator() {
        // Bare Readium locator — same shape iOS stores; decodeCompatibleLocator
        // rejects it (no android envelope). Must not produce a navigation target.
        val bareIosStyleLocator =
            """{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.5}}"""
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(bareIosStyleLocator))
        assertNull(ReadiumNavigatorController.locatorFromJson(bareIosStyleLocator))
    }

    @Test
    fun foreignEnvelopeProducesNoLocator() {
        val foreign =
            """{"platform":"ios","engine":"readium-swift","version":1,"locator":{"href":"x.xhtml","type":"application/xhtml+xml","locations":{"progression":0.1}}}"""
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(foreign))
        assertNull(ReadiumNavigatorController.locatorFromJson(foreign))
    }

    @Test
    fun androidEnvelopeStillNavigates() {
        val raw =
            """{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.5}}"""
        val envelope = ReaderLocatorCodec.encodeEnvelope(raw)
        assertNotNull(envelope)
        assertNotNull(ReadiumNavigatorController.locatorFromJson(envelope!!))
    }
}
