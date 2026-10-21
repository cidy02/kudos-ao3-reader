package io.github.cidy02.kudos.auth

import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.*
import org.junit.Test

class AO3NativeLoginScriptTest {
    @Test fun checksRememberMeBeforeSubmittingOnlyOnAo3Https() {
        val script = AO3NativeLoginScript.fill("reader", "local-test")
        assertTrue(script.contains("location.protocol !== 'https:'"))
        assertTrue(script.contains("location.hostname !== 'archiveofourown.org'"))
        assertTrue(script.contains("#user_remember_me"))
        assertTrue(script.contains("user[remember_me]"))
        assertTrue(script.indexOf("r.checked = true") < script.indexOf("form.submit()"))
    }

    @Test fun credentialsAreJsonLiteralsIncludingQuotesAndControlCharacters() {
        val credential = "quote\" slash\\ newline\n tab\t carriage\r"
        val script = AO3NativeLoginScript.fill(credential, credential)
        assertTrue(script.contains("u.value = ${JsonPrimitive(credential)};"))
        assertTrue(script.contains("p.value = ${JsonPrimitive(credential)};"))
    }

    @Test fun missingFormFieldsOrMalformedResultCannotReportSubmission() {
        assertTrue(AO3NativeLoginScript.submitted("\"{\\\"ok\\\":true}\""))
        for (raw in listOf(null, "null", "broken", "{}", "\"{\\\"ok\\\":false,\\\"reason\\\":\\\"no-form\\\"}\"",
            "{\"ok\":false,\"reason\":\"no-fields\"}")) {
            assertFalse(AO3NativeLoginScript.submitted(raw))
        }
    }

    @Test fun submittedPageWithoutFlashErrorRequiresVisibleFallback() {
        assertTrue(AO3NativeLoginScript.requiresFallback(AO3WebLoginInspection(false, null)))
        assertFalse(AO3NativeLoginScript.requiresFallback(AO3WebLoginInspection(false, null, "Invalid password")))
        assertFalse(AO3NativeLoginScript.requiresFallback(AO3WebLoginInspection(true, "reader")))
    }

    @Test fun ao3FlashErrorsDecodeEscapedQuotesNewlinesAndUnicode() {
        val message = "Sorry, \"reader\".\nTry again — please."
        val payload = "{\"loggedIn\":false,\"username\":null,\"errorMessage\":${JsonPrimitive(message)}}"
        val inspection = AO3WebLoginInspection.parseJavascriptResult(JsonPrimitive(payload).toString())
        assertFalse(inspection.loggedIn)
        assertNull(inspection.username)
        assertEquals(message, inspection.errorMessage)
        assertNull(AO3WebLoginInspection.parseJavascriptResult("{\"errorMessage\":\"  \"}").errorMessage)
        assertEquals(AO3WebLoginInspection(false, null), AO3WebLoginInspection.parseJavascriptResult("malformed"))
        assertTrue(AO3WebLoginInspection.Script.contains("#main .flash.error, #main .error, .flash.error, .flash.alert"))
    }
}
