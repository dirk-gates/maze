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
        .onAppear {
            viewModel.generate()
        }
    }
}
