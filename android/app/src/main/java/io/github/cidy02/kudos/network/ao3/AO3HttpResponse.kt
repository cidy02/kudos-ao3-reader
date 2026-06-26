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
