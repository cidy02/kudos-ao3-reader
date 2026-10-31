import SwiftUI
import Testing
@testable import Kudos

struct SubjectScreenRoleTests {
    @Test func onlyTheSubjectRoleUsesAnIdentityWash() {
        #expect(!SubjectScreenRole.content.usesSubjectWash)
        #expect(!SubjectScreenRole.grouped.usesSubjectWash)
        #expect(SubjectScreenRole.subjectWash.usesSubjectWash)
    }

    @Test func rolesMapToTheCorrectBaseSurface() {
        #expect(SubjectScreenRole.content.baseSurface == .content)
        #expect(SubjectScreenRole.grouped.baseSurface == .grouped)
        #expect(SubjectScreenRole.subjectWash.baseSurface == .content)
    }

    @Test func contentBackdropPinsAllFourThemes() {
        #if os(iOS)
        #expect(ReaderTheme.light.contentBackdrop == Color(uiColor: .systemBackground))
        #else
        #expect(ReaderTheme.light.contentBackdrop == Color(nsColor: .windowBackgroundColor))
        #endif
        #expect(ReaderTheme.light.contentBackdrop != ReaderTheme.light.cardBackdrop)

        #expect(ReaderTheme.sepia.contentBackdrop == ReaderTheme.sepia.cardBackdrop)
        #expect(ReaderTheme.sepia.contentBackdrop == ReaderTheme.sepia.appBaseBackground)

        #expect(ReaderTheme.dark.contentBackdrop == ReaderTheme.dark.cardBackdrop)
        #expect(ReaderTheme.dark.contentBackdrop.hexString == "#0B0B0D")
        #expect(ReaderTheme.dark.contentBackdrop != ReaderTheme.dark.appBaseBackground)

        #expect(ReaderTheme.oled.contentBackdrop == ReaderTheme.oled.cardBackdrop)
        #expect(ReaderTheme.oled.contentBackdrop == .black)
        #expect(ReaderTheme.oled.contentBackdrop.hexString == "#000000")
    }

    @Test func washGeometryMatchesTheSharedRule() {
        #expect(SubjectWashGeometry.height == 380)
        #expect(SubjectWashGeometry.opacities == [0.20, 0.12, 0.05, 0])
        #expect(SubjectWashGeometry.locations == [0, 0.35, 0.65, 1])
    }

    @Test func washScrollTracksVerticalListsAndIgnoresHorizontalScrollViews() {
        let overflowingHorizontal = ScrollGeometry(
            contentOffset: CGPoint(x: 120, y: 0),
            contentSize: CGSize(width: 720, height: 36),
            contentInsets: EdgeInsets(),
            containerSize: CGSize(width: 360, height: 36)
        )
        let overflowSample = SubjectWashGeometry.scrollSample(from: overflowingHorizontal)
        #expect(overflowSample == nil)
        #expect(SubjectWashGeometry.resolvedOffset(from: overflowSample, to: overflowSample) == nil)

        let compactHorizontal = ScrollGeometry(
            contentOffset: .zero,
            contentSize: CGSize(width: 90, height: 36),
            contentInsets: EdgeInsets(),
            containerSize: CGSize(width: 360, height: 36)
        )
        let compactSample = SubjectWashGeometry.scrollSample(from: compactHorizontal)
        #expect(SubjectWashGeometry.resolvedOffset(from: compactSample, to: compactSample) == nil)
        #expect(SubjectWashGeometry.resolvedOffset(from: nil, to: compactSample) == nil)

        let verticalAtTop = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: -98),
            contentSize: CGSize(width: 390, height: 1400),
            contentInsets: EdgeInsets(top: 98, leading: 0, bottom: 34, trailing: 0),
            containerSize: CGSize(width: 390, height: 844)
        )
        let topSample = SubjectWashGeometry.scrollSample(from: verticalAtTop)
        #expect(SubjectWashGeometry.resolvedOffset(from: topSample, to: topSample) == 0)

        let verticalScrolled = ScrollGeometry(
            contentOffset: CGPoint(x: 0, y: 82),
            contentSize: CGSize(width: 390, height: 1400),
            contentInsets: EdgeInsets(top: 98, leading: 0, bottom: 34, trailing: 0),
            containerSize: CGSize(width: 390, height: 844)
        )
        let scrolledSample = SubjectWashGeometry.scrollSample(from: verticalScrolled)
        #expect(SubjectWashGeometry.resolvedOffset(from: topSample, to: scrolledSample) == 180)
        #expect(SubjectWashGeometry.resolvedOffset(from: scrolledSample, to: topSample) == 0)
    }
}
