package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
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
}
