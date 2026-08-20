// Thin JNI shim over MuPDF's structured-text API.
//
// Android counterpart of iOS's KudosMuPDF.m — same two entry points, same
// algorithm, same reasons. Only strings cross the boundary; MuPDF's C API and
// its manual reference counting stay on this side of it.
//
// Why MuPDF at all: PDFKit/PdfRenderer expose a *text* API, not a *layout* one.
// See the iOS docs/PDF_ENGINE_MUPDF.md for the five defects that produced,
// the worst being prose silently relocated into the wrong paragraph.

#include <jni.h>
#include <string.h>
#include <mupdf/fitz.h>

#define KUDOS_EXPORT __attribute__((visibility("default")))

/** Whether a block is flattened into one paragraph, or emitted line by line. */
typedef enum {
    KudosGranularityParagraph = 0,
    KudosGranularityLine = 1
} KudosGranularity;

/**
 * Appends one Unicode codepoint to `buffer` as native-order UTF-16 code
 * unit(s) — one for a BMP codepoint, a surrogate pair above it. JNI's
 * `NewString` takes `jchar*`/UTF-16, not UTF-8; feeding it raw UTF-8 via
 * `NewStringUTF` (JNI's *Modified* UTF-8, which forbids 4-byte sequences)
 * aborts the process under CheckJNI on any character outside the BMP —
 * emoji, some CJK extension characters, anything an AO3 author's note can
 * contain. A lone surrogate value from `fz_runetochar`'s rune isn't a valid
 * standalone codepoint, so it's substituted with U+FFFD rather than passed
 * through and corrupting the UTF-16 stream.
 */
static void kudos_append_utf16(fz_context *ctx, fz_buffer *buffer, int rune) {
    if (rune < 0 || (rune >= 0xD800 && rune <= 0xDFFF)) {
        rune = 0xFFFD;
    }
    if (rune <= 0xFFFF) {
        jchar unit = (jchar) rune;
        fz_append_data(ctx, buffer, &unit, sizeof(unit));
    } else {
        int v = rune - 0x10000;
        jchar hi = (jchar) (0xD800 + (v >> 10));
        jchar lo = (jchar) (0xDC00 + (v & 0x3FF));
        fz_append_data(ctx, buffer, &hi, sizeof(hi));
        fz_append_data(ctx, buffer, &lo, sizeof(lo));
    }
}

/** Appends one structured-text line's characters as UTF-16 code units. */
static void kudos_append_line(fz_stext_line *line, fz_buffer *buffer, fz_context *ctx) {
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        kudos_append_utf16(ctx, buffer, ch->c);
    }
}

/** `buffer` holds native-order UTF-16 code units (see kudos_append_utf16). */
static jstring kudos_buffer_to_jstring(JNIEnv *env, fz_context *ctx, fz_buffer *buffer) {
    unsigned char *data = NULL;
    size_t length = fz_buffer_storage(ctx, buffer, &data);
    if (length == 0 || data == NULL) return NULL;
    jsize unitCount = (jsize) (length / sizeof(jchar));
    if (unitCount == 0) return NULL;
    return (*env)->NewString(env, (const jchar *) data, unitCount);
}

/**
 * Returns String[][]: one entry per page, each holding that page's text at the
 * requested granularity, in reading order. NULL when the document can't be
 * opened at all, so the caller can fall back rather than import nothing.
 */
