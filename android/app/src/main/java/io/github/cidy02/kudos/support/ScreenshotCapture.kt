package io.github.cidy02.kudos.support

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.core.content.FileProvider
import java.io.File

/**
 * iOS `ScreenshotCapture.captureKeyWindow`: the screen at shake time, grabbed before the bug
 * report covers it. Null when there is no window to read. PixelCopy reads the window's
 * surface, so Coil's hardware bitmaps come out too (a software canvas would throw on them).
 */
fun captureScreen(context: Context, onResult: (Bitmap?) -> Unit) {
    val window = context.findActivity()?.window
    val view = window?.decorView
    if (view == null || view.width == 0 || view.height == 0) return onResult(null)
    val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
    try {
        PixelCopy.request(
            window,
            bitmap,
            { result -> onResult(bitmap.takeIf { result == PixelCopy.SUCCESS }) },
            Handler(Looper.getMainLooper())
        )
    } catch (_: IllegalArgumentException) {
        onResult(null)
    }
}

/**
 * Writes [bitmap] where the FileProvider can hand it out, for the share sheet the bug report
 * opens. Blocking: call it off the main thread.
 */
fun screenshotShareIntent(context: Context, bitmap: Bitmap): Intent {
    val dir = File(context.cacheDir, "bug-report").apply { mkdirs() }
    val file = File(dir, "Kudos screenshot.png")
    file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType("image/png")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return Intent.createChooser(send, "Save or Share Screenshot")
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
