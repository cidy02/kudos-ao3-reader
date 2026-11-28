#import "KudosMuPDF.h"

#import <math.h>
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

typedef struct {
    float y;
    float x0;
    float x1;
} KudosRule;

typedef struct {
    NSUInteger pageIndex;
    NSUInteger insertIndex;
    float gap;
    float upperLineHeight;
    BOOL isEdgeBlankBlock;
} KudosGapCandidate;

static int KudosCompareRules(const void *va, const void *vb) {
    float ay = ((const KudosRule *)va)->y;
    float by = ((const KudosRule *)vb)->y;
    if (ay < by) return -1;
    if (ay > by) return 1;
    return 0;
}

static int KudosCompareFloat(const void *va, const void *vb) {
    float a = *(const float *)va;
    float b = *(const float *)vb;
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

static int KudosCompareGapCandidatesDesc(const void *va, const void *vb) {
    const KudosGapCandidate *a = (const KudosGapCandidate *)va;
    const KudosGapCandidate *b = (const KudosGapCandidate *)vb;
    if (a->pageIndex != b->pageIndex) {
        return a->pageIndex > b->pageIndex ? -1 : 1;
    }
    if (a->insertIndex != b->insertIndex) {
        return a->insertIndex > b->insertIndex ? -1 : 1;
    }
    return 0;
}

static BOOL KudosIsWhitespaceRune(int rune) {
    return rune == ' ' || rune == '\t' || rune == '\n' || rune == '\r' || rune == 0x00A0;
}

static BOOL KudosIsLineWhitespaceOnly(fz_stext_line *line) {
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        if (!KudosIsWhitespaceRune(ch->c)) {
            return NO;
        }
    }
    return YES;
}

static BOOL KudosIsBlockWhitespaceOnly(fz_stext_block *block) {
    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
        if (!KudosIsLineWhitespaceOnly(line)) {
            return NO;
        }
    }
    return YES;
}

static BOOL KudosBlockHasAnyChar(fz_stext_block *block) {
    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
        if (line->first_char != NULL) {
            return YES;
        }
    }
    return NO;
}

static BOOL KudosLineEndsWithWordHyphen(fz_stext_line *line) {
    int prevNonWS = 0;
    int lastNonWS = 0;
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        if (!KudosIsWhitespaceRune(ch->c)) {
            prevNonWS = lastNonWS;
            lastNonWS = ch->c;
        }
    }
    BOOL prevIsASCIIAlpha = (prevNonWS >= 'a' && prevNonWS <= 'z') || (prevNonWS >= 'A' && prevNonWS <= 'Z');
    return lastNonWS == '-' && prevIsASCIIAlpha;
}

static float KudosFirstWordWidth(fz_stext_line *line) {
    if (line == NULL) {
        return 0.0f;
    }
    BOOL inWord = NO;
    float minX = 0.0f;
    float maxX = 0.0f;
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        if (KudosIsWhitespaceRune(ch->c)) {
            if (inWord) {
                break;
            }
            continue;
        }
        fz_rect r = fz_rect_from_quad(ch->quad);
        if (!inWord) {
            minX = r.x0;
            maxX = r.x1;
            inWord = YES;
        } else {
            if (r.x0 < minX) minX = r.x0;
            if (r.x1 > maxX) maxX = r.x1;
        }
    }
    return inWord ? (maxX - minX) : 0.0f;
}

