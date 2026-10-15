package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import org.jsoup.nodes.Element

/**
 * A work's authors by AO3 account, in the shape iOS keeps them (`AO3AuthorIdentityCodec`). A
 * byline's words are a pseud, so the account is read from the link's address. Kept on the device
 * only: no backup carries it.
 */
object AO3AuthorIdentities {
    /** Empty when no link names an account: Anonymous, or a page without a byline. */
    fun json(authorLinks: Iterable<Element>): String {
        val identities = buildJsonArray {
            for (link in authorLinks) {
                // Resolved, so the segments are decoded: "Second%20Pseud" is "Second Pseud".
                val path = AO3Constants.baseHttpUrl.resolve(link.attr("href"))?.pathSegments ?: continue
                val username = path.getOrNull(1)?.takeIf { path[0] == "users" && it.isNotBlank() } ?: continue
                addJsonObject {
                    put("username", username)
                    if (path.getOrNull(2) == "pseuds") path.getOrNull(3)?.takeIf { it.isNotBlank() }?.let { put("pseud", it) }
                    put("displayName", link.text().trim())
                    put("kind", if (username.equals("orphan_account", ignoreCase = true)) "orphaned" else "registered")
                }
            }
        }
        return if (identities.isEmpty()) "" else identities.toString()
    }

    /**
     * One name of a byline as AO3 prints its account, "pseud (account)" or the account alone,
     * for [AO3AuthorRoute.fromByline]. The name's own words are a pseud: asked for as an
     * account, "Avery Writes" is nobody, or somebody else. Null when no kept link has the name.
     */
    fun byline(json: String, displayName: String): String? {
        val identities = runCatching { Json.parseToJsonElement(json) as? JsonArray }.getOrNull() ?: return null
        fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
        val matches = identities.filterIsInstance<JsonObject>().filter {
            it.text("displayName") == displayName.trim() && it.text("kind") in setOf("registered", "orphaned")
        }
        // Two accounts printed alike: no link rather than the first one's (A49 F9).
        if (matches.mapNotNull { it.text("username")?.lowercase() }.distinct().size > 1) return null
        val identity = matches.firstOrNull() ?: return null
        val username = identity.text("username") ?: return null
        val pseud = identity.text("pseud")
        return if (pseud == null || pseud == username) username else "$pseud ($username)"
    }
}
