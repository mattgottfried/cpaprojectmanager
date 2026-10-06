import WidgetKit
import SwiftUI

/// The Mac widgets (Notification Center / desktop). Same Today and This Week widgets as the iPhone
/// and iPad ones; the Live Activity and Control Center controls have no Mac equivalent here.
@main
struct CPAWidgetsMacBundle: WidgetBundle {
    var body: some Widget {
        DueTodayWidget()
        ThisWeekWidget()
    }
}