/// Typical prose line width on `page`, used to separate wrapped prose from deliberate
/// short lines (verse/lyrics). Falls back to 65% of page width on poem-only pages where
/// every line is short.
static float KudosPageLineMeasure(fz_stext_page *page) {
    float pageWidth = page->mediabox.x1 - page->mediabox.x0;
    if (pageWidth < 1.0f) {
        return 0.0f;
    }
    NSMutableData *widthsData = [NSMutableData data];
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_TEXT || KudosIsBlockWhitespaceOnly(block)) {
            continue;
        }
        for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
            if (KudosIsLineWhitespaceOnly(line)) {
                continue;
            }
            float width = line->bbox.x1 - line->bbox.x0;
            if (width > 0.0f) {
                [widthsData appendBytes:&width length:sizeof(width)];
            }
        }
    }
    NSUInteger count = widthsData.length / sizeof(float);
    if (count == 0) {
        return pageWidth * 0.65f;
    }
    float *widths = widthsData.mutableBytes;
    if (count > 1) {
        qsort(widths, count, sizeof(float), KudosCompareFloat);
    }
    float p90 = widths[(NSUInteger)(0.9f * (float)(count - 1))];
    return (p90 >= pageWidth * 0.45f) ? p90 : MAX(p90, pageWidth * 0.65f);
}

/// The page's top and bottom margin bands, shared by the header/footer and page-number rules so they agree.
static const float KudosTopMarginBand = 0.065f;
static const float KudosBottomMarginBand = 0.08f;

/// A line that is only a page number (digits, optionally with dashes, dots or spaces: `12`, `- 12 -`, `12.`) in the
/// page's top or bottom margin. It is page chrome: dropped here rather than kept as a short verse line inside the
/// block, where the converter's page-number filter (which looks at whole blocks) could not see it (T-579e round 2).
static BOOL KudosIsMarginPageNumberLine(fz_stext_line *line, fz_stext_page *page) {
    float pageHeight = page->mediabox.y1 - page->mediabox.y0;
    if (pageHeight <= 0.0f) {
        return NO;
    }
    BOOL inTop = line->bbox.y1 < page->mediabox.y0 + pageHeight * KudosTopMarginBand;
    BOOL inBottom = line->bbox.y0 > page->mediabox.y1 - pageHeight * KudosBottomMarginBand;
    if (!inTop && !inBottom) {
        return NO;
    }
    int digits = 0;
    int others = 0;
    for (fz_stext_char *ch = line->first_char; ch != NULL; ch = ch->next) {
        int c = ch->c;
        if (c >= '0' && c <= '9') {
            digits++;
        } else if (c == ' ' || c == '-' || c == '.' || c == 0x2013 || c == 0x2014 || c == 0x00A0) {
            others++;
        } else {
            return NO;
        }
    }
    return digits >= 1 && digits <= 4 && others <= 6;
}

