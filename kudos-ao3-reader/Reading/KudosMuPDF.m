#import "KudosMuPDF.h"

#import <mupdf/fitz.h>
#import <string.h>

@implementation KudosPDFBlock

- (instancetype)initWithText:(NSString *)text
                italicRanges:(NSArray<NSValue *> *)italicRanges
                  boldRanges:(NSArray<NSValue *> *)boldRanges {
    self = [super init];
    if (self != nil) {
        _text = [text copy];
        _italicRanges = [italicRanges copy];
        _boldRanges = [boldRanges copy];
    }
    return self;
}

@end

@implementation KudosMuPDF

static char KudosASCIILower(char ch) {
    return (ch >= 'A' && ch <= 'Z') ? (char)(ch + ('a' - 'A')) : ch;
}

static BOOL KudosASCIIContains(const char *haystack, const char *needle) {
    if (haystack == NULL || needle == NULL || needle[0] == '\0') {
        return NO;
    }
    for (const char *cursor = haystack; *cursor != '\0'; cursor++) {
        const char *left = cursor;
        const char *right = needle;
        while (*left != '\0' && *right != '\0' && KudosASCIILower(*left) == KudosASCIILower(*right)) {
            left++;
            right++;
        }
        if (*right == '\0') {
            return YES;
        }
    }
    return NO;
}

static BOOL KudosASCIIEndsWith(const char *string, const char *suffix) {
    size_t stringLen = strlen(string);
    size_t suffixLen = strlen(suffix);
    if (suffixLen > stringLen) {
        return NO;
    }
    const char *tail = string + (stringLen - suffixLen);
    for (size_t index = 0; index < suffixLen; index++) {
        if (KudosASCIILower(tail[index]) != KudosASCIILower(suffix[index])) {
            return NO;
        }
    }
    return YES;
}

static void KudosClassifyFont(fz_context *ctx, fz_font *font, BOOL *outItalic, BOOL *outBold) {
    if (font == NULL) {
        *outItalic = NO;
        *outBold = NO;
        return;
    }

    fz_font_flags_t *flags = fz_font_flags(font);
    BOOL italic = fz_font_is_italic(ctx, font) != 0 || (flags != NULL && flags->fake_italic != 0);
    BOOL bold = fz_font_is_bold(ctx, font) != 0 || (flags != NULL && flags->fake_bold != 0);

    const char *name = fz_font_name(ctx, font);
    if (name != NULL && name[0] != '\0') {
        size_t nameLen = strlen(name);
        if (!italic) {
            italic = KudosASCIIContains(name, "italic")
                || KudosASCIIContains(name, "oblique")
                || KudosASCIIEndsWith(name, "-ital")
                || KudosASCIIEndsWith(name, "reguital")
                || KudosASCIIEndsWith(name, "boldital")
                || KudosASCIIEndsWith(name, "lighital")
                || KudosASCIIEndsWith(name, "mediital");
            // MuPDF stores font names in a 32-byte buffer (31 chars + NUL), so a subset
            // name like `ABCDEF+LiberationSerif-BoldItalic` truncates to `…-BoldItal`.
            if (!italic && nameLen == 31) {
                italic = KudosASCIIEndsWith(name, "itali")
                    || KudosASCIIEndsWith(name, "ital")
                    || KudosASCIIEndsWith(name, "-ita")
                    || KudosASCIIEndsWith(name, ",ita")
                    || KudosASCIIEndsWith(name, "boldita")
                    || KudosASCIIEndsWith(name, "obliqu")
                    || KudosASCIIEndsWith(name, "obliq")
                    || KudosASCIIEndsWith(name, "obli")
                    || KudosASCIIEndsWith(name, "-obl")
                    || KudosASCIIEndsWith(name, ",obl")
                    || KudosASCIIEndsWith(name, "boldobl");
            }
        }
        if (!bold) {
            bold = KudosASCIIContains(name, "bold")
                || KudosASCIIContains(name, "black")
                || KudosASCIIContains(name, "heavy")
                || KudosASCIIContains(name, "semibold");
            if (!bold && nameLen == 31) {
                bold = KudosASCIIEndsWith(name, "-bol")
                    || KudosASCIIEndsWith(name, ",bol")
                    || KudosASCIIEndsWith(name, "-blac")
                    || KudosASCIIEndsWith(name, "-heav")
                    || KudosASCIIEndsWith(name, "-semib")
                    || KudosASCIIEndsWith(name, "-semibo")
                    || KudosASCIIEndsWith(name, "-semibol");
            }
        }
    }

    *outItalic = italic;
    *outBold = bold;
}

