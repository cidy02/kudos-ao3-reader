import SwiftUI
import WidgetKit

/// Kudos's widgets (T-576e, `Phone-Capture.dc.html`, `Phone-Sprint.dc.html`): New Idea and what you're writing on the
/// Lock Screen, New Idea in Control Center (and so on the Action button), and the sprint Live Activity.
@main
struct KudosWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NewIdeaWidget()
        WritingWidget()
        NewIdeaControl()
        SprintLiveActivity()
    }
}
