// MazeApp -- @main entry. Same scene used on macOS and iOS / iPadOS;
// macOS-only scene modifiers are guarded with #if os(macOS).
//
// The view model lives at App scope so that the appearance picker
// can drive `.preferredColorScheme` directly on the WindowGroup --
// which is what makes the override reach sheets and chrome, and
// makes "System" reliably revert (mirrors the pattern used in our
// other SwiftUI apps under /Users/dirkgates/work/twbuild).

import SwiftUI

@main
struct MazeApp: App {
    @State private var viewModel = MazeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .preferredColorScheme(viewModel.schemeOverride)
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
