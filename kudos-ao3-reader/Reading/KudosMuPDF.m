#import "KudosMuPDF.h"

#import <mupdf/fitz.h>

/// Whether a structured-text block/line should be flattened as one paragraph or as
/// separate lines.
typedef NS_ENUM(NSInteger, KudosMuPDFGranularity) {
    KudosMuPDFGranularityParagraph,
    KudosMuPDFGranularityLine
};

@implementation KudosMuPDF

/// Appends one structured-text line's characters to `buffer`.
static void KudosAppendLine(fz_stext_line *line, NSMutableString *buffer) {
    // Characters are UTF-32 runes; convert each and append. A per-line NSMutableData
    // avoids one autoreleased NSString per glyph on a 170-page document.
    NSMutableData *utf8 = [NSMutableData dataWithCapacity:128];
    char scratch[8];
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        int written = fz_runetochar(scratch, ch->c);
        [utf8 appendBytes:scratch length:(NSUInteger)written];
    }
    NSString *text = [[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding];
    if (text != nil) {
        [buffer appendString:text];
    }
}

+ (nullable NSArray<NSArray<NSString *> *> *)extractFromPDFAtPath:(NSString *)path
                                                     granularity:(KudosMuPDFGranularity)granularity {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        return nil;
    }

    NSMutableArray<NSArray<NSString *> *> *pages = [NSMutableArray array];
    fz_document *doc = NULL;

    // MuPDF signals errors by longjmp, so every call that can throw sits inside
    // fz_try. Without this a malformed PDF — which is most of what this feature
    // imports — would take the process down instead of returning nil.
    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path.fileSystemRepresentation);
        int pageCount = fz_count_pages(ctx, doc);

        for (int index = 0; index < pageCount; index++) {
            fz_stext_options options = { 0 };
            fz_stext_page *stext = NULL;
            NSMutableArray<NSString *> *entries = [NSMutableArray array];

            // Per-page fz_try: one unreadable page yields an empty page rather than
            // abandoning the whole document, which matters for a 170-page work whose
            // last chapter is fine.
            fz_try(ctx) {
                stext = fz_new_stext_page_from_page_number(ctx, doc, index, &options);
                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) {
                        continue;
                    }
                    if (granularity == KudosMuPDFGranularityLine) {
                        for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                            NSMutableString *text = [NSMutableString string];
                            KudosAppendLine(line, text);
                            if (text.length > 0) {
                                [entries addObject:text];
                            }
                        }
                    } else {
                        // One block is one paragraph; its lines are wrapped display
                        // lines and join with a single space.
                        NSMutableString *text = [NSMutableString string];
                        for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                            if (text.length > 0) {
                                [text appendString:@" "];
                            }
                            KudosAppendLine(line, text);
                        }
                        if (text.length > 0) {
                            [entries addObject:text];
                        }
                    }
                }
            }
            fz_always(ctx) {
                fz_drop_stext_page(ctx, stext);
            }
            fz_catch(ctx) {
                // Keep going; `entries` holds whatever this page yielded.
            }

            [pages addObject:entries];
        }
    }
    fz_always(ctx) {
        fz_drop_document(ctx, doc);
    }
    fz_catch(ctx) {
        fz_drop_context(ctx);
        return nil;
    }

    fz_drop_context(ctx);
    return pages;
}

+ (nullable NSArray<NSArray<NSString *> *> *)paragraphsPerPageForPDFAtPath:(NSString *)path {
    return [self extractFromPDFAtPath:path granularity:KudosMuPDFGranularityParagraph];
}

+ (nullable NSArray<NSArray<NSString *> *> *)linesPerPageForPDFAtPath:(NSString *)path {
    return [self extractFromPDFAtPath:path granularity:KudosMuPDFGranularityLine];
}

@end
