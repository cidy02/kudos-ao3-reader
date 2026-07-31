// Objective-C surface visible to Swift.
//
// Only the MuPDF shim lives here. Kudos is otherwise pure Swift, and the shim is
// Objective-C because the app target is a file-system–synchronized folder: a `.m` is
// picked up automatically, so this one build setting replaces what a modulemap-based
// C target would have needed. See docs/PDF_ENGINE_MUPDF.md.
#import "KudosMuPDF.h"