static void KudosAppendRange(NSMutableArray<NSValue *> *ranges, NSUInteger location, NSUInteger length) {
    if (length == 0) {
        return;
    }
    if (ranges.count > 0) {
        NSRange last = ranges.lastObject.rangeValue;
        if (NSMaxRange(last) == location) {
            ranges[ranges.count - 1] = [NSValue valueWithRange:NSMakeRange(last.location, last.length + length)];
            return;
        }
    }
    [ranges addObject:[NSValue valueWithRange:NSMakeRange(location, length)]];
}

static BOOL KudosIsWhitespaceUnit(unichar unit) {
    return unit == ' ' || unit == '\t' || unit == '\n' || unit == '\r' || unit == 0x00A0;
}

static NSArray<NSValue *> *KudosNormalizeRanges(NSString *text, NSArray<NSValue *> *rawRanges) {
    NSUInteger textLength = text.length;
    if (rawRanges.count == 0 || textLength == 0) {
        return @[];
    }

    // Merge adjacent/overlapping ranges and single spaces separating two runs of the same style
    // (including line-join spaces and regular-font spaces inside styled phrases).
    NSMutableArray<NSValue *> *merged = [NSMutableArray arrayWithCapacity:rawRanges.count];
    for (NSValue *value in rawRanges) {
        NSRange range = value.rangeValue;
        if (range.location >= textLength || range.length == 0) {
            continue;
        }
        NSUInteger end = MIN(NSMaxRange(range), textLength);
        range = NSMakeRange(range.location, end - range.location);

        if (merged.count > 0) {
            NSRange prev = merged.lastObject.rangeValue;
            NSUInteger prevEnd = NSMaxRange(prev);
            BOOL adjacent = range.location <= prevEnd;
            BOOL singleSpace = NO;
            if (!adjacent && range.location == prevEnd + 1) {
                unichar gap = [text characterAtIndex:prevEnd];
                singleSpace = (gap == ' ' || gap == 0x00A0);
            }
            if (adjacent || singleSpace) {
                NSUInteger newEnd = MAX(prevEnd, NSMaxRange(range));
                merged[merged.count - 1] = [NSValue valueWithRange:NSMakeRange(prev.location, newEnd - prev.location)];
                continue;
            }
        }
        [merged addObject:[NSValue valueWithRange:range]];
    }

    // Trim boundary whitespace so MuPDF synthetic spaces after an italic/bold glyph do not
    // pull separating spaces inside the styled tag.
    NSMutableArray<NSValue *> *trimmed = [NSMutableArray arrayWithCapacity:merged.count];
    for (NSValue *value in merged) {
        NSRange range = value.rangeValue;
        NSUInteger start = range.location;
        NSUInteger end = NSMaxRange(range);
        while (start < end && KudosIsWhitespaceUnit([text characterAtIndex:start])) {
            start++;
        }
        while (end > start && KudosIsWhitespaceUnit([text characterAtIndex:end - 1])) {
            end--;
        }
        if (end > start) {
            [trimmed addObject:[NSValue valueWithRange:NSMakeRange(start, end - start)]];
        }
    }
    return [trimmed copy];
}

static KudosPDFBlock *KudosMakePDFBlock(NSString *text,
                                        NSArray<NSValue *> *italicRaw,
                                        NSArray<NSValue *> *boldRaw) {
    NSString *copy = [text copy];
    return [[KudosPDFBlock alloc] initWithText:copy
                                  italicRanges:KudosNormalizeRanges(copy, italicRaw)
                                    boldRanges:KudosNormalizeRanges(copy, boldRaw)];
}

