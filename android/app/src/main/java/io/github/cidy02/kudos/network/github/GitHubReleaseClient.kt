package io.github.cidy02.kudos.network.github

import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Public, unauthenticated GitHub REST access for one repo's releases. No
 * cookies/CSRF/AO3 pacing concerns — a plain client, deliberately separate
 * from [io.github.cidy02.kudos.network.ao3.OkHttpAO3Client].
 */
class GitHubReleaseClient(
    private val owner: String = "cidy02",
    private val repo: String = "kudos-ao3-reader",
    private val appVersionForUserAgent: String
) {
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .callTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    private val json = Json { ignoreUnknownKeys = true }

    /** Most recent releases, newest first, as GitHub returns them (page 1, default page size). */
    suspend fun fetchReleases(): List<GitHubRelease> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("https://api.github.com/repos/$owner/$repo/releases")
            // GitHub's REST API rejects requests with no User-Agent.
            .header("User-Agent", "Kudos-Android/$appVersionForUserAgent (+https://github.com/$owner/$repo)")
            .header("Accept", "application/vnd.github+json")
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("GitHub returned HTTP ${response.code} listing releases.")
            }
            val body = response.body.string()
            json.decodeFromString<List<GitHubRelease>>(body)
        }
    }
}
