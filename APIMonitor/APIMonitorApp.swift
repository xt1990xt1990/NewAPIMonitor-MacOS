import SwiftUI

@main
struct APIMonitorApp: App {
    @StateObject private var state = MonitorState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Text(state.menuBarText)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)


    }
}
