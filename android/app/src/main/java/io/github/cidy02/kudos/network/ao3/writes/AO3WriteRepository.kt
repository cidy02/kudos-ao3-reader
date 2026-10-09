package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSignUpForm
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSignUpUrls
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSignUpParser
import io.github.cidy02.kudos.network.ao3.account.AO3SignUpSaveOutcome
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeUrls
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemDraft
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsPage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionForm
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionSaveOutcome
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionModerationUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantsUrls
import io.github.cidy02.kudos.network.ao3.account.collectionNameFormatIsValid
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetSnapshot
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetField
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetUrls
import io.github.cidy02.kudos.network.ao3.account.AO3TagNomination
import io.github.cidy02.kudos.network.ao3.account.rejectParameter
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

class AO3WriteRepository(
    private val client: AO3AuthenticatedClient,
    private val parser: AO3WriteFormParser = AO3WriteFormParser()
) {
    /** Loaded series token/action, no preparation read, exactly one non-retried POST. */
    suspend fun saveSeries(form: io.github.cidy02.kudos.network.ao3.writing.AO3SeriesForm,
        expectedGeneration: Int): AO3Result<String> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        if (!AO3RedirectCookieRelay.isTrustedUrl(form.actionUrl) || form.seriesID == null || form.openOnAO3ForCreate)
            return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's series form."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(form.actionUrl, form.parameters(),
                writeHeaders(form.csrfToken, form.actionUrl), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val error = parser.writeErrorMessage(response.value.body)
                val notice = parser.workWriteNotice(response.value.body)
                when {
                    error != null -> AO3Result.Failure(AO3Error.Validation(error))
                    notice != null -> AO3Result.Success(notice)
                    response.value.statusCode in 300..399 -> AO3Result.Success("Saved.")
                    response.value.statusCode in 200..299 -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
                    else -> AO3Result.Failure(AO3Error.Validation("AO3 didn't accept the change."))
                }
            }
        }
    }

    /** iOS's full serial order, verified by a read-back; a redirect alone proves nothing. */
    suspend fun reorderSeries(seriesID: Long, orderedSerialWorkIDs: List<Long>, expectedGeneration: Int):
        AO3Result<List<io.github.cidy02.kudos.network.ao3.writing.AO3SeriesWorkRow>> =
        changeSeriesWorks(seriesID, orderedSerialWorkIDs, null, expectedGeneration)

    suspend fun removeWorkFromSeries(seriesID: Long, serialWorkID: Long, expectedGeneration: Int):
        AO3Result<List<io.github.cidy02.kudos.network.ao3.writing.AO3SeriesWorkRow>> =
        changeSeriesWorks(seriesID, null, serialWorkID, expectedGeneration)

    private suspend fun changeSeriesWorks(seriesID: Long, order: List<Long>?, removal: Long?, expectedGeneration: Int):
        AO3Result<List<io.github.cidy02.kudos.network.ao3.writing.AO3SeriesWorkRow>> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        if (seriesID <= 0) return AO3Result.Failure(AO3Error.Validation("Not a valid AO3 series URL."))
        val url = io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormUrls.manage(seriesID)
        val html = when (val result = client.getAuthenticated(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the form on AO3."))
        val seriesParser = io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormParser()
        val listed = try { seriesParser.parseManage(html, url).map { it.serialWorkID } }
            catch (_: Exception) { return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's series form.")) }
        if (order != null && (order.size != listed.size || order.toSet() != listed.toSet() || order.distinct().size != order.size) ||
            removal != null && removal !in listed)
            return AO3Result.Failure(AO3Error.Validation("The series changed on AO3 since this screen opened. Reopen it and try again."))
        if (removal != null && listed.size <= 1) return AO3Result.Failure(AO3Error.Validation(
            "It is the series' last work on AO3, and AO3 deletes a series with its last work."))
        val fields = listOf("authenticity_token" to token) +
            (order?.map { "serial[]" to it.toString() } ?: listOf("_method" to "delete"))
        val action = if (removal == null) io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormUrls.positions(seriesID)
            else "https://archiveofourown.org/serial_works/$removal"
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(action, fields, writeHeaders(token, url), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        when (response) {
            is AO3Result.Failure -> return response
            is AO3Result.Success -> parser.writeErrorMessage(response.value.body)?.let {
                return AO3Result.Failure(AO3Error.Validation(it))
            }
        }
        val fresh = try {
            when (val result = client.getAuthenticated(url)) {
                is AO3Result.Failure -> null
                is AO3Result.Success -> try { seriesParser.parseManage(result.value.body, url) } catch (_: Exception) { null }
            }
        // The POST has returned. A session that moved on during this read is "didn't confirm" just below,
        // not a cancellation the screen words as "not saved" (audit A26-2); a closed screen still cancels.
        } catch (_: CancellationException) { currentCoroutineContext().ensureActive(); null }
        catch (_: Exception) { null }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        if (fresh == null || order != null && fresh.sortedBy { it.position }.map { it.serialWorkID } != order ||
            removal != null && fresh.any { it.serialWorkID == removal })
            return AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
        return AO3Result.Success(fresh)
    }

    /** iOS saveWork: the loaded token/body/action, zero preparation reads, one single-shot POST. */
    suspend fun saveWork(form: AO3WorkForm, expectedGeneration: Int): AO3Result<Unit> =
        submitWork(form, expectedGeneration, form.actionUrl)

    /** iOS editTags: fresh form/token/action, desired tags, one single-shot POST. */
    suspend fun editWorkTags(desired: AO3WorkForm, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        if (desired.kind != AO3WorkFormKind.EditTags)
            return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form."))
        val id = desired.workID ?: return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form."))
        val referer = AO3WorkFormUrls.editTags(id)
        val page = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        currentCoroutineContext().ensureActive()
        requireCollectionSession(expectedGeneration)
        val fresh = try {
            withContext(Dispatchers.Default) { AO3WorkFormParser().parse(page.body, page.url) }
        } catch (cancelled: CancellationException) { throw cancelled }
          catch (_: AO3WorkFormParseException.LoginRequired) { return AO3Result.Failure(AO3Error.AuthenticationRequired) }
          catch (_: AO3WorkFormParseException.Overloaded) { return AO3Result.Failure(AO3Error.Overloaded(page.statusCode, null)) }
          catch (_: Exception) { return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form.")) }
        if (fresh.kind != AO3WorkFormKind.EditTags || fresh.workID != id)
            return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form."))
        return submitWork(fresh.withTagsFrom(desired), expectedGeneration, referer, tagsOnly = true)
    }

    private suspend fun submitWork(form: AO3WorkForm, expectedGeneration: Int, referer: String,
        tagsOnly: Boolean = false, servedOnly: Boolean = false,
        submit: AO3WorkSubmitAction = if (tagsOnly || form.isPosted) AO3WorkSubmitAction.Update else AO3WorkSubmitAction.SaveDraft): AO3Result<Unit> {
        val fields = form.parameters(submit)
            .let { pairs -> if (!servedOnly) pairs else {
                val names = form.servedControls.filterNot { it.disabled }.map { it.name }.toSet()
                pairs.filter { it.first in names }
            } }
        if (servedOnly && fields.none { it.first == (if (form.isPosted) "update_button" else "save_button") })
            return AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
        val token = if (tagsOnly) form.csrfToken else fields.firstOrNull { it.first == AO3WorkFormField.authenticityToken }?.second.orEmpty()
        return workVerdict(postWriting(form.actionUrl, fields, token, referer, expectedGeneration), tagsOnly)
    }

    /** Work Post is direct (not the chapter's preview-first path), including a new work. */
    suspend fun postWork(form: AO3WorkForm, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val missing = form.missingRequiredFields()
        if (missing.isNotEmpty()) return AO3Result.Failure(AO3Error.Validation("AO3 still needs ${missing.joinToString(" and ")}."))
        return submitWork(form, expectedGeneration, form.actionUrl, submit = AO3WorkSubmitAction.Post)
    }

    /** Preview is a write: one POST, same dispatch fence/verdict, then authoritative pane. */
    suspend fun previewWork(form: AO3WorkForm, expectedGeneration: Int): AO3Result<AO3WorkPreview> {
        val fields = form.parameters(AO3WorkSubmitAction.Preview)
        return parseWritingPreview(postWriting(form.actionUrl, fields,
            fields.firstOrNull { it.first == "authenticity_token" }?.second.orEmpty(), form.actionUrl, expectedGeneration,
            judgedByCaller = true), expectedGeneration, workOnly = true)
    }

    /** iOS reads confirm_delete then the work stats. Draft public pages would be refused. */
    suspend fun loadDeleteImplications(workID: Long, expectedGeneration: Int): AO3Result<AO3WorkDeleteImplications> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val page = when (val result = client.getAuthenticated(workConfirmDeleteUrl(workID))) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        currentCoroutineContext().ensureActive()
        requireCollectionSession(expectedGeneration)
        val implications = try { withContext(Dispatchers.Default) {
            AO3WorkDeleteParser.parse(page.body, page.url, workID)
        } } catch (cancelled: CancellationException) { throw cancelled }
          catch (_: Exception) { return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form.")) }
        // iOS goes on to read the work's own page for the counts its confirmation page lacks, here and
        // again on the confirmed delete. Neither app shows those counts (the alert is AO3's caution,
        // verbatim), so Android does not make the read: two fewer requests for every posted work deleted.
        currentCoroutineContext().ensureActive()
        requireCollectionSession(expectedGeneration)
        return AO3Result.Success(implications)
    }

    /** Swift re-reads the delete form on confirmation, then submits only token + method. */
    suspend fun deleteWork(workID: Long, expectedGeneration: Int): AO3Result<Unit> {
        val implications = when (val result = loadDeleteImplications(workID, expectedGeneration)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        return workVerdict(postWriting(implications.actionUrl, listOf("authenticity_token" to implications.csrfToken,
            "_method" to implications.methodOverride), implications.csrfToken, implications.actionUrl, expectedGeneration))
    }

    /** Captured chapter action/token; no preparation GET, one single-shot POST. */
    suspend fun saveChapter(form: AO3ChapterForm, submit: AO3WorkSubmitAction, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        if (submit !in listOf(AO3WorkSubmitAction.SaveDraft, AO3WorkSubmitAction.Post,
                AO3WorkSubmitAction.PostWithoutPreview, AO3WorkSubmitAction.Update))
            return AO3Result.Failure(AO3Error.Validation("AO3 didn't accept the change."))
        val fields = form.parameters(submit)
        if (fields.none { it.first == submit.fieldName }) return AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
        return workVerdict(postWriting(form.actionUrl, fields, form.csrfToken, form.actionUrl, expectedGeneration))
    }

    suspend fun previewChapter(form: AO3ChapterForm, expectedGeneration: Int): AO3Result<AO3ChapterPreview> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val fields = form.parameters(AO3WorkSubmitAction.Preview)
        if (fields.none { it.first == "preview_button" }) return AO3Result.Failure(AO3Error.Validation(CHAPTER_PREVIEW_UNAVAILABLE))
        return parseWritingPreview(postWriting(form.actionUrl, fields, form.csrfToken, form.actionUrl, expectedGeneration,
            judgedByCaller = true), expectedGeneration, workOnly = false)
    }

    /**
     * iOS judges the preview it received. Previewing a new work or chapter makes AO3 create its draft, and
     * that draft's id is in this answer: thrown away because the session has since moved on, the next
     * Preview would create a second one (audit A26-1). So a preview AO3 did return is returned, and so is
     * AO3's own named refusal; only an answer that confirms nothing becomes "didn't confirm".
     */
    private suspend fun parseWritingPreview(result: AO3Result<AO3HttpResponse>, expectedGeneration: Int,
        workOnly: Boolean): AO3Result<AO3ChapterPreview> {
        if (result is AO3Result.Failure) return movedOnAfterWrite(expectedGeneration, result) ?: result
        val page = (result as AO3Result.Success).value
        var refused = false
        // A returned write must reach a verdict even if its screen departs while parsing.
        val verdict: AO3Result<AO3ChapterPreview> = withContext(NonCancellable) {
            withContext(Dispatchers.Default) {
                val error = parser.workWriteError(page.body)
                refused = error != null
                when {
                    error != null -> AO3Result.Failure(AO3Error.Validation(error))
                    page.statusCode !in 200..399 -> AO3Result.Failure(AO3Error.Validation(CHAPTER_PREVIEW_UNAVAILABLE))
                    else -> try {
                        AO3Result.Success(AO3ChapterFormParser().preview(page.body, page.url, workOnly))
                    } catch (_: AO3WorkFormParseException.LoginRequired) { AO3Result.Failure(AO3Error.AuthenticationRequired) }
                      catch (_: Exception) { AO3Result.Failure(AO3Error.Validation(CHAPTER_PREVIEW_UNAVAILABLE)) }
                }
            }
        }
        // "Did return" means a preview that names what it previews: a pane with no work behind it adopts
        // nothing, and from a session that has moved on it confirms nothing either.
        val adoptable = verdict is AO3Result.Success && verdict.value.workID != null
        return if (adoptable || refused) verdict else movedOnAfterWrite(expectedGeneration, verdict) ?: verdict
    }

    /** iOS updateWorkTotals: a fresh work form, change only its total, SaveDraft/Update. */
    suspend fun updateWorkTotals(workID: Long, total: Long, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val page = when (val result = client.getAuthenticated(AO3WorkFormUrls.editWork(workID))) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        currentCoroutineContext().ensureActive()
        requireCollectionSession(expectedGeneration)
        val fresh = try { withContext(Dispatchers.Default) { AO3WorkFormParser().parse(page.body, page.url) } }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: AO3WorkFormParseException.LoginRequired) { return AO3Result.Failure(AO3Error.AuthenticationRequired) }
            catch (_: AO3WorkFormParseException.Overloaded) { return AO3Result.Failure(AO3Error.Overloaded(page.statusCode, null)) }
            catch (_: Exception) { return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form.")) }
        if (fresh.workID != workID || fresh.kind == AO3WorkFormKind.EditTags ||
            fresh.servedControls.none { !it.disabled && it.name == AO3WorkFormField.wipLength })
            return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form."))
        return submitWork(fresh.copy(chapterTotal = total.toString()), expectedGeneration, fresh.actionUrl, servedOnly = true)
    }

    /** Only after the editor's explicit confirmation: AO3's confirm_delete GET, one delete POST. */
    suspend fun deleteChapter(workID: Long, chapterID: Long, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val page = when (val result = client.getAuthenticated(AO3ChapterUrls.confirmDelete(workID, chapterID))) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        currentCoroutineContext().ensureActive()
        requireCollectionSession(expectedGeneration)
        val form = try { withContext(Dispatchers.Default) {
            AO3ChapterFormParser().deleteForm(page.body, page.url, workID, chapterID)
        } } catch (cancelled: CancellationException) { throw cancelled }
          catch (_: AO3WorkFormParseException.LoginRequired) { return AO3Result.Failure(AO3Error.AuthenticationRequired) }
          catch (_: AO3WorkFormParseException.Overloaded) { return AO3Result.Failure(AO3Error.Overloaded(page.statusCode, null)) }
          catch (_: Exception) { return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's chapter form.")) }
        return workVerdict(postWriting(form.actionUrl, listOf("authenticity_token" to form.csrfToken,
            "_method" to form.methodOverride), form.csrfToken, form.actionUrl, expectedGeneration))
    }

    /** The existing authenticated client owns pacing, cookies, transport and the dispatch fence. */
    private suspend fun postWriting(action: String, fields: List<Pair<String, String>>, token: String,
        referer: String, expectedGeneration: Int, judgedByCaller: Boolean = false): AO3Result<AO3HttpResponse> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        if (!AO3RedirectCookieRelay.isTrustedUrl(action)) return AO3Result.Failure(AO3Error.Parse("Couldn't read AO3's work form."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(action, fields, writeHeaders(token, referer), expectedGeneration)
        }
        if (!judgedByCaller) movedOnAfterWrite(expectedGeneration, response)?.let { return it }
        return response
    }

    private fun workVerdict(response: AO3Result<AO3HttpResponse>, sharedErrors: Boolean = false): AO3Result<Unit> = when (response) {
        is AO3Result.Failure -> response
        is AO3Result.Success -> {
            val error = if (sharedErrors) parser.writeErrorMessage(response.value.body) else parser.workWriteError(response.value.body)
            when {
                error != null -> AO3Result.Failure(AO3Error.Validation(error))
                parser.workWriteNotice(response.value.body) != null || response.value.statusCode in 300..399 -> AO3Result.Success(Unit)
                response.value.statusCode in 200..299 -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
                else -> AO3Result.Failure(AO3Error.Validation("AO3 didn't accept the change."))
            }
        }
    }

    /** iOS saveChallengeSignUp: validate, one fresh meta token, one POST, no follow-up GET. */
    suspend fun saveChallengeSignUp(form: AO3ChallengeSignUpForm,
        expectedGeneration: Int): AO3Result<AO3SignUpSaveOutcome> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val checked = form.validated()
        if (!checked.isValid) return AO3Result.Success(AO3SignUpSaveOutcome.Invalid(checked))
        val referer = AO3ChallengeSignUpUrls.form(form.slug, form.signUpID)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the work on AO3."))
        val action = checked.actionUrl.ifEmpty {
            "${AO3CollectionFormUrls.show(form.slug)}/signups" + (form.signUpID?.let { "/$it" } ?: "")
        }
        val posted = checked.copy(token = token, actionUrl = action)
        if (!AO3RedirectCookieRelay.isTrustedUrl(posted.actionUrl)) return AO3Result.Failure(
            AO3Error.Parse("Couldn't read AO3's sign-up form."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(posted.actionUrl, posted.parameters(), writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val body = response.value.body
                val parsed = try { AO3ChallengeSignUpParser().parse(body, form.slug) }
                    catch (_: Exception) { null }
                val error = parser.writeErrorMessage(body)
                when {
                    parsed != null && !parsed.isValid -> AO3Result.Success(
                        AO3SignUpSaveOutcome.Invalid(checked.copy(
                            fieldErrors = parsed.fieldErrors, generalErrors = parsed.generalErrors)))
                    error != null -> AO3Result.Success(AO3SignUpSaveOutcome.Invalid(
                        checked.copy(generalErrors = listOf(error))))
                    parser.writeSuccessMessage(body) != null || response.value.statusCode in 300..399 ->
                        AO3Result.Success(AO3SignUpSaveOutcome.Saved(parsed ?: posted))
                    else -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
                }
            }
        }
    }

    /** iOS claimPrompt: one fresh requests-page token and one single-shot POST. */
    suspend fun claimPrompt(slug: String, promptID: Int, expectedGeneration: Int): AO3Result<Unit> =
        changePromptClaim(AO3PromptMemeUrls.requests(slug), AO3PromptMemeUrls.claims(slug),
            promptID, expectedGeneration)

    /** iOS releasePrompt: one fresh for-user claims token and one single-shot delete override. */
    suspend fun releasePrompt(slug: String, claimID: Int, expectedGeneration: Int): AO3Result<Unit> =
        changePromptClaim(AO3PromptMemeUrls.claims(slug, forUser = true), AO3PromptMemeUrls.claim(slug, claimID),
            null, expectedGeneration)

    private suspend fun changePromptClaim(referer: String, action: String, promptID: Int?,
        expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the work on AO3."))
        val fields = if (promptID != null) listOf("authenticity_token" to token, "prompt_id" to promptID.toString())
            else listOf("_method" to "delete", "authenticity_token" to token)
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(action, fields, writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, if (promptID != null) "AO3 couldn't claim that prompt."
            else "AO3 couldn't release that prompt.")
    }

    /** iOS: fresh edit-page meta token, captured action/method, all four strings, one POST. */
    suspend fun saveTagSetFields(tagSet: AO3TagSetSnapshot, fields: Map<AO3TagSetField, String>,
        expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val referer = AO3TagSetUrls.edit(tagSet.id)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the work on AO3."))
        val action = tagSet.actionUrl
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't find AO3's tag-set form."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(action, tagSet.saveParameters(fields, token),
                writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, "AO3 couldn't save that tag set.")
    }

    /** iOS: bracket replacement precedes the shared form encoder; no success verification GET. */
    suspend fun reportRejectedTag(tagSetId: Int, nomination: AO3TagNomination, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.Validation("Log in to AO3 first."))
        val referer = AO3TagSetUrls.nominations(tagSetId)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the work on AO3."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(referer,
                listOf("_method" to "put", "authenticity_token" to token, nomination.rejectParameter()),
                writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, "AO3 couldn't reject that tag.")
    }

    /** One participants CSRF read and one tap-triggered, generation-fenced POST. */
    suspend fun decideCollectionMember(slug: String, id: Int, accept: Boolean, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val referer = AO3CollectionModerationUrls.participants(slug)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true) ?: return AO3Result.Failure(
            AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        val fields = buildList {
            add("_method" to if (accept) "patch" else "delete")
            add("authenticity_token" to token)
            if (accept) add("collection_participant[participant_role]" to "Member")
        }
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(AO3CollectionModerationUrls.participant(slug, id), fields,
                writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, if (accept) "AO3 couldn't update that member." else "AO3 couldn't decline that member.")
    }

    /** iOS revealCollection/unanonCollection: whole edit form, fresh meta token, one POST. */
    suspend fun revealCollection(slug: String, removeAnonymity: Boolean, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val html = when (val result = client.getAuthenticated(AO3CollectionFormUrls.form(slug))) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val form = try { withContext(Dispatchers.Default) { AO3CollectionFormParser().parse(html, slug) } }
        catch (error: CancellationException) { throw error }
        catch (error: Exception) { return AO3Result.Failure(AO3Error.Parse(error.message ?: "Couldn't read AO3's collection form.")) }
        requireCollectionSession(expectedGeneration)
        return when (val result = saveCollection(form.changed(
            AO3CollectionFields.preference(if (removeAnonymity) "anonymous" else "unrevealed"), "0"), expectedGeneration)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> when (val outcome = result.value) {
                is AO3CollectionSaveOutcome.Saved -> AO3Result.Success(Unit)
                is AO3CollectionSaveOutcome.Invalid -> AO3Result.Failure(AO3Error.Validation(
                    outcome.form.generalErrors.firstOrNull() ?: if (removeAnonymity) "Couldn't un-anon the collection." else "Couldn't reveal the collection."))
            }
        }
    }

    /** iOS inviteMaintainer intentionally sends no role, even though its screen offers a role choice. */
    suspend fun inviteMaintainer(slug: String, byline: String, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val invite = byline.trim()
        if (invite.isEmpty()) return AO3Result.Failure(AO3Error.Validation("Name someone to invite."))
        val referer = AO3CollectionParticipantsUrls.page(slug)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(AO3CollectionParticipantsUrls.add(slug),
                listOf("authenticity_token" to token, "participants_to_invite" to invite),
                writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, "AO3 couldn't invite that maintainer.")
    }

    /** iOS leaveCollection takes the fresh meta token from show, not the participants page. */
    suspend fun leaveCollection(slug: String, participantId: Int, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val referer = AO3CollectionFormUrls.show(slug)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(AO3CollectionParticipantsUrls.participant(slug, participantId),
                listOf("_method" to "delete", "authenticity_token" to token),
                writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, "AO3 couldn't leave that collection.")
    }

    /** iOS createCollection/updateCollection: fresh token, original action/fields, one POST. */
    suspend fun saveCollection(form: AO3CollectionForm, expectedGeneration: Int): AO3Result<AO3CollectionSaveOutcome> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        if (form.slug == null && !collectionNameFormatIsValid(form[AO3CollectionFields.NAME])) {
            return AO3Result.Success(AO3CollectionSaveOutcome.Invalid(form.copy(
                fieldErrors = form.fieldErrors + (AO3CollectionFields.NAME to AO3CollectionFields.INVALID_NAME))))
        }
        val referer = AO3CollectionFormUrls.form(form.slug)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        val token = parser.parseAuthenticityToken(html, metaOnly = true)
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        val posted = form.copy(csrfToken = token)
        currentCoroutineContext().ensureActive()
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(posted.actionUrl, posted.parameters(), writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> withContext(Dispatchers.Default) {
                val body = response.value.body
                val parsed = try { AO3CollectionFormParser().parse(body, form.slug) } catch (_: Exception) { null }
                val error = parser.writeErrorMessage(body)
                val notice = parser.writeSuccessMessage(body)
                    ?: "Collection was successfully created.".takeIf { body.contains("successfully created", true) }
                    ?: "Collection was successfully updated.".takeIf { body.contains("successfully updated", true) }
                when {
                    error != null -> AO3Result.Success(AO3CollectionSaveOutcome.Invalid((parsed ?: posted).copy(
                        generalErrors = (listOf(error) + parsed?.generalErrors.orEmpty()).distinct())))
                    notice != null -> AO3Result.Success(AO3CollectionSaveOutcome.Saved(parsed ?: posted, notice))
                    response.value.statusCode in 300..399 -> AO3Result.Success(AO3CollectionSaveOutcome.Saved(posted,
                        if (form.slug == null) "Collection created." else "Collection updated."))
                    response.value.statusCode in 200..299 && parsed != null &&
                        (parsed.generalErrors.isNotEmpty() || parsed.fieldErrors.isNotEmpty()) ->
                        AO3Result.Success(AO3CollectionSaveOutcome.Invalid(parsed))
                    else -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
                }
            }
        }
    }

    /** Owner-offered delete: token from the confirmation form (not its meta), then one method-override POST. */
    suspend fun deleteCollection(slug: String, expectedGeneration: Int): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val referer = AO3CollectionFormUrls.confirmDelete(slug)
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireCollectionSession(expectedGeneration)
        if (parser.parseAuthenticityToken(html, metaOnly = true) == null) return AO3Result.Failure(
            AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        val token = AO3CollectionFormParser().destroyToken(html)
            ?: return AO3Result.Failure(AO3Error.Validation("AO3 did not offer the collection delete confirmation. It was not deleted."))
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(AO3CollectionFormUrls.show(slug),
                listOf("_method" to "delete", "authenticity_token" to token), writeHeaders(token, referer), expectedGeneration)
        }
        movedOnAfterWrite(expectedGeneration)?.let { return it }
        return collectionWriteVerdict(response, "AO3 couldn't delete that collection.")
    }

    /**
     * For after a POST has gone out. The write may have landed, so a session that moved on
     * meanwhile is "AO3 didn't confirm", never the cancellation that screens word as "not
     * saved": a writer told that would send it again, or delete what they think is still
     * there (audit A24-1; iOS judges the answer it has and calls the rest unconfirmed).
     * Before the POST, [requireCollectionSession] still stops the write outright.
     */
    private fun movedOnAfterWrite(generation: Int, answer: AO3Result<*>? = null): AO3Result.Failure? = when {
        client.sessionGeneration() == generation -> null
        // AO3 answering the POST with its login page is AO3's refusal, and is itself what ended the session.
        answer is AO3Result.Failure && answer.error == AO3Error.AuthenticationRequired -> answer
        else -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
    }

    private fun requireCollectionSession(generation: Int) {
        if (client.sessionGeneration() != generation) throw CancellationException()
    }

    private fun collectionWriteVerdict(response: AO3Result<AO3HttpResponse>, fallback: String): AO3Result<Unit> = when (response) {
        is AO3Result.Failure -> response
        is AO3Result.Success -> {
            val error = parser.writeErrorMessage(response.value.body)
            when {
                error != null -> AO3Result.Failure(AO3Error.Validation(error))
                parser.writeSuccessMessage(response.value.body) != null || response.value.statusCode in 300..399 -> AO3Result.Success(Unit)
                response.value.statusCode in 200..299 -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
                else -> AO3Result.Failure(AO3Error.Validation(fallback))
            }
        }
    }

    /** iOS updateCollectionItems: one fresh form, sequential single-shot POSTs, stop on first refusal. */
    suspend fun updateCollectionItems(
        slug: String,
        drafts: List<AO3CollectionItemDraft>,
        expectedGeneration: Int
    ): AO3Result<Unit> {
        fun requireSession() {
            if (client.sessionGeneration() != expectedGeneration) throw CancellationException()
        }
        requireSession()
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        if (drafts.isEmpty()) return AO3Result.Success(Unit)
        val referer = AO3CollectionItemsUrls.page(
            slug, AO3CollectionItemTab.Unreviewed, 1
        )
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        requireSession()
        // fetchCSRFPage on iOS requires the page meta, even when the items parser can read an input.
        val token = parser.parseAuthenticityToken(html, metaOnly = true) ?: return AO3Result.Failure(
            AO3Error.Validation("Couldn't prepare the request. Try again, or open the collection on AO3."))
        val page = try {
            withContext(Dispatchers.Default) {
                AO3CollectionItemsParser().parse(
                    html, slug, AO3CollectionItemTab.Unreviewed, 1
                ).copy(csrfToken = token)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            return AO3Result.Failure(AO3Error.Parse(error.message ?: "Couldn't read AO3's items form."))
        }
        return submitCollectionItemDrafts(page, referer, drafts, expectedGeneration)
    }

    /** iOS updateUserCollectionItems: account-default CSRF page, then one ordered single-shot POST per draft. */
    suspend fun updateUserCollectionItems(
        username: String,
        drafts: List<AO3CollectionItemDraft>,
        expectedGeneration: Int
    ): AO3Result<Unit> {
        requireCollectionSession(expectedGeneration)
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        if (drafts.isEmpty()) return AO3Result.Success(Unit)
        val referer = AO3CollectionItemsUrls.userPage(username, AO3CollectionItemTab.Invited, 1)
        val fallbackAction = AO3CollectionItemsUrls.userUpdate(username)
        if (referer == null || fallbackAction == null) return AO3Result.Failure(AO3Error.Validation(
            "AO3 didn't give a collection-items page for this account."
        ))
        val response = client.getAuthenticated(referer)
        requireCollectionSession(expectedGeneration)
        val html = when (response) {
            is AO3Result.Failure -> return response
            is AO3Result.Success -> response.value.body
        }
        val page = withContext(Dispatchers.Default) {
            val token = parser.parseAuthenticityToken(html, metaOnly = true) ?: return@withContext null
            val parsed = try {
                AO3CollectionItemsParser().parseUser(html, username, AO3CollectionItemTab.Invited, 1)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null // iOS try? parse: a valid fresh meta token still permits the account fallback endpoint.
            }
            (parsed ?: AO3CollectionItemsPage(emptyList(), AO3CollectionItemTab.Invited, 1, 1,
                fallbackAction, token, "patch")).copy(csrfToken = token)
        } ?: return AO3Result.Failure(AO3Error.Validation(
            "Couldn't prepare the request. Try again, or open the collection on AO3."
        ))
        return submitCollectionItemDrafts(page, referer, drafts, expectedGeneration)
    }

    /** The existing moderation dispatch loop is shared by both scopes; it does not reorder its caller's drafts. */
    private suspend fun submitCollectionItemDrafts(
        page: AO3CollectionItemsPage,
        referer: String,
        drafts: List<AO3CollectionItemDraft>,
        expectedGeneration: Int
    ): AO3Result<Unit> {
        fun requireSession() = requireCollectionSession(expectedGeneration)
        for (draft in drafts) {
            currentCoroutineContext().ensureActive()
            requireSession()
            val response = withContext(NonCancellable) {
                client.postAuthenticatedInSession(
                    page.actionUrl, draft.parameters(page), writeHeaders(page.csrfToken, referer), expectedGeneration
                )
            }
            movedOnAfterWrite(expectedGeneration)?.let { return it }
            when (response) {
                is AO3Result.Failure -> return response
                is AO3Result.Success -> {
                    val body = response.value.body
                    val error = parser.writeErrorMessage(body)
                    when {
                        error != null -> return AO3Result.Failure(AO3Error.Validation(error))
                        AO3OverloadDetector.isOverloadPage(body) -> return AO3Result.Failure(
                            AO3Error.Overloaded(response.value.statusCode, null)
                        )
                        parser.writeSuccessMessage(body) != null || response.value.statusCode in 300..399 -> Unit
                        response.value.statusCode in 200..299 -> return AO3Result.Failure(AO3Error.Validation(
                            "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
                        ))
                        else -> return AO3Result.Failure(AO3Error.Validation("AO3 couldn't update that collection item."))
                    }
                }
            }
        }
        return AO3Result.Success(Unit)
    }

    suspend fun giveKudos(workId: Long): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()

        val response = client.postAuthenticated(
            url = AO3WriteUrls.kudosEndpoint(),
            formFields = listOf(
                "authenticity_token" to token,
                "kudo[commentable_id]" to workId.toString(),
                "kudo[commentable_type]" to "Work"
            ),
            headers = mapOf(
                "X-CSRF-Token" to token,
                "Referer" to workUrl,
                "X-Requested-With" to "XMLHttpRequest",
                "Accept" to "text/javascript, application/javascript, */*"
            )
        )
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val body = response.value.body
                when {
                    response.value.statusCode in 200..299 -> success(AO3WriteActionKind.Kudos, "Kudos left.")
                    response.value.statusCode == 422 && parser.alreadyKudosed(body) ->
                        success(AO3WriteActionKind.Kudos, "You've already left kudos here.")
                    else -> rejected(body, "AO3 didn't accept the kudos.")
                }
            }
        }
    }

    /**
     * Reads the live Subscribe/Unsubscribe form on the work page without writing.
     * Used by Work Detail so the overflow menu label matches AO3 before the user taps.
     */
    /** AO3WriteActions.swift:342–351: one signed-in advisory page, serving both labels. */
    suspend fun fetchWorkActionStates(workId: Long): AO3Result<Pair<AO3SubscriptionState, AO3BookmarkState>> {
        if (client.username() == null) return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val html = when (val page = client.getAuthenticated(AO3WriteUrls.workUrl(workId))) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        return AO3Result.Success(withContext(Dispatchers.Default) {
            parser.parseSubscription(html) to parser.parseBookmarkState(html)
        })
    }

    suspend fun fetchSubscriptionState(workId: Long): AO3Result<AO3SubscriptionState> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        return AO3Result.Success(
            withContext(Dispatchers.Default) { parser.parseSubscription(html) }
        )
    }

    suspend fun toggleSubscribe(workId: Long): AO3Result<AO3WriteOutcome> {
        val username = client.username() ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val state = withContext(Dispatchers.Default) { parser.parseSubscription(html) }

        return if (state.isSubscribed) {
            val unsubscribeUrl = state.unsubscribePath?.let(AO3WriteUrls::absoluteUrl)
                ?: return AO3Result.Failure(AO3Error.Validation("Couldn't find AO3's unsubscribe form."))
            val response = client.postAuthenticated(
                url = unsubscribeUrl,
                formFields = listOf("_method" to "delete", "authenticity_token" to token),
                headers = writeHeaders(token, workUrl)
            )
            response.toOutcome(AO3WriteActionKind.Unsubscribe, "Unsubscribed.", "Couldn't unsubscribe.", needsEvidence = true)
        } else {
            val response = client.postAuthenticated(
                url = AO3WriteUrls.subscriptionsEndpoint(username),
                formFields = listOf(
                    "authenticity_token" to token,
                    "subscription[subscribable_id]" to workId.toString(),
                    "subscription[subscribable_type]" to "Work"
                ),
                headers = writeHeaders(token, workUrl)
            )
            when (response) {
                is AO3Result.Failure -> response
                is AO3Result.Success -> {
                    if (response.value.body.contains("already subscribed", ignoreCase = true)) {
                        success(AO3WriteActionKind.Subscribe, "You're already subscribed.")
                    } else {
                        response.toOutcome(AO3WriteActionKind.Subscribe, "Subscribed.", "Couldn't subscribe.")
                    }
                }
            }
        }
    }

    /** iOS unsubscribe(path:page:): captured index action, fresh Works-index CSRF, one POST. */
    suspend fun unsubscribe(path: String, page: Int): AO3Result<AO3WriteOutcome> {
        val generation = client.sessionGeneration()
        val username = client.username() ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        val endpoint = AO3WriteUrls.absoluteUrl(path)
            ?.takeIf { AO3RedirectCookieRelay.isTrustedUrl(it) }
            ?: return AO3Result.Failure(AO3Error.Validation("Couldn't build the subscription address."))
        val referer = AO3AccountUrls().url(AccountListType.Subscriptions, username, page.coerceAtLeast(1))
        return indexWrite(generation, referer, endpoint, AO3WriteActionKind.Unsubscribe, "Unsubscribed.",
            "Couldn't unsubscribe.") { token -> listOf("_method" to "delete", "authenticity_token" to token) }
    }

    /**
     * iOS `deleteReading`: one row of AO3's reading history. The token comes from the history
     * page the row is on (the page that renders its form); the POST carries Rails' method
     * override and the reading's own id. Never run against AO3.
     */
    suspend fun deleteReading(readingId: Long, page: Int): AO3Result<AO3WriteOutcome> {
        val generation = client.sessionGeneration()
        val username = client.username() ?: return AO3Result.Failure(AO3Error.AuthenticationRequired)
        if (readingId <= 0) return AO3Result.Failure(AO3Error.Validation("Couldn't build the history address."))
        val shown = page.coerceAtLeast(1)
        val referer = AO3AccountUrls().url(AccountListType.History, username, shown)
        // The form passes the page through; page 1 has no query (iOS `deleteReadingURL`).
        val endpoint = AO3AccountUrls().url(AccountListType.History, username, 1).substringBefore('?') +
            "/$readingId" + if (shown > 1) "?page=$shown" else ""
        if (!AO3RedirectCookieRelay.isTrustedUrl(endpoint)) {
            return AO3Result.Failure(AO3Error.Validation("Couldn't build the history address."))
        }
        return indexWrite(generation, referer, endpoint, AO3WriteActionKind.History, "Removed from history.",
            "Couldn't remove that from history.") { token ->
            listOf("_method" to "delete", "authenticity_token" to token, "reading" to readingId.toString())
        }
    }

    /**
     * A write whose form lives on one of the account's index pages: a fresh general token
     * from that page, one POST never retried, and AO3's own evidence before "done"
     * (iOS `readingsWriteResult`).
     */
    private suspend fun indexWrite(
        generation: Int?, referer: String, endpoint: String, kind: AO3WriteActionKind, done: String,
        fallback: String, fields: (String) -> List<Pair<String, String>>
    ): AO3Result<AO3WriteOutcome> {
        val html = when (val result = client.getAuthenticated(referer)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value.body
        }
        if (client.sessionGeneration() != generation) throw CancellationException()
        val token = withContext(Dispatchers.Default) { parser.parseAuthenticityToken(html, metaOnly = true) }
            ?: return AO3Result.Failure(
                AO3Error.Validation("Couldn't prepare the request. Try again, or open the work on AO3.")
            )
        // A view may disappear after sending. Finish that single write; never retry it.
        val response = withContext(NonCancellable) {
            client.postAuthenticatedInSession(endpoint, fields(token), writeHeaders(token, referer), generation)
        }
        if (client.sessionGeneration() != generation)
            return AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
        return when (response) {
            is AO3Result.Failure -> response
            is AO3Result.Success -> {
                val body = response.value.body
                val error = parser.writeErrorMessage(body)
                when {
                    error != null -> AO3Result.Failure(AO3Error.Validation(error))
                    AO3OverloadDetector.isOverloadPage(body) ->
                        AO3Result.Failure(AO3Error.Overloaded(response.value.statusCode, null))
                    parser.writeSuccessMessage(body) != null || response.value.statusCode in 300..399 ->
                        success(kind, done)
                    response.value.statusCode in 200..399 -> AO3Result.Failure(AO3Error.Validation(
                        "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
                    ))
                    else -> rejected(body, fallback)
                }
            }
        }
    }

    suspend fun markForLater(workId: Long): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val response = client.postAuthenticated(
            url = AO3WriteUrls.markForLaterEndpoint(workId),
            formFields = listOf("_method" to "patch", "authenticity_token" to token),
            headers = writeHeaders(token, workUrl)
        )
        return response.toOutcome(AO3WriteActionKind.MarkForLater, "Marked for later.", "Couldn't mark for later.",
            needsEvidence = true)
    }

    suspend fun fetchBookmarkState(workId: Long): AO3Result<AO3BookmarkState> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        return AO3Result.Success(parser.parseBookmarkState(html))
    }

    suspend fun createBookmark(
        workId: Long,
        input: AO3BookmarkInput,
        pseudStore: io.github.cidy02.kudos.auth.AO3PostingPseudStore? = null
    ): AO3Result<AO3WriteOutcome> {
        val workUrl = AO3WriteUrls.workUrl(workId)
        val html = when (val page = client.getAuthenticated(workUrl)) {
            is AO3Result.Failure -> return page
            is AO3Result.Success -> page.value.body
        }
        val token = parseToken(html) ?: return missingToken()
        val state = parser.parseBookmarkState(html)

        // Preference resolution: caller-provided (UI dropdown) > persisted > AO3 default.
        val preferredPseudId = if (!input.pseudId.isNullOrEmpty()) {
            input.pseudId
        } else {
            val username = client.username()
            val persisted = if (username != null) pseudStore?.pseudName(username) else null
            state.availablePseuds.find { it.name.equals(persisted, true) }?.id
                ?: parser.parseDefaultPseudId(html, field = "bookmark[pseud_id]")
        }

        val fields = buildList {
            if (state.exists) {
                add("_method" to "put")
            }
            add("authenticity_token" to token)
            add("bookmark[bookmarker_notes]" to input.notes)
            add("bookmark[tag_string]" to input.tags)
            // Always re-scrape collection_names at submit time (iOS saveBookmark).
            // Never trust the caller's composer — it doesn't edit collections.
            add("bookmark[collection_names]" to state.collectionNames)
            add("bookmark[private]" to if (input.isPrivate) "1" else "0")
            add("bookmark[rec]" to if (input.isRecommendation) "1" else "0")
            preferredPseudId?.let {
                add("bookmark[pseud_id]" to it)
            }
        }
        val postUrl = if (state.exists) {
            state.editPath?.let(AO3WriteUrls::absoluteUrl)
                ?: return AO3Result.Failure(AO3Error.Validation("Couldn't find AO3's bookmark edit form."))
        } else {
            AO3WriteUrls.bookmarksEndpoint(workId)
        }
        val response = client.postAuthenticated(
            url = postUrl,
            formFields = fields,
            headers = writeHeaders(token, workUrl)
        )
        val successMessage = if (state.exists) "Bookmark updated." else "Bookmarked."
        
        // Persist the pseud choice on success.
        if (response is AO3Result.Success && preferredPseudId != null && !state.exists) {
            val chosenName = state.availablePseuds.find { it.id == preferredPseudId }?.name
            val username = client.username()
            if (chosenName != null && username != null) {
                pseudStore?.setPseudName(chosenName, username)
            }
        }

        return response.toOutcome(AO3WriteActionKind.Bookmark, successMessage, "Couldn't bookmark this work.")
    }

    private suspend fun parseToken(html: String): String? {
        return withContext(Dispatchers.Default) { parser.parseAuthenticityToken(html) }
    }

    private fun AO3Result<AO3HttpResponse>.toOutcome(
        kind: AO3WriteActionKind,
        successMessage: String,
        fallbackError: String,
        needsEvidence: Boolean = false
    ): AO3Result<AO3WriteOutcome> {
        return when (this) {
            is AO3Result.Failure -> this
            is AO3Result.Success -> when {
                value.statusCode !in 200..399 || parser.writeErrorMessage(value.body) != null ->
                    rejected(value.body, fallbackError)
                !needsEvidence || value.statusCode in 300..399 || parser.writeSuccessMessage(value.body) != null ->
                    success(kind, successMessage)
                // iOS readingsWriteResult: a flashless 2xx (a maintenance page) is not AO3
                // confirming this write (audit A4-6).
                else -> AO3Result.Failure(AO3Error.Validation(AO3CollectionFields.UNCONFIRMED))
            }
        }
    }

    private fun writeHeaders(token: String, referer: String): Map<String, String> {
        return mapOf(
            "X-CSRF-Token" to token,
            "Referer" to referer
        )
    }

    private fun success(kind: AO3WriteActionKind, message: String): AO3Result.Success<AO3WriteOutcome> {
        return AO3Result.Success(AO3WriteOutcome(kind, message))
    }

    private fun rejected(html: String, fallback: String): AO3Result.Failure {
        return AO3Result.Failure(AO3Error.Validation(parser.writeErrorMessage(html) ?: fallback))
    }

    private fun missingToken(): AO3Result.Failure {
        return AO3Result.Failure(AO3Error.Validation("Couldn't prepare the AO3 request. Open the work on AO3 and try there."))
    }
}
