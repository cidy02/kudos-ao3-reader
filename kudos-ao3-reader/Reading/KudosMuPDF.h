#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One extracted paragraph block together with its inline italic and bold runs.
///
/// Ranges are UTF-16 `NSRange` values wrapped in `NSValue`, indexing into `text`.
@interface KudosPDFBlock : NSObject

@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, copy, readonly) NSArray<NSValue *> *italicRanges;
@property (nonatomic, copy, readonly) NSArray<NSValue *> *boldRanges;

- (instancetype)initWithText:(NSString *)text
                italicRanges:(NSArray<NSValue *> *)italicRanges
                  boldRanges:(NSArray<NSValue *> *)boldRanges NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// Thin Objective-C shim over MuPDF's structured-text API.
///
/// Objective-C rather than a Swift module map on purpose: the app target is a
/// file-system–synchronized folder, so a `.m` is picked up automatically and only a
/// bridging-header build setting is needed. A modulemap-based C target would mean real
/// project surgery for no extra capability.
///
/// Only what the converter needs crosses the boundary — strings, no `fz_*` types — so
/// MuPDF's C API and its manual reference counting stay on this side of it.
///
/// Why MuPDF at all: `PDFPage.string`/`characterBounds` is a text API, not a layout
/// one. See docs/PDF_ENGINE_MUPDF.md.
@interface KudosMuPDF : NSObject

/// One entry per page, each holding that page's paragraphs in reading order.
///
/// A paragraph is one MuPDF structured-text *block*, its wrapped prose lines joined with
/// a single space and deliberate short lines (verse/lyrics) kept as `\n`. Verified on a
/// 171-page reference PDF: the assembled text is character-identical to MuPDF's own
/// reading-order stream, and its non-whitespace character counts match PDFKit's exactly
/// (493,826, including 4,395 commas) while being correctly ordered and grouped where
/// PDFKit is not.
///
/// Returns nil when the document cannot be opened, so the caller can fall back.
+ (nullable NSArray<NSArray<NSString *> *> *)paragraphsPerPageForPDFAtPath:(NSString *)path
    NS_SWIFT_NAME(paragraphsPerPage(forPDFAtPath:));

/// One entry per page, each holding that page's paragraph blocks with UTF-16
/// italic and bold runs.
///
/// Follows the same block, line-join, verse line-break, drawn-rule, and vertical-gap
/// scene-break rules as `paragraphsPerPage(forPDFAtPath:)`; scene-break `* * *` blocks
/// carry no styling.
/// Returns nil when the document cannot be opened, so the caller can fall back.
+ (nullable NSArray<NSArray<KudosPDFBlock *> *> *)styledParagraphsPerPageForPDFAtPath:(NSString *)path
    NS_SWIFT_NAME(styledParagraphsPerPage(forPDFAtPath:));

/// One entry per page, each holding that page's *lines* — not paragraphs.
///
/// Needed for the calibre/FanFicFare metadata page, whose `Label: value` rows must be
/// read one line at a time. Feeding it assembled paragraphs merged those rows into one
/// blob and made the parser read `Storylink:` as part of `Story:`'s value.
+ (nullable NSArray<NSArray<NSString *> *> *)linesPerPageForPDFAtPath:(NSString *)path
    NS_SWIFT_NAME(linesPerPage(forPDFAtPath:));

@end

NS_ASSUME_NONNULL_END
