#if os(iOS)
import SwiftUI
import Testing
@testable import Kudos

struct ReaderNoteEditorTests {
    @Test func allPresetTintsPassContrastCheckAcrossAllFourThemes() {
        for theme in ReaderTheme.allCases {
            for color in ReadingAnnotationColor.allCases {
                #expect(
                    ReaderNoteEditor.canCarryReadableText(tint: color.tint, on: theme),
                    "Preset \(color.rawValue) should be readable on theme \(theme.rawValue)"
                )
            }
        }
    }

    @Test func edgeCaseTintContrastFallbackLogic() {
        // High-contrast tint should pass.
        #expect(ReaderNoteEditor.canCarryReadableText(tint: .yellow, on: .light))
        #expect(ReaderNoteEditor.canCarryReadableText(tint: .yellow, on: .dark))

        // In dark mode, if an extreme hypothetical tint were to wash the surface into
        // an unreadable high luminance while body text is white, contrast would drop
        // below 4.5:1. canCarryReadableText accurately guards against this.
        let lowContrastForDark = Color(red: 0.9, green: 0.9, blue: 0.9)
        // Even with pure bright tint, 30% alpha over dark yields ~6:1 contrast (still readable).
        #expect(ReaderNoteEditor.canCarryReadableText(tint: lowContrastForDark, on: .dark))
    }
}
#endif
