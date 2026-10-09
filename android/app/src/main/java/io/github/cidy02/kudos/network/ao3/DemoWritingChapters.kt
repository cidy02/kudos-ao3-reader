package io.github.cidy02.kudos.network.ao3

import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import java.net.URLDecoder

/** Original process-local chapter answers, reached only by the terminal demo interceptor. */
internal class DemoWritingChapters {
    private val forms = mutableMapOf<Long, MutableMap<Long, Document>>()
    private val changed = mutableSetOf<Long>()
    private val failTotalOnce = mutableSetOf<Long>()
    fun hasChanges(work: Long) = work in changed
    fun totalFailure(work: Long): String? = if (failTotalOnce.remove(work)) "Expected chapter total could not be updated." else null

    fun answer(request: Request, source: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        val match = Regex("^/works/(995006|995001)/(chapters(?:/(?:new|[0-9]+)(?:/(?:edit|confirm_delete))?)?|navigate)$").matchEntire(path)
            ?: return null
        val work = match.groupValues[1].toLong()
        val chapters = forms[work] ?: initial(work, source)?.also { forms[work] = it } ?: return 404 to ""
        if (request.method == "GET") {
            if (path.endsWith("/navigate")) return 200 to index(work, chapters)
            if (path.endsWith("/new")) {
                val doc = source.read("ao3_demo_chapter_${work}_new")?.decodeToString()?.let(Jsoup::parse) ?: return 404 to ""
                doc.selectFirst("input[name='chapter[position]']")?.attr("value", (chapters.size + 1).toString())
                return 200 to doc.outerHtml()
            }
            val id = path.substringAfter("/chapters/").substringBefore('/').toLongOrNull() ?: return 404 to ""
            val doc = chapters[id] ?: return 404 to ""
            if (path.endsWith("/edit")) return 200 to doc.outerHtml()
            if (path.endsWith("/confirm_delete")) {
                val delete = source.read("ao3_demo_chapter_${work}_delete")?.decodeToString()?.let(Jsoup::parse) ?: return 404 to ""
                delete.selectFirst("form")?.attr("action", "/works/$work/chapters/$id")
                return 200 to delete.outerHtml()
            }
            return 404 to ""
        }
        if (request.method != "POST") return 405 to ""
        val id = path.substringAfter("/chapters/", "").toLongOrNull()
        if (path != "/works/$work/chapters" && id == null) return 405 to ""
        val body = okio.Buffer().also { request.body?.writeTo(it) }.readUtf8()
        val fields = body.split('&').filter(String::isNotEmpty).map {
            val pair = it.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }.groupBy({ it.first }, { it.second })
        if (fields["_method"] == listOf("delete")) {
            val token = "demo-delete-$work=="
            if (fields["authenticity_token"] != listOf(token) || request.header("X-CSRF-Token") != token) return refusal("Invalid authenticity token")
            if (id == null || id !in chapters) return 404 to ""
            if (chapters.size <= 1) return refusal("You cannot delete the only chapter of a work.")
            val posted = chapters.values.count { it.selectFirst("[name=save_button]") == null }
            if (posted == 1 && chapters[id]?.selectFirst("[name=save_button]") == null)
                return refusal("You cannot delete the only posted chapter of a work.")
            chapters.remove(id); renumber(chapters); changed += work
            return notice("Chapter was successfully deleted.")
        }
        val old = if (id != null) chapters[id]?.clone() else source.read("ao3_demo_chapter_${work}_new")?.decodeToString()?.let(Jsoup::parse)
        val doc = old ?: return 404 to ""
        doc.outputSettings().prettyPrint(false)
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
        if (fields["authenticity_token"] != listOf(token) || request.header("X-CSRF-Token") != token) return refusal("Invalid authenticity token")
        val submits = listOf("save_button", "preview_button", "post_without_preview_button", "post_button", "update_button")
            .filter { fields[it] == listOf("1") }
        if (submits.size != 1 || id != null && fields["_method"] != listOf("patch")) return refusal("AO3 didn't accept the change.")
        val title = fields["chapter[title]"]?.firstOrNull().orEmpty()
        if (title == "Refuse this chapter") return refusal("Title is too long (maximum is 255 characters)", "Content can't be blank")
        for (control in doc.select("form [name]")) {
            if (!control.attr("name").startsWith("chapter[")) continue
            val sent = fields[control.attr("name")] ?: continue
            when (control.tagName()) {
                "textarea" -> control.text(sent.firstOrNull().orEmpty())
                "select" -> control.select("option").forEach { option ->
                    if (option.attr("value") in sent) option.attr("selected", "selected") else option.removeAttr("selected")
                }
                "input" -> if (control.attr("type") !in listOf("submit", "checkbox", "radio")) control.attr("value", sent.firstOrNull().orEmpty())
            }
        }
        val preview = submits.single() == "preview_button"
        // Preview on an existing chapter only renders. A new preview creates one draft.
        val newId = id ?: ((chapters.keys.maxOrNull() ?: if (work == 995006L) 12300L else 12310L) + 1)
        val posts = submits.single() in listOf("post_without_preview_button", "post_button", "update_button")
        val form = doc.selectFirst("form") ?: return 404 to ""
        form.attr("action", "/works/$work/chapters/$newId")
        if (form.selectFirst("[name=_method]") == null) form.prependElement("input").attr("type", "hidden").attr("name", "_method").attr("value", "patch")
        if (posts) {
            form.select("[name=save_button], [name=post_without_preview_button]").remove()
            if (form.selectFirst("[name=update_button]") == null) form.appendElement("input").attr("type", "submit").attr("name", "update_button").attr("value", "Update")
        }
        if (!preview || id == null) {
            chapters[newId] = doc.clone(); renumber(chapters); changed += work
            if (title == "Fail total once") failTotalOnce += work
        }
        if (preview) {
            val reply = Document.createShell("https://archiveofourown.org")
            reply.head().appendElement("meta").attr("name", "csrf-token").attr("content", token.orEmpty())
            val main = reply.body().appendElement("main").attr("id", "main")
            main.appendElement("div").attr("class", "flash notice").text("Draft saved.")
            val pane = main.appendElement("div").attr("id", "previewpane")
            pane.appendElement("h3").attr("class", "title").text(title)
            for ((label, name) in listOf("Summary:" to "summary", "Notes:" to "notes", "" to "content", "Notes:" to "endnotes")) {
                val module = pane.appendElement("div").attr("class", "module")
                if (label.isNotEmpty()) module.appendElement("h3").attr("class", "heading").text(label)
                module.appendElement("div").attr("class", "userstuff").html(fields["chapter[$name]"]?.firstOrNull().orEmpty())
            }
            val posting = form.clone()
            posting.select("input[type=submit], button").remove()
            posting.appendElement("input").attr("type", "submit").attr("name", "edit_button").attr("value", "Edit")
            posting.appendElement("input").attr("type", "submit").attr("name", if (doc.selectFirst("[name=save_button]") != null) "post_button" else "update_button").attr("value", "Post")
            main.appendChild(posting)
            return 200 to reply.outerHtml()
        }
        return notice(if (posts) "Chapter was successfully posted." else "Draft chapter was successfully saved.")
    }

