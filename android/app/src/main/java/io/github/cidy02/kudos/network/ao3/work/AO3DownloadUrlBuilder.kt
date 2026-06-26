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

    fun workMetadataUrl(workId: Long): String {
        require(workId > 0) { "AO3 work id must be positive." }
        return AO3Constants.baseHttpUrl.newBuilder()
            .encodedPath("/works/$workId")
            .addQueryParameter("view_adult", "true")
            .build()
            .toString()
    }
}
