import AppKit
import SwiftUI

struct RootMenu: View {
    var body: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}
