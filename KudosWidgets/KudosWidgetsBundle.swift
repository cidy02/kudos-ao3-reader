import SwiftUI
import WidgetKit

/// Kudos's widgets (T-576e, `Phone-Capture.dc.html`, `Phone-Sprint.dc.html`): New Idea and what you're writing on the
/// Lock Screen, New Idea in Control Center (and so on the Action button), and the sprint Live Activity.
@main
struct KudosWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NewIdeaWidget()
        // shortcut: WritingWidget waits for the App Group (group.<app id>), which command-line signing can't register;
        // add it back with the entitlement once the group exists on the developer account.
        NewIdeaControl()
        SprintLiveActivity()
    }
}
