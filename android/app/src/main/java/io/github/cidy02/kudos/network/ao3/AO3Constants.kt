package io.github.cidy02.kudos.network.ao3

import okhttp3.HttpUrl.Companion.toHttpUrl

object AO3Constants {
    const val BASE_URL = "https://archiveofourown.org"
    const val WORKS_HOST = "archiveofourown.org"
    const val SEARCH_PATH = "/works/search"
    const val LOGIN_PATH = "/users/login"

    val baseHttpUrl = BASE_URL.toHttpUrl()

    fun isLoginUrl(url: String): Boolean {
        return runCatching { url.toHttpUrl().encodedPath == LOGIN_PATH }.getOrDefault(false)
    }
}
