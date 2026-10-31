import CoreGraphics
import Testing
@testable import Kudos

struct SubjectHeadingScrollCollapseTests {
    @Test func clampedOffsetPinsOverscrollAndStopsBeyondMaxTracked() {
        #expect(SubjectHeadingScrollCollapse.clampedOffset(-32) == 0)
        #expect(SubjectHeadingScrollCollapse.clampedOffset(0) == 0)
        #expect(SubjectHeadingScrollCollapse.clampedOffset(23.6) == 24)
        #expect(SubjectHeadingScrollCollapse.clampedOffset(60) == 60)
        #expect(SubjectHeadingScrollCollapse.clampedOffset(240) == 60)
    }

    @Test func inlineTitleUsesHysteresisBandBetweenShowAndHideThresholds() {
        // Scrolling down from rest stays hidden until crossing 44pt.
        #expect(!SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 0, previouslyVisible: false))
        #expect(!SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 28, previouslyVisible: false))
        #expect(!SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 36, previouslyVisible: false))
        #expect(SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 44, previouslyVisible: false))

        // Scrolling back up stays visible inside the 29...43pt band until reaching 28pt.
        #expect(SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 43, previouslyVisible: true))
        #expect(SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 29, previouslyVisible: true))
        #expect(!SubjectHeadingScrollCollapse.showsInlineTitle(scrollOffset: 28, previouslyVisible: true))
    }

    @Test func headingScaleAndOpacityShrinkIntoTheNavigationBar() {
        #expect(SubjectHeadingScrollCollapse.headingScale(scrollOffset: 0) == 1.0)
        #expect(SubjectHeadingScrollCollapse.headingScale(scrollOffset: -10) == 1.0)
        #expect(abs(SubjectHeadingScrollCollapse.headingScale(scrollOffset: 22) - 0.96) < 0.0001)
        #expect(abs(SubjectHeadingScrollCollapse.headingScale(scrollOffset: 44) - 0.92) < 0.0001)
        #expect(abs(SubjectHeadingScrollCollapse.headingScale(scrollOffset: 60) - 0.92) < 0.0001)

        #expect(SubjectHeadingScrollCollapse.headingOpacity(scrollOffset: 0) == 1.0)
        #expect(SubjectHeadingScrollCollapse.headingOpacity(scrollOffset: 12) == 1.0)
        let midOpacity = SubjectHeadingScrollCollapse.headingOpacity(scrollOffset: 31)
        #expect(midOpacity > 0 && midOpacity < 1)
        #expect(SubjectHeadingScrollCollapse.headingOpacity(scrollOffset: 50) == 0.0)
        #expect(SubjectHeadingScrollCollapse.headingOpacity(scrollOffset: 60) == 0.0)
    }
}
