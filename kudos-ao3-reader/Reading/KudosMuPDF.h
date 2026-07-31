#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
/// A paragraph is one MuPDF structured-text *block*, its lines joined with a single
/// space. Verified on a 171-page reference PDF: the assembled text is
/// character-identical to MuPDF's own reading-order stream, and its non-whitespace
/// character counts match PDFKit's exactly (493,826, including 4,395 commas) while
/// being correctly ordered and grouped where PDFKit is not.
///
/// Returns nil when the document cannot be opened, so the caller can fall back.
+ (nullable NSArray<NSArray<NSString *> *> *)paragraphsPerPageForPDFAtPath:(NSString *)path
    NS_SWIFT_NAME(paragraphsPerPage(forPDFAtPath:));

/// One entry per page, each holding that page's *lines* — not paragraphs.
///
/// Needed for the calibre/FanFicFare metadata page, whose `Label: value` rows must be
/// read one line at a time. Feeding it assembled paragraphs merged those rows into one
/// blob and made the parser read `Storylink:` as part of `Story:`'s value.
+ (nullable NSArray<NSArray<NSString *> *> *)linesPerPageForPDFAtPath:(NSString *)path
    NS_SWIFT_NAME(linesPerPage(forPDFAtPath:));

@end

NS_ASSUME_NONNULL_END