static jobjectArray kudos_extract(JNIEnv *env, jstring jpath, KudosGranularity granularity) {
    const char *path = (*env)->GetStringUTFChars(env, jpath, NULL);
    if (path == NULL) return NULL;

    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        (*env)->ReleaseStringUTFChars(env, jpath, path);
        return NULL;
    }

    jclass stringArrayClass = (*env)->FindClass(env, "[Ljava/lang/String;");
    jclass stringClass = (*env)->FindClass(env, "java/lang/String");
    jobjectArray pages = NULL;
    fz_document *doc = NULL;
    // A page rarely has more blocks than this; the cap also bounds the
    // per-page local-JNI-ref frame requested below against a hostile PDF.
    const int maxEntries = 4096;
    // Bounds allocation against a hostile /Count; no real work has anywhere
    // near this many pages.
    const int maxPages = 20000;

    fz_var(doc);
    fz_var(pages);

    // Every MuPDF call that can longjmp is inside fz_try. Without this a
    // malformed PDF — which is most of what this feature exists for — takes the
    // whole process down instead of failing one import. Locals assigned inside
    // fz_try and read in fz_always/fz_catch (or after a catch) must be fz_var'd:
    // fz_try is setjmp/longjmp, and an un-fz_var'd local can roll back to its
    // pre-try value across the jump under optimization.
    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path);
        int pageCount = fz_count_pages(ctx, doc);
        if (pageCount < 0) pageCount = 0;
        if (pageCount > maxPages) pageCount = maxPages;
        pages = (*env)->NewObjectArray(env, pageCount, stringArrayClass, NULL);
        if (pages == NULL) fz_throw(ctx, FZ_ERROR_GENERIC, "NewObjectArray(pages) failed");

        for (int index = 0; index < pageCount; index++) {
            fz_stext_options options = { 0 };
            fz_stext_page *stext = NULL;
            jstring entries[4096];
            int count = 0;

            fz_var(stext);
            fz_var(count);

            // Local refs for every entry on the page live only inside this
            // frame — freeing them all at PopLocalFrame, rather than one by
            // one, is what keeps a dense page (many short lines) under ART's
            // local-reference-table limit (JNI guarantees only 16 by default;
            // ART's is larger but still far short of maxEntries).
            if ((*env)->PushLocalFrame(env, maxEntries + 32) < 0) {
                continue; // OOM reserving frame capacity — skip this page.
            }

            // Per-page fz_try: one unreadable page yields an empty page rather
            // than abandoning the document, which matters for a 170-page work
            // whose last page is damaged.
            fz_try(ctx) {
                stext = fz_new_stext_page_from_page_number(ctx, doc, index, &options);
                for (fz_stext_block *block = stext->first_block;
                     block != NULL && count < maxEntries; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) continue;

                    if (granularity == KudosGranularityLine) {
                        for (fz_stext_line *line = block->u.t.first_line;
                             line != NULL && count < maxEntries; line = line->next) {
                            fz_buffer *buf = fz_new_buffer(ctx, 256);
                            kudos_append_line(line, buf, ctx);
                            jstring s = kudos_buffer_to_jstring(env, ctx, buf);
                            fz_drop_buffer(ctx, buf);
                            if (s != NULL) entries[count++] = s;
                        }
                    } else {
                        // One block is one paragraph; its lines are wrapped
                        // display lines and join with a single space.
                        fz_buffer *buf = fz_new_buffer(ctx, 512);
                        int first = 1;
                        for (fz_stext_line *line = block->u.t.first_line;
                             line != NULL; line = line->next) {
                            if (!first) kudos_append_utf16(ctx, buf, ' ');
                            first = 0;
                            kudos_append_line(line, buf, ctx);
                        }
                        jstring s = kudos_buffer_to_jstring(env, ctx, buf);
                        fz_drop_buffer(ctx, buf);
                        if (s != NULL) entries[count++] = s;
                    }
                }
            }
            fz_always(ctx) {
                fz_drop_stext_page(ctx, stext);
            }
            fz_catch(ctx) {
                // Keep going; `entries` holds whatever this page yielded.
            }

            jobjectArray pageArray = (*env)->NewObjectArray(env, count, stringClass, NULL);
            if (pageArray != NULL) {
                for (int i = 0; i < count; i++) {
                    (*env)->SetObjectArrayElement(env, pageArray, i, entries[i]);
                }
            }
            // Pops every local ref created since PushLocalFrame (ctx, stext,
            // all `entries`) and re-homes pageArray as a single local ref in
            // the caller's (outer try's) frame.
            pageArray = (*env)->PopLocalFrame(env, pageArray);
            if (pageArray != NULL) {
                (*env)->SetObjectArrayElement(env, pages, index, pageArray);
                (*env)->DeleteLocalRef(env, pageArray);
            }
        }
    }
    fz_always(ctx) {
        fz_drop_document(ctx, doc);
    }
    fz_catch(ctx) {
        pages = NULL;
    }

    fz_drop_context(ctx);
    (*env)->ReleaseStringUTFChars(env, jpath, path);
    return pages;
}

KUDOS_EXPORT JNIEXPORT jobjectArray JNICALL
Java_io_github_cidy02_kudos_works_converters_KudosMuPDF_nativeParagraphsPerPage(
        JNIEnv *env, jclass clazz, jstring path) {
    (void) clazz;
    return kudos_extract(env, path, KudosGranularityParagraph);
}

KUDOS_EXPORT JNIEXPORT jobjectArray JNICALL
Java_io_github_cidy02_kudos_works_converters_KudosMuPDF_nativeLinesPerPage(
        JNIEnv *env, jclass clazz, jstring path) {
    (void) clazz;
    return kudos_extract(env, path, KudosGranularityLine);
}
