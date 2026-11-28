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

/// What a drawn scene break becomes in the extracted text (the same string the converter uses for typed ones).
static NSString *const KudosSceneBreakMarker = @"* * *";

typedef struct {
    float y;
    float x0;
    float x1;
} KudosRule;

static int KudosCompareRules(const void *va, const void *vb) {
    float ay = ((const KudosRule *)va)->y;
    float by = ((const KudosRule *)vb)->y;
    if (ay < by) return -1;
    if (ay > by) return 1;
    return 0;
}

/// A vertical border of a table or a box around a quote. Its own bbox is tall, so the horizontal sides are what
/// would otherwise pass the scene-break test; this catches those sides.
static BOOL KudosVerticalStrokeCrosses(fz_rect rule, fz_stext_block *self, fz_stext_page *page) {
    float midY = (rule.y0 + rule.y1) / 2;
    for (fz_stext_block *other = page->first_block; other != NULL; other = other->next) {
        if (other == self || other->type != FZ_STEXT_BLOCK_VECTOR) {
            continue;
        }
        if ((other->u.v.flags & FZ_STEXT_VECTOR_IS_RECTANGLE) == 0) {
            continue;
        }
        fz_rect box = other->bbox;
        if (box.x1 - box.x0 > 4 || box.y1 - box.y0 <= 4) {
            continue;
        }
        float midX = (box.x0 + box.x1) / 2;
        if (midX < rule.x0 || midX > rule.x1) {
            continue;
        }
        if (box.y0 <= midY && midY <= box.y1) {
            return YES;
        }
    }
    return NO;
}

/// The vertical centres, top to bottom, of horizontal rules that separate paragraphs. A vector at most 4 pt tall and
/// at least 40% of the page wide, in the page and not in its outer 12 pt (a rule along the page edge). A vertical
/// stroke crossing it is a table or a box, not a break. Crossing a text line means sharing that line's x range as
/// well as its height, so a strike-through counts and a rule beside a margin note, or beside the other column, does
/// not. A rule between two lines of one block still counts. Rules within 6 pt of each other and overlapping in x are
/// one rule (calibre strokes an `<hr>` as two overlapping paths).
/// shortcut: a break is inserted by page height, so two columns can put it in the wrong column; fan fiction PDFs are
/// single-column, revisit if a multi-column import shows it.
static NSArray<NSNumber *> *KudosSceneBreakRules(fz_stext_page *page) {
    float pageWidth = page->mediabox.x1 - page->mediabox.x0;
    if (pageWidth < 1) {
        return @[];
    }
    NSMutableData *found = [NSMutableData data];
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_VECTOR) {
            continue;
        }
        fz_rect box = block->bbox;
        if (box.y1 - box.y0 > 4 || box.x1 - box.x0 < pageWidth * 0.4f) {
            continue;
        }
        float centre = (box.y0 + box.y1) / 2;
        // `mediabox` is the crop box in the same space as the vectors (origin at the top left, y downward),
        // including a rotated or offset page. A rule outside that box, or in the outer 12 pt, is a page edge.
        if (centre - page->mediabox.y0 < 12 || page->mediabox.y1 - centre < 12) {
            continue;
        }
        if (KudosVerticalStrokeCrosses(box, block, page)) {
            continue;
        }
        BOOL crossesText = NO;
        for (fz_stext_block *text = page->first_block; text != NULL && !crossesText; text = text->next) {
            if (text->type != FZ_STEXT_BLOCK_TEXT) {
                continue;
            }
            for (fz_stext_line *line = text->u.t.first_line; line != NULL; line = line->next) {
                if (centre < line->bbox.y0 || centre > line->bbox.y1) {
                    continue;
                }
                if (box.x0 <= line->bbox.x1 && box.x1 >= line->bbox.x0) {
                    crossesText = YES;
                    break;
                }
            }
        }
        if (crossesText) {
            continue;
        }
        KudosRule rule = { centre, box.x0, box.x1 };
        [found appendBytes:&rule length:sizeof(rule)];
    }
    NSUInteger count = found.length / sizeof(KudosRule);
    KudosRule *rules = found.mutableBytes;
    if (count > 1) {
        qsort(rules, count, sizeof(KudosRule), KudosCompareRules);
    }
    // Drop a second stroke of a rule already kept. The window is the kept rule, not the previous raw one, so a
    // stroke in the other column between the two passes of one `<hr>` does not hide the second pass.
    NSUInteger kept = 0;
    for (NSUInteger index = 0; index < count; index++) {
        KudosRule rule = rules[index];
        BOOL sameStroke = NO;
        for (NSUInteger prior = 0; prior < kept; prior++) {
            if (rule.y - rules[prior].y <= 6 && rules[prior].x0 <= rule.x1 && rule.x0 <= rules[prior].x1) {
                sameStroke = YES;
                break;
            }
        }
        if (!sameStroke) {
            rules[kept++] = rule;
        }
    }
    NSMutableArray<NSNumber *> *centres = [NSMutableArray arrayWithCapacity:kept];
    for (NSUInteger index = 0; index < kept; index++) {
        [centres addObject:@(rules[index].y)];
    }
    return centres;
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
            // Paragraph mode also collects vector drawings, so a scene break drawn as a rule (FanFiction.net's <hr>,
            // which calibre draws as a thin grey line) can come back as a `* * *` paragraph instead of vanishing.
            if (granularity == KudosMuPDFGranularityParagraph) {
                options.flags = FZ_STEXT_COLLECT_VECTORS;
            }
            fz_stext_page *stext = NULL;
            NSMutableArray<NSString *> *entries = [NSMutableArray array];

            // Per-page fz_try: one unreadable page yields an empty page rather than
            // abandoning the whole document, which matters for a 170-page work whose
            // last chapter is fine.
            fz_try(ctx) {
                stext = fz_new_stext_page_from_page_number(ctx, doc, index, &options);
                NSArray<NSNumber *> *rules = granularity == KudosMuPDFGranularityParagraph
                    ? KudosSceneBreakRules(stext) : @[];
                NSUInteger nextRule = 0;
                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) {
                        continue;
                    }
                    // Rules above this block come first, in page order.
                    while (nextRule < rules.count && rules[nextRule].floatValue < block->bbox.y0) {
                        [entries addObject:KudosSceneBreakMarker];
                        nextRule++;
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
                        // lines and join with a single space. A scene-break rule between two of its lines splits it.
                        NSMutableString *text = [NSMutableString string];
                        for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                            if (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                                if (text.length > 0) {
                                    [entries addObject:[text copy]];
                                    [text setString:@""];
                                }
                                while (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                                    [entries addObject:KudosSceneBreakMarker];
                                    nextRule++;
                                }
                            }
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
                while (nextRule < rules.count) {
                    [entries addObject:KudosSceneBreakMarker];
                    nextRule++;
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
