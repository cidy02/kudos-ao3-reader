package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Constants

class AO3DownloadUrlBuilder {
    fun epubDownloadUrl(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath("/downloads/$workId/work.epub")
            .build()
            .toString()
    }

    /** The same route with `.html`: the one format AO3 keeps when it withdraws the ebook ones. */
    fun htmlDownloadUrl(workId: Long): String = epubDownloadUrl(workId).removeSuffix("epub") + "html"

    fun workMetadataUrl(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath("/works/$workId")
            .addQueryParameter("view_adult", "true")
            .build()
            .toString()
    }
}
