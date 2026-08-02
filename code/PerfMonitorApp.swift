import SwiftUI

@main
struct PerfMonitorApp: App {
    @StateObject private var engine = MonitorEngine()

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView()
                .environmentObject(engine)
                .frame(minWidth: 720, minHeight: 640)
                .onAppear { engine.start() }
                // Deliberately no onDisappear/stop here: closing the dashboard window
                // should not stop monitoring, since the menu bar item needs to keep
                // updating even when the window is closed.
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(engine)
        } label: {
            MenuBarLabel()
                .environmentObject(engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(engine)
        }
    }
}
