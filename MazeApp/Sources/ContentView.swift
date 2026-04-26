// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / speed.

import SwiftUI

struct ContentView: View {
    @State private var viewModel = MazeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            MazeCanvasView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel)
        }
        .background(Color.black)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
        .onAppear {
            // iPhone-friendly default size; macOS uses larger via .frame.
            #if os(iOS)
            viewModel.width  = 20
            viewModel.height = 30
            #endif
            viewModel.generate()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .mazeGenerate)) { _ in
            viewModel.generate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mazeSolve)) { _ in
            viewModel.solve()
        }
        #endif
    }
}
