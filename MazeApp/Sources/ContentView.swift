// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.

import SwiftUI

struct ContentView: View {
    @State private var viewModel       = MazeViewModel()
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var systemScheme

    /// Color scheme actually used for rendering, accounting for the
    /// user's appearance preference. Computed once per render pass
    /// and passed down to children that care -- avoids the
    /// `preferredColorScheme` / `@Environment(\.colorScheme)` quirk
    /// where a sibling view reads the system value while the chrome
    /// is overridden.
    private var effectiveScheme: ColorScheme {
        switch viewModel.appearance {
        case .system: return systemScheme
        case .light : return .light
        case .dark  : return .dark
        }
    }

    private var theme: Theme {
        Theme.classic(effectiveScheme)
    }

    private var schemeOverride: ColorScheme? {
        switch viewModel.appearance {
        case .system: return nil
        case .light : return .light
        case .dark  : return .dark
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MazeCanvasView(viewModel: viewModel, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel, showingSettings: $showingSettings)
        }
        .preferredColorScheme(schemeOverride)
        .background(theme.background)
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