/// Keeps a deliberate line break (`\n`) when a non-final line ends well short of the
/// typical line width (calibre's ~0.45–0.60 unwrap factor) and the next line's first
/// word would still have fit on it.
static BOOL KudosShouldKeepLineBreak(fz_stext_line *prevLine, fz_stext_line *nextLine, float measure) {
    if (prevLine == NULL || nextLine == NULL || measure < 1.0f) {
        return NO;
    }
    if (KudosLineEndsWithWordHyphen(prevLine)) {
        return NO;
    }
    float prevWidth = prevLine->bbox.x1 - prevLine->bbox.x0;
    if (prevWidth >= measure * 0.55f) {
        return NO;
    }
    float nextWordWidth = KudosFirstWordWidth(nextLine);
    if (prevWidth + nextWordWidth >= measure * 0.90f) {
        return NO;
    }
    return YES;
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

static BOOL KudosRuleCrossesText(fz_rect box, float centre, float verticalPad, fz_stext_page *page) {
    for (fz_stext_block *text = page->first_block; text != NULL; text = text->next) {
        if (text->type != FZ_STEXT_BLOCK_TEXT) {
            continue;
        }
        for (fz_stext_line *line = text->u.t.first_line; line != NULL; line = line->next) {
            if (KudosIsLineWhitespaceOnly(line)) {
                continue;
            }
            if (centre < line->bbox.y0 - verticalPad || centre > line->bbox.y1 + verticalPad) {
                continue;
            }
            if (box.x0 <= line->bbox.x1 && box.x1 >= line->bbox.x0) {
                return YES;
            }
        }
    }
    return NO;
}

/// The vertical centres, top to bottom, of horizontal rules that separate paragraphs. A vector at most 4 pt tall and
/// either at least 40% of the page wide, or centered and at least 25% of the page wide (matching CSS `hr { width: 40%;
/// margin: auto }` inside page margins), in the page and not in its outer 12 pt (a rule along the page edge). A vertical
/// stroke crossing it is a table or a box, not a break. Crossing a text line means sharing that line's x range as well
/// as its height, so a strike-through or link underline counts and a rule beside a margin note, or beside the other
/// column, does not. A rule between two lines of one block still counts. Rules within 6 pt of each other and
/// overlapping in x are one rule (calibre strokes an `<hr>` as two overlapping paths).
/// shortcut: a break is inserted by page height, so two columns can put it in the wrong column; fan fiction PDFs are
/// single-column, revisit if a multi-column import shows it.
static NSArray<NSNumber *> *KudosSceneBreakRules(fz_stext_page *page) {
    float pageWidth = page->mediabox.x1 - page->mediabox.x0;
    if (pageWidth < 1) {
        return @[];
    }
    float pageMidX = (page->mediabox.x0 + page->mediabox.x1) * 0.5f;
    NSMutableData *found = [NSMutableData data];
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_VECTOR) {
            continue;
        }
        fz_rect box = block->bbox;
        if (box.y1 - box.y0 > 4) {
            continue;
        }
        float ruleWidth = box.x1 - box.x0;
        BOOL isWideRule = (ruleWidth >= pageWidth * 0.4f);
        float ruleMidX = (box.x0 + box.x1) * 0.5f;
        BOOL isCenteredRule = (ruleWidth >= pageWidth * 0.25f)
            && (fabsf(ruleMidX - pageMidX) <= pageWidth * 0.08f);
        if (!isWideRule && !isCenteredRule) {
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
        // Centered medium-width rules get 2 pt vertical padding against text lines so link underlines never pass.
        float verticalPad = isWideRule ? 0.0f : 2.0f;
        if (KudosRuleCrossesText(box, centre, verticalPad, page)) {
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

static BOOL KudosIsInTopMargin(fz_stext_block *block, fz_stext_page *page) {
    float pageHeight = page->mediabox.y1 - page->mediabox.y0;
    return pageHeight > 0.0f && block->bbox.y1 < page->mediabox.y0 + pageHeight * KudosTopMarginBand;
}

static BOOL KudosIsInBottomMargin(fz_stext_block *block, fz_stext_page *page) {
    float pageHeight = page->mediabox.y1 - page->mediabox.y0;
    return pageHeight > 0.0f && block->bbox.y0 > page->mediabox.y1 - pageHeight * KudosBottomMarginBand;
}

static BOOL KudosHasDrawnInVerticalBand(fz_stext_page *page, float y0, float y1) {
    float pageWidth = page->mediabox.x1 - page->mediabox.x0;
    float pageHeight = page->mediabox.y1 - page->mediabox.y0;
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block->type != FZ_STEXT_BLOCK_VECTOR && block->type != FZ_STEXT_BLOCK_IMAGE) {
            continue;
        }
        fz_rect box = block->bbox;
        float w = box.x1 - box.x0;
        float h = box.y1 - box.y0;
        // Skip full-page background/clip rectangles (WebKit draws one behind each page).
        if (w > pageWidth * 0.9f && h > pageHeight * 0.5f) {
            continue;
        }
        float cy = (box.y0 + box.y1) * 0.5f;
        if (cy > y0 - 2.0f && cy < y1 + 2.0f) {
            return YES;
        }
    }
    return NO;
}

static BOOL KudosHasTextInVerticalBand(fz_stext_page *page,
                                       float y0,
                                       float y1,
                                       fz_stext_block *ignoreA,
                                       fz_stext_block *ignoreB) {
    for (fz_stext_block *block = page->first_block; block != NULL; block = block->next) {
        if (block == ignoreA || block == ignoreB || block->type != FZ_STEXT_BLOCK_TEXT) {
            continue;
        }
        if (KudosIsBlockWhitespaceOnly(block)) {
            continue;
        }
        float cy = (block->bbox.y0 + block->bbox.y1) * 0.5f;
        if (cy > y0 && cy < y1) {
            return YES;
        }
    }
    return NO;
}

+ (nullable NSArray<NSArray<KudosPDFBlock *> *> *)styledParagraphsPerPageForPDFAtPath:(NSString *)path {
    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    if (ctx == NULL) {
        return nil;
    }

    NSMutableArray<NSMutableArray<KudosPDFBlock *> *> *pages = [NSMutableArray array];
    NSMutableData *allGapsData = [NSMutableData data];
    NSMutableData *allLineHeightsData = [NSMutableData data];
    NSMutableData *gapCandidatesData = [NSMutableData data];
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
                float pageMeasure = KudosPageLineMeasure(stext);
                float pageWidth = stext->mediabox.x1 - stext->mediabox.x0;
                float pageMidX = (stext->mediabox.x0 + stext->mediabox.x1) * 0.5f;

                fz_stext_block *firstTextBlock = NULL;
                fz_stext_block *lastTextBlock = NULL;
                fz_stext_block *firstBodyBlock = NULL;
                fz_stext_block *lastBodyBlock = NULL;
                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT || KudosIsBlockWhitespaceOnly(block)) {
                        continue;
                    }
                    if (firstTextBlock == NULL) {
                        firstTextBlock = block;
                    }
                    lastTextBlock = block;
                    if (!KudosIsInTopMargin(block, stext) && !KudosIsInBottomMargin(block, stext)) {
                        if (firstBodyBlock == NULL) {
                            firstBodyBlock = block;
                        }
                        lastBodyBlock = block;
                    }
                    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                        if (KudosIsLineWhitespaceOnly(line)) {
                            continue;
                        }
                        float lh = line->bbox.y1 - line->bbox.y0;
                        if (lh > 2.0f) {
                            [allLineHeightsData appendBytes:&lh length:sizeof(lh)];
                        }
                    }
                }

                NSUInteger nextRule = 0;
                fz_stext_block *prevTextBlock = NULL;
                NSUInteger firstBodyEntryIndex = NSNotFound;
                NSUInteger lastBodyEndEntryIndex = NSNotFound;

                for (fz_stext_block *block = stext->first_block; block != NULL; block = block->next) {
                    if (block->type != FZ_STEXT_BLOCK_TEXT) {
                        continue;
                    }
                    if (KudosIsBlockWhitespaceOnly(block)) {
                        continue;
                    }
                    // Rules above this block come first, in page order.
                    BOOL emittedRuleBeforeBlock = NO;
                    while (nextRule < rules.count && rules[nextRule].floatValue < block->bbox.y0) {
                        [entries addObject:KudosSceneBreakBlock()];
                        nextRule++;
                        emittedRuleBeforeBlock = YES;
                    }
                    if (prevTextBlock != NULL && !emittedRuleBeforeBlock) {
                        float gap = block->bbox.y0 - prevTextBlock->bbox.y1;
                        if (gap > 2.0f) {
                            BOOL isTopHeader = (prevTextBlock == firstTextBlock && KudosIsInTopMargin(prevTextBlock, stext));
                            BOOL isBottomFooter = (block == lastTextBlock && KudosIsInBottomMargin(block, stext));
                            if (!isTopHeader && !isBottomFooter
                                && !KudosHasDrawnInVerticalBand(stext, prevTextBlock->bbox.y1, block->bbox.y0)
                                && !KudosHasTextInVerticalBand(stext, prevTextBlock->bbox.y1, block->bbox.y0, prevTextBlock, block)) {
                                [allGapsData appendBytes:&gap length:sizeof(gap)];
                                float upperLH = 0.0f;
                                for (fz_stext_line *l = prevTextBlock->u.t.last_line; l != NULL; l = l->prev) {
                                    if (!KudosIsLineWhitespaceOnly(l)) {
                                        upperLH = l->bbox.y1 - l->bbox.y0;
                                        break;
                                    }
                                }
                                KudosGapCandidate candidate = {
                                    (NSUInteger)index,
                                    entries.count,
                                    gap,
                                    upperLH,
                                    NO
                                };
                                [gapCandidatesData appendBytes:&candidate length:sizeof(candidate)];
                            }
                        }
                    }

                    if (block == firstBodyBlock && firstBodyEntryIndex == NSNotFound) {
                        firstBodyEntryIndex = entries.count;
                    }

                    // One block is one paragraph; wrapped prose lines join with a single space while
                    // deliberate short lines (verse/lyrics) keep `\n`. A scene-break rule between two
                    // lines of one block still splits it.
                    NSMutableString *text = [NSMutableString string];
                    NSMutableArray<NSValue *> *italicRaw = [NSMutableArray array];
                    NSMutableArray<NSValue *> *boldRaw = [NSMutableArray array];
                    fz_stext_line *prevLine = NULL;
                    BOOL keptLine = NO;
                    for (fz_stext_line *line = block->u.t.first_line; line != NULL; line = line->next) {
                        if (KudosIsLineWhitespaceOnly(line) || KudosIsMarginPageNumberLine(line, stext)) {
                            continue;
                        }
                        keptLine = YES;
                        if (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                            if (text.length > 0) {
                                [entries addObject:KudosMakePDFBlock(text, italicRaw, boldRaw)];
                                [text setString:@""];
                                [italicRaw removeAllObjects];
                                [boldRaw removeAllObjects];
                                prevLine = NULL;
                            }
                            while (nextRule < rules.count && rules[nextRule].floatValue < line->bbox.y0) {
                                [entries addObject:KudosSceneBreakBlock()];
                                nextRule++;
                            }
                        }
                        if (text.length > 0) {
                            BOOL keepBreak = KudosShouldKeepLineBreak(prevLine, line, pageMeasure);
                            [text appendString:keepBreak ? @"\n" : @" "];
                        }
                        KudosAppendLine(ctx, line, text, italicRaw, boldRaw);
                        prevLine = line;
                    }
                    if (text.length > 0) {
                        [entries addObject:KudosMakePDFBlock(text, italicRaw, boldRaw)];
                    }
                    if (block == lastBodyBlock) {
                        lastBodyEndEntryIndex = entries.count;
                    }
                    // A block whose only lines were margin page numbers yields nothing, so the gap to it is no scene break.
                    if (keptLine) {
                        prevTextBlock = block;
                    }
                }
                while (nextRule < rules.count) {
                    [entries addObject:KudosSceneBreakBlock()];
                    nextRule++;
                }

                // A blank-paragraph scene break (`<p>&#160;</p>`) that landed at the very top or
                // bottom of a page leaves a centered whitespace-only text block with no sibling
                // on its outer side; record it as a candidate so page breaks do not swallow it.
                if (firstBodyBlock != NULL && lastBodyBlock != NULL && pageWidth > 1.0f) {
                    for (fz_stext_block *ws = stext->first_block; ws != NULL; ws = ws->next) {
                        if (ws->type != FZ_STEXT_BLOCK_TEXT
                            || !KudosIsBlockWhitespaceOnly(ws)
                            || !KudosBlockHasAnyChar(ws)) {
                            continue;
                        }
                        float wy0 = ws->bbox.y0;
                        float wy1 = ws->bbox.y1;
                        float wcy = (wy0 + wy1) * 0.5f;
                        float wmid = (ws->bbox.x0 + ws->bbox.x1) * 0.5f;
                        if (wcy - stext->mediabox.y0 < 12.0f || stext->mediabox.y1 - wcy < 12.0f) {
                            continue;
                        }
                        if (fabsf(wmid - pageMidX) > pageWidth * 0.10f) {
                            continue;
                        }
                        BOOL overlapsText = NO;
                        for (fz_stext_block *tb = stext->first_block; tb != NULL; tb = tb->next) {
                            if (tb->type != FZ_STEXT_BLOCK_TEXT || KudosIsBlockWhitespaceOnly(tb)) {
                                continue;
                            }
                            if (wy0 < tb->bbox.y1 && wy1 > tb->bbox.y0) {
                                overlapsText = YES;
                                break;
                            }
                        }
                        if (overlapsText) {
                            continue;
                        }
                        if (wy0 > lastBodyBlock->bbox.y1 && lastBodyEndEntryIndex != NSNotFound) {
                            float gap = wy0 - lastBodyBlock->bbox.y1;
                            if (gap > 2.0f && !KudosHasDrawnInVerticalBand(stext, lastBodyBlock->bbox.y1, wy1)) {
                                KudosGapCandidate candidate = {
                                    (NSUInteger)index,
                                    lastBodyEndEntryIndex,
                                    gap,
                                    0.0f,
                                    YES
                                };
                                [gapCandidatesData appendBytes:&candidate length:sizeof(candidate)];
                            }
                        } else if (wy1 < firstBodyBlock->bbox.y0 && firstBodyEntryIndex != NSNotFound) {
                            float gap = firstBodyBlock->bbox.y0 - wy1;
                            if (gap > 2.0f && !KudosHasDrawnInVerticalBand(stext, wy0, firstBodyBlock->bbox.y0)) {
                                KudosGapCandidate candidate = {
                                    (NSUInteger)index,
                                    firstBodyEntryIndex,
                                    gap,
                                    0.0f,
                                    YES
                                };
                                [gapCandidatesData appendBytes:&candidate length:sizeof(candidate)];
                            }
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

    // Insert scene breaks for empty vertical gaps clearly larger than the document's
    // normal paragraph gap (and at least two line heights tall), plus standalone
    // centered blank-paragraph blocks at page edges.
    NSUInteger gapCount = allGapsData.length / sizeof(float);
    NSUInteger lineHeightCount = allLineHeightsData.length / sizeof(float);
    NSUInteger candidateCount = gapCandidatesData.length / sizeof(KudosGapCandidate);
    if (gapCount >= 3 && lineHeightCount > 0 && candidateCount > 0) {
        float *allGaps = allGapsData.mutableBytes;
        qsort(allGaps, gapCount, sizeof(float), KudosCompareFloat);
        float docMedianGap = allGaps[gapCount / 2];

        float *allLineHeights = allLineHeightsData.mutableBytes;
        qsort(allLineHeights, lineHeightCount, sizeof(float), KudosCompareFloat);
        float docMedianLineHeight = allLineHeights[lineHeightCount / 2];

        KudosGapCandidate *candidates = gapCandidatesData.mutableBytes;
        if (candidateCount > 1) {
            qsort(candidates, candidateCount, sizeof(KudosGapCandidate), KudosCompareGapCandidatesDesc);
        }
        for (NSUInteger i = 0; i < candidateCount; i++) {
            KudosGapCandidate c = candidates[i];
            if (c.pageIndex >= pages.count) {
                continue;
            }
            BOOL isBreak = NO;
            if (c.isEdgeBlankBlock) {
                isBreak = (c.gap >= docMedianGap * 0.85f);
            } else if (c.upperLineHeight <= docMedianLineHeight * 1.5f) {
                float refHeight = MAX(docMedianLineHeight, c.upperLineHeight);
                isBreak = (c.gap >= docMedianGap * 2.2f && c.gap >= refHeight * 2.0f);
            }
            if (!isBreak) {
                continue;
            }
            NSMutableArray<KudosPDFBlock *> *pageEntries = pages[c.pageIndex];
            if (c.insertIndex > pageEntries.count) {
                continue;
            }
            if (c.insertIndex > 0 && [pageEntries[c.insertIndex - 1].text isEqualToString:KudosSceneBreakMarker]) {
                continue;
            }
            if (c.insertIndex < pageEntries.count && [pageEntries[c.insertIndex].text isEqualToString:KudosSceneBreakMarker]) {
                continue;
            }
            [pageEntries insertObject:KudosSceneBreakBlock() atIndex:c.insertIndex];
        }
    }

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
