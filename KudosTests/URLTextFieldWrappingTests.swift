#if os(iOS)
import Testing
import UIKit
@testable import Kudos

/// The parent work's URL wraps at any character. Word wrapping hyphenated a word wider
/// than the field ("archiveo- / fourown.org" at AX5) even with hyphenation off (T-443).
struct URLTextFieldWrappingTests {
    @Test func theURLWrapsAtAnyCharacterWithNoHyphen() {
        let style = URLTextView.attributes(font: nil, alignment: .right)[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byCharWrapping)
        #expect(style?.hyphenationFactor == 0)
    }
}
#endif
