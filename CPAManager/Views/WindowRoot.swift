import SwiftUI

/// One app window: its own navigation state, published so menu commands and keyboard
/// shortcuts act on whichever window is in front (Mac windows, iPad Stage Manager /
/// Split View scenes).
struct WindowRoot: View {
    @State private var router = AppRouter()

    var body: some View {
        RootView()
            .appChrome()
            .macWindowMinSize()
            .environment(router)
            .focusedSceneValue(\.appRouter, router)
    }
}
