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

/** Appends one structured-text line's characters (UTF-32 runes) as UTF-8. */
static void kudos_append_line(fz_stext_line *line, fz_buffer *buffer, fz_context *ctx) {
    char scratch[8];
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        int written = fz_runetochar(scratch, ch->c);
        fz_append_data(ctx, buffer, scratch, (size_t) written);
    }
}

static jstring kudos_buffer_to_jstring(JNIEnv *env, fz_context *ctx, fz_buffer *buffer) {
    unsigned char *data = NULL;
    size_t length = fz_buffer_storage(ctx, buffer, &data);
    if (length == 0 || data == NULL) return NULL;
    // NUL-terminate for NewStringUTF, which takes a C string.
    fz_terminate_buffer(ctx, buffer);
    fz_buffer_storage(ctx, buffer, &data);
    return (*env)->NewStringUTF(env, (const char *) data);
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

    // Every MuPDF call that can longjmp is inside fz_try. Without this a
    // malformed PDF — which is most of what this feature exists for — takes the
    // whole process down instead of failing one import.
    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path);
        int pageCount = fz_count_pages(ctx, doc);
        pages = (*env)->NewObjectArray(env, pageCount, stringArrayClass, NULL);

        for (int index = 0; index < pageCount; index++) {
            fz_stext_options options = { 0 };
            fz_stext_page *stext = NULL;
            // Bounded: a page rarely has more blocks than this, and the cap keeps
            // a hostile document from making us allocate without limit.
            const int maxEntries = 4096;
            jstring entries[4096];
            int count = 0;

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
                            if (!first) fz_append_byte(ctx, buf, ' ');
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
            for (int i = 0; i < count; i++) {
                (*env)->SetObjectArrayElement(env, pageArray, i, entries[i]);
                (*env)->DeleteLocalRef(env, entries[i]);
            }
            (*env)->SetObjectArrayElement(env, pages, index, pageArray);
            (*env)->DeleteLocalRef(env, pageArray);
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
