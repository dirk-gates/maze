// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.

import SwiftUI

struct ContentView: View {
    @State private var viewModel       = MazeViewModel()
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    private var schemeOverride: ColorScheme? {
        switch viewModel.appearance {
        case .system: return nil
        case .light : return .light
        case .dark  : return .dark
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MazeCanvasView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel, showingSettings: $showingSettings)
        }
        .preferredColorScheme(schemeOverride)
        .background(Theme.classic(colorScheme).background)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
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