/// Appends one structured-text line's characters to `buffer`, optionally recording UTF-16
/// italic and bold runs aligned to `buffer`'s UTF-16 code units.
static void KudosAppendLine(fz_context *ctx,
                            fz_stext_line *line,
                            NSMutableString *buffer,
                            NSMutableArray<NSValue *> *italicRanges,
                            NSMutableArray<NSValue *> *boldRanges) {
    // Convert UTF-32 runes directly to UTF-16 code units so every character's offset matches
    // `NSString.length` and `NSRange` exactly, including supplementary-plane surrogate pairs.
    NSUInteger baseOffset = buffer.length;
    NSMutableData *utf16 = [NSMutableData dataWithCapacity:256];
    NSUInteger lineOffset = 0;

    BOOL trackStyles = (italicRanges != nil || boldRanges != nil);
    fz_font *lastFont = NULL;
    BOOL fontItalic = NO;
    BOOL fontBold = NO;
    BOOL inItalic = NO;
    NSUInteger italicStart = 0;
    BOOL inBold = NO;
    NSUInteger boldStart = 0;

    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        int rune = ch->c;
        unichar units[2];
        NSUInteger unitCount = 0;
        if (rune < 0 || rune > 0x10FFFF || (rune >= 0xD800 && rune <= 0xDFFF)) {
            units[0] = 0xFFFD;
            unitCount = 1;
        } else if (rune <= 0xFFFF) {
            units[0] = (unichar)rune;
            unitCount = 1;
        } else {
            uint32_t adjusted = (uint32_t)(rune - 0x10000);
            units[0] = (unichar)(0xD800U + (adjusted >> 10));
            units[1] = (unichar)(0xDC00U + (adjusted & 0x3FFU));
            unitCount = 2;
        }
        [utf16 appendBytes:units length:unitCount * sizeof(unichar)];

        if (trackStyles) {
            if (ch->font != lastFont) {
                lastFont = ch->font;
                KudosClassifyFont(ctx, lastFont, &fontItalic, &fontBold);
            }
            NSUInteger charPos = baseOffset + lineOffset;
            if (italicRanges != nil) {
                if (fontItalic) {
                    if (!inItalic) {
                        inItalic = YES;
                        italicStart = charPos;
                    }
                } else if (inItalic) {
                    KudosAppendRange(italicRanges, italicStart, charPos - italicStart);
                    inItalic = NO;
                }
            }
            if (boldRanges != nil) {
                BOOL isBold = fontBold || ((ch->flags & FZ_STEXT_BOLD) != 0);
                if (isBold) {
                    if (!inBold) {
                        inBold = YES;
                        boldStart = charPos;
                    }
                } else if (inBold) {
                    KudosAppendRange(boldRanges, boldStart, charPos - boldStart);
                    inBold = NO;
                }
            }
        }

        lineOffset += unitCount;
    }

    if (trackStyles) {
        NSUInteger lineEnd = baseOffset + lineOffset;
        if (inItalic && italicRanges != nil) {
            KudosAppendRange(italicRanges, italicStart, lineEnd - italicStart);
        }
        if (inBold && boldRanges != nil) {
            KudosAppendRange(boldRanges, boldStart, lineEnd - boldStart);
        }
    }

    if (lineOffset > 0) {
        NSString *text = [[NSString alloc] initWithCharacters:(const unichar *)utf16.bytes
                                                       length:lineOffset];
        if (text != nil) {
            [buffer appendString:text];
        }
    }
}

/// What a drawn scene break becomes in the extracted text (the same string the converter uses for typed ones).
static NSString *const KudosSceneBreakMarker = @"* * *";

static KudosPDFBlock *KudosSceneBreakBlock(void) {
    return [[KudosPDFBlock alloc] initWithText:KudosSceneBreakMarker italicRanges:@[] boldRanges:@[]];
}

/// The vertical centres, top to bottom, of horizontal rules that separate paragraphs: a vector at most 4 pt tall and at
/// least 40% of the page wide that crosses no line of text (so underlines and strike-throughs don't count; a rule
/// between two lines of one block still counts, because MuPDF can group paragraphs on either side of it). Rules
/// within 6 pt of each other are one rule (calibre strokes an `<hr>` as two overlapping paths).
/// shortcut: placed by height on the page, so a two-column layout could put a break in the wrong column; fan fiction
/// PDFs are single-column, revisit if a multi-column import shows it.
static NSArray<NSNumber *> *KudosSceneBreakRules(fz_stext_page *page) {
    float pageWidth = page->mediabox.x1 - page->mediabox.x0;
    NSMutableArray<NSNumber *> *centres = [NSMutableArray array];
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_VECTOR) {
            continue;
        }
        fz_rect box = block->bbox;
        if (box.y1 - box.y0 > 4 || box.x1 - box.x0 < pageWidth * 0.4f) {
            continue;
        }
        float centre = (box.y0 + box.y1) / 2;
        BOOL overlapsText = NO;
        for (fz_stext_block *text = page->first_block; text != NULL && !overlapsText; text = text->next) {
            if (text->type != FZ_STEXT_BLOCK_TEXT) {
                continue;
            }
            for (fz_stext_line *line = text->u.t.first_line; line != NULL; line = line->next) {
                if (centre >= line->bbox.y0 && centre <= line->bbox.y1) {
                    overlapsText = YES;
                    break;
                }
            }
        }
        if (!overlapsText) {
            [centres addObject:@(centre)];
        }
    }
    [centres sortUsingSelector:@selector(compare:)];
    NSMutableArray<NSNumber *> *rules = [NSMutableArray array];
    for (NSNumber *centre in centres) {
        if (rules.count == 0 || centre.floatValue - rules.lastObject.floatValue > 6) {
            [rules addObject:centre];
        }
    }
    return rules;
}

