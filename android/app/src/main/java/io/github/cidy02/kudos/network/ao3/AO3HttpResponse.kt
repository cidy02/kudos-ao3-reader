package io.github.cidy02.kudos.network.ao3

data class AO3HttpResponse(
    val url: String,
    val statusCode: Int,
    val headers: Map<String, List<String>>,
    val body: String
) {
    fun header(name: String): String? {
        return headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }
            ?.value
            ?.firstOrNull()
    }
}

data class AO3BinaryResponse(
    val url: String,
    val statusCode: Int,
    val headers: Map<String, List<String>>,
    val body: ByteArray
) {
    fun header(name: String): String? {
        return headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }
            ?.value
            ?.firstOrNull()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AO3BinaryResponse) return false
        return url == other.url &&
            statusCode == other.statusCode &&
            headers == other.headers &&
            body.contentEquals(other.body)
    }

    override fun hashCode(): Int {
        var result = url.hashCode()
        result = 31 * result + statusCode
        result = 31 * result + headers.hashCode()
        result = 31 * result + body.contentHashCode()
        return result
    }
}
