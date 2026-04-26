// MazeApp -- @main entry. Same scene used on macOS and iOS / iPadOS;
// macOS-only scene modifiers are guarded with #if os(macOS).

import SwiftUI

@main
struct MazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            #if os(macOS)
                .frame(minWidth: 600, minHeight: 480)
            #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { /* no New File */ }
            CommandGroup(after: .toolbar) {
                Button("Generate") {
                    NotificationCenter.default.post(name: .mazeGenerate, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Solve") {
                    NotificationCenter.default.post(name: .mazeSolve, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let mazeGenerate = Notification.Name("MazeApp.generate")
    static let mazeSolve    = Notification.Name("MazeApp.solve")
}
