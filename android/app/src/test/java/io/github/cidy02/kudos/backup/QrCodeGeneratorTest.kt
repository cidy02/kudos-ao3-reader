package io.github.cidy02.kudos.backup

import com.google.zxing.BinaryBitmap
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.qrcode.QRCodeReader
import com.google.zxing.common.HybridBinarizer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * QR *encoding* is real, testable data transformation — round-trip it
 * through zxing's own decoder as an independent verifier. The rendered
 * Compose UI around it (PairingSheet's Image()) is manual-verification-only
 * (see the report) and is deliberately not faked here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class QrCodeGeneratorTest {
    @Test
    fun encodedQrDecodesBackToTheExactPairingPayload() {
        val hex = "ab".repeat(32)
        val payload = PairingKeyCodec.encode(hex)

        val bitmap = QrCodeGenerator.encode(payload, sizePx = 256)

        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val source = RGBLuminanceSource(bitmap.width, bitmap.height, pixels)
        val decoded = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)))

        assertEquals(payload, decoded.text)
        // The decoded text must itself decode back to the original hex —
        // the full round trip an iOS scan would perform.
        assertEquals(hex, PairingKeyCodec.decode(decoded.text))
    }

    @Test
    fun encodeRejectsBlankText() {
        assertThrows(IllegalArgumentException::class.java) {
            QrCodeGenerator.encode("")
        }
    }
}
