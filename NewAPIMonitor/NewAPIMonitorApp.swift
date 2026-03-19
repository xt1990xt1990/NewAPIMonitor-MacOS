import SwiftUI

@main
struct NewAPIMonitorApp: App {
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
