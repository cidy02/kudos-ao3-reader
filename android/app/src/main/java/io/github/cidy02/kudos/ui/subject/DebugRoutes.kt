package io.github.cidy02.kudos.ui.subject

/**
 * Debug-only launch extra. Ignored unless the build is debuggable.
 *
 * `adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute designCatalog`
 * `... --es kudosDebugRoute nav:recently-deleted` opens any `Routes` path on launch.
 */
object DebugRoutes {
    const val EXTRA = "kudosDebugRoute"
    const val DESIGN_CATALOG = "designCatalog"
    const val NAV_PREFIX = "nav:"
    const val WRITING_EDITOR = "nav:writing-editor-demo"
    const val WRITING_EDITOR_FIXTURE = "nav:writing-editor-fixture"
}