    fun applyToWork(doc: Document, work: Long) {
        if (work !in changed) return
        val chapters = forms[work] ?: return
        val form = doc.selectFirst("form#work-form") ?: return
        form.select("a[href*=/chapters/][href*=/edit]").remove()
        chapters.forEach { (id, _) -> form.appendElement("a").attr("href", "/works/$work/chapters/$id/edit").text("Chapter") }
        if (chapters.size > 1) form.select("textarea[name='work[chapter_attributes][content]']").remove()
        val first = chapters.values.firstOrNull() ?: return
        form.selectFirst("[name='work[chapter_attributes][id]']")?.attr("value", chapters.keys.first().toString())
        for (control in form.select("[name^='work[chapter_attributes]']")) {
            val name = control.attr("name").replace("work[chapter_attributes]", "chapter")
            val source = first.selectFirst("[name='$name']") ?: continue
            if (control.tagName() == "textarea") control.text(source.wholeText())
            else if (control.tagName() == "select") {
                val values = source.select("option[selected]").map { it.attr("value") }
                control.select("option").forEach { if (it.attr("value") in values) it.attr("selected", "selected") else it.removeAttr("selected") }
            } else control.attr("value", source.attr("value"))
        }
    }

    private fun initial(work: Long, source: FixtureSource): MutableMap<Long, Document>? {
        val kind = if (work == 995006L) "posted" else "draft"
        val doc = source.read("ao3_demo_chapter_${work}_$kind")?.decodeToString()?.let(Jsoup::parse) ?: return null
        val id = if (work == 995006L) 12302L else 12311L
        val result = linkedMapOf<Long, Document>()
        if (work == 995006L) result[12301] = doc.clone().apply {
            selectFirst("form")?.attr("action", "/works/$work/chapters/12301")
            selectFirst("[name='chapter[title]']")?.attr("value", "Chapter 1")
            selectFirst("[name='chapter[position]']")?.attr("value", "1")
        }
        result[id] = doc
        return result
    }
    private fun renumber(chapters: MutableMap<Long, Document>) {
        val sorted = chapters.entries.sortedBy { it.value.selectFirst("[name='chapter[position]']")?.attr("value")?.toIntOrNull() ?: Int.MAX_VALUE }
        chapters.clear()
        sorted.forEachIndexed { index, entry -> entry.value.selectFirst("[name='chapter[position]']")?.attr("value", "${index + 1}"); chapters[entry.key] = entry.value }
    }
    private fun index(work: Long, chapters: Map<Long, Document>): String {
        val doc = Document.createShell("https://archiveofourown.org")
        val list = doc.body().appendElement("main").attr("id", "main").appendElement("ol").attr("class", "chapter index group")
        chapters.entries.forEachIndexed { position, (id, form) ->
            val row = list.appendElement("li")
            row.appendElement("a").attr("href", "/works/$work/chapters/$id").text("${position + 1}. " + form.selectFirst("[name='chapter[title]']")?.attr("value").orEmpty().ifEmpty { "Chapter ${position + 1}" })
            row.appendElement("span").attr("class", "datetime").text("(2026-10-05)")
        }
        return doc.outerHtml()
    }
    private fun refusal(vararg reasons: String): Pair<Int, String> {
        val doc = Document.createShell("https://archiveofourown.org")
        val list = doc.body().appendElement("main").attr("id", "main").appendElement("div").attr("id", "error").appendElement("ul")
        reasons.forEach { list.appendElement("li").text(it) }
        return 422 to doc.outerHtml()
    }
    private fun notice(text: String) = 200 to "<main id='main'><div class='flash notice'>$text</div></main>"
}