+ (nullable NSArray<NSArray<KudosPDFBlock *> *> *)styledParagraphsPerPageForPDFAtPath:(NSString *)path {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        return nil;
    }

    NSMutableArray<NSArray<KudosPDFBlock *> *> *pages = [NSMutableArray array];
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
            options.flags = FZ_STEXT_COLLECT_VECTORS;
            fz_stext_page *stext = NULL;
            NSMutableArray<KudosPDFBlock *> *entries = [NSMutableArray array];

            // Per-page fz_try: one unreadable page yields an empty page rather than
            // abandoning the whole document, which matters for a 170-page work whose
            // last chapter is fine.
            fz_try(ctx) {
                stext = fz_new_stext_page_from_page_number(ctx, doc, index, &options);
                NSArray<NSNumber *> *rules = KudosSceneBreakRules(stext);
                NSUInteger nextRule = 0;
                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) {
                        continue;
                    }
                    // Rules above this block come first, in page order.
                    while (nextRule < rules.count && rules[nextRule].floatValue < block->bbox.y0) {
                        [entries addObject:KudosSceneBreakBlock()];
                        nextRule++;
                    }
                    // One block is one paragraph; its lines are wrapped display
                    // lines and join with a single space. A scene-break rule between two of its lines splits it.
                    NSMutableString *text = [NSMutableString string];
                    NSMutableArray<NSValue *> *italicRaw = [NSMutableArray array];
                    NSMutableArray<NSValue *> *boldRaw = [NSMutableArray array];
                    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                        if (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                            if (text.length > 0) {
                                [entries addObject:KudosMakePDFBlock(text, italicRaw, boldRaw)];
                                [text setString:@""];
                                [italicRaw removeAllObjects];
                                [boldRaw removeAllObjects];
                            }
                            while (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                                [entries addObject:KudosSceneBreakBlock()];
                                nextRule++;
                            }
                        }
                        if (text.length > 0) {
                            [text appendString:@" "];
                        }
                        KudosAppendLine(ctx, line, text, italicRaw, boldRaw);
                    }
                    if (text.length > 0) {
                        [entries addObject:KudosMakePDFBlock(text, italicRaw, boldRaw)];
                    }
                }
                while (nextRule < rules.count) {
                    [entries addObject:KudosSceneBreakBlock()];
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
    NSArray<NSArray<KudosPDFBlock *> *> *styledPages = [self styledParagraphsPerPageForPDFAtPath:path];
    if (styledPages == nil) {
        return nil;
    }
    NSMutableArray<NSArray<NSString *> *> *pages = [NSMutableArray arrayWithCapacity:styledPages.count];
    for (NSArray<KudosPDFBlock *> *styledPage in styledPages) {
        NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:styledPage.count];
        for (KudosPDFBlock *block in styledPage) {
            [texts addObject:block.text];
        }
        [pages addObject:texts];
    }
    return pages;
}

+ (nullable NSArray<NSArray<NSString *> *> *)linesPerPageForPDFAtPath:(NSString *)path {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        return nil;
    }

    NSMutableArray<NSArray<NSString *> *> *pages = [NSMutableArray array];
    fz_document *doc = NULL;

    fz_try(ctx) {
        fz_register_document_handlers(ctx);
        doc = fz_open_document(ctx, path.fileSystemRepresentation);
        int pageCount = fz_count_pages(ctx, doc);

        for (int index = 0; index < pageCount; index++) {
            fz_stext_options options = { 0 };
            fz_stext_page *stext = NULL;
            NSMutableArray<NSString *> *entries = [NSMutableArray array];

            fz_try(ctx) {
                stext = fz_new_stext_page_from_page_number(ctx, doc, index, &options);
                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) {
                        continue;
                    }
                    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                        NSMutableString *text = [NSMutableString string];
                        KudosAppendLine(ctx, line, text, nil, nil);
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

@end
