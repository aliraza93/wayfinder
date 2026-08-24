import SwiftUI

@main
struct WaypointApp: App {
    var body: some Scene {
        MenuBarExtra("Waypoint", systemImage: "location.north.line") {
            RootMenu()
        }
    }
}
