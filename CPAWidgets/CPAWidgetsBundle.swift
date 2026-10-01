import WidgetKit
import SwiftUI

@main
struct CPAWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DueTodayWidget()
        ThisWeekWidget()
        TimerLiveActivity()
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            QuickTaskControl()
            InboxCaptureControl()
        }
        #endif
    }
}
