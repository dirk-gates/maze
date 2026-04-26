// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.

import SwiftUI

struct ContentView: View {
    @State private var viewModel        = MazeViewModel()
    @State private var showingSettings  = false
    @State private var didInitialLaunch = false
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
        // Apply preferredColorScheme ONLY when the user has chosen a
        // specific override. SwiftUI's .preferredColorScheme(nil) does
        // not reliably "release" a previously set override -- the
        // window stays in the prior scheme. Applying the modifier
        // conditionally side-steps that, so going back to System
        // immediately reverts the chrome to the actual system value.
        if let scheme = schemeOverride {
            mainContent.preferredColorScheme(scheme)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            MazeCanvasView(viewModel: viewModel, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel, showingSettings: $showingSettings)
        }
        .background(theme.background)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
        .sheet(isPresented: $showingSettings) {
            // Same conditional-preferredColorScheme dance as the root.
            // The sheet is its own view hierarchy, so the modifier on
            // mainContent does not propagate in -- we have to apply it
            // (and release it) on the sheet content directly, or going
            // back to System leaves the sheet stuck in the prior scheme.
            if let scheme = schemeOverride {
                SettingsView(viewModel: viewModel)
                    .preferredColorScheme(scheme)
            } else {
                SettingsView(viewModel: viewModel)
            }
        }
        .onAppear {
            // Gate to the first-ever appearance. On iOS, dismissing
            // the Settings sheet re-fires .onAppear on the host view,
            // and we don't want that to auto-regenerate -- the user
            // should have to press Generate explicitly.
            guard !didInitialLaunch else { return }
            didInitialLaunch = true
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
