import SwiftUI

@main
struct CPAWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(store)
                .onAppear { store.activate() }
        }
    }
}
