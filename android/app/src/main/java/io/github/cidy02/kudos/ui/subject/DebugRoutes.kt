package io.github.cidy02.kudos.ui.subject

/**
 * Debug-only launch extra. Ignored unless the build is debuggable.
 *
 * `adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute designCatalog`
 */
object DebugRoutes {
    const val EXTRA = "kudosDebugRoute"
    const val DESIGN_CATALOG = "designCatalog"
}
