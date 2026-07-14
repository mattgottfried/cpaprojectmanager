import WidgetKit
import SwiftUI

@main
struct CPAWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DueTodayWidget()
        TimerLiveActivity()
    }
}
