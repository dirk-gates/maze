// MazeApp -- @main entry. Multiplatform-ready scene; macOS-only target
// in this initial commit (iOS target in a follow-up).

import SwiftUI

@main
struct MazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { /* no New File */ }
        }
    }
}
