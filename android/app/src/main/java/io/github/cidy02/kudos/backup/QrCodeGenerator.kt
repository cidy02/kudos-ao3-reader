package io.github.cidy02.kudos.backup

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * QR **generation only**. Android's pairing role is deliberately
 * QR-generate-only, never scan — iOS is the scanner (a sibling unit). Do not
 * add a scanning/camera dependency here; see [PairingKeyCodec] for the wire
 * format this encodes.
 */
object QrCodeGenerator {
    fun encode(text: String, sizePx: Int = 512): Bitmap {
        require(text.isNotBlank()) { "text must not be blank" }
        val hints = mapOf(
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 1
        )
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
        val bitmap = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.RGB_565)
        for (x in 0 until matrix.width) {
            for (y in 0 until matrix.height) {
                bitmap.setPixel(x, y, if (matrix.get(x, y)) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }
}
