package io.github.cidy02.kudos.update

import io.github.cidy02.kudos.network.github.GitHubRelease
import io.github.cidy02.kudos.network.github.GitHubReleaseAsset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AndroidReleaseMatcherTest {
    private fun release(
        tag: String,
        draft: Boolean = false,
        assets: List<GitHubReleaseAsset> = emptyList()
    ) = GitHubRelease(tagName = tag, draft = draft, assets = assets)

    private val apkAsset = GitHubReleaseAsset(
        name = "kudos-android-v0.2.0.apk",
        browserDownloadUrl = "https://example/kudos.apk",
        size = 1234
    )

    @Test
    fun `ignores releases without an android tag prefix`() {
        val releases = listOf(
            release("sideload-test-20260706-1050", assets = listOf(apkAsset)),
            release("ios-test-build-20260703-e8a6164", assets = listOf(apkAsset))
        )
        assertNull(AndroidReleaseMatcher.latest(releases))
    }

    @Test
    fun `ignores android-tagged releases with no apk asset`() {
        val releases = listOf(release("android-v0.2.0-alpha", assets = emptyList()))
        assertNull(AndroidReleaseMatcher.latest(releases))
    }

    @Test
    fun `ignores draft releases`() {
        val releases = listOf(release("android-v0.2.0-alpha", draft = true, assets = listOf(apkAsset)))
        assertNull(AndroidReleaseMatcher.latest(releases))
    }

    @Test
    fun `picks the highest matching version, not just the first in the list`() {
        val older = release("android-v0.1.0-alpha", assets = listOf(apkAsset))
        val newer = release("android-v0.2.0-alpha", assets = listOf(apkAsset))
        val result = AndroidReleaseMatcher.latest(listOf(older, newer))
        assertEquals(AppVersion(0, 2, 0), result?.version)
    }

    @Test
    fun `is unaffected by unrelated ios releases mixed into the same list`() {
        val releases = listOf(
            release("ios-test-build-20260703-e8a6164", assets = listOf(apkAsset)), // wrong prefix even with an .apk-shaped asset
            release("android-v0.1.0-alpha", assets = listOf(apkAsset))
        )
        val result = AndroidReleaseMatcher.latest(releases)
        assertEquals("android-v0.1.0-alpha", result?.release?.tagName)
    }
}
