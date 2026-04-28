// SettingsView -- presented as a sheet.
//
// Appearance binds DIRECTLY to the view model so toggling the picker
// updates the whole app live (no Apply needed). Size + look-ahead
// keep editing copies because applying them re-triggers the
// multi-second generation animation.

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: MazeViewModel
    @Environment(\.dismiss) private var dismiss

    // Editing copies for inputs whose change triggers a regenerate.
    @State private var width         : Int
    @State private var height        : Int
    @State private var lookAheadDepth: Int

    init(viewModel: MazeViewModel) {
        self.viewModel = viewModel
        self._width          = State(initialValue: viewModel.width)
        self._height         = State(initialValue: viewModel.height)
        self._lookAheadDepth = State(initialValue: viewModel.lookAheadDepth)
    }

    /// Always returns an explicit ColorScheme (never nil). When the
    /// user has chosen System, we read the live OS scheme directly so
    /// the sheet renders in that value. nil-overrides on sheets do
    /// not reliably revert a previously set scheme.
    private var resolvedScheme: ColorScheme {
        switch viewModel.appearance {
        case .light : return .light
        case .dark  : return .dark
        case .system:
            #if os(iOS)
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
            #elseif os(macOS)
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            #else
            return .light
            #endif
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $viewModel.appearance) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Hedge height", selection: $viewModel.hedgeHeight) {
                        ForEach(HedgeHeight.allCases) { h in
                            Text(h.displayName).tag(h)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Walk-mode hedges")
                } footer: {
                    Text("\"Waist high\" drops the hedges below eye level so you can see across the maze as you walk it. Takes effect on the next time you tap Walk.")
                        .font(.footnote)
                }
                Section {
                    LabeledContent("Camera tilt",
                                   value: "\(Int(viewModel.walkPitchDeg))°")
                    Slider(value: $viewModel.walkPitchDeg,
                           in   : -60...0,
                           step : 5)
                } header: {
                    Text("Walk-mode tilt")
                } footer: {
                    Text("How far the camera tilts down by default when entering walk mode, so the floor and the cyan solution path are visible from the start. Drag-to-look overrides this during the walk.")
                        .font(.footnote)
                }
                Section("Size") {
                    Stepper(value: $width, in: 4...80) {
                        LabeledContent("Width", value: "\(width) cells")
                    }
                    Stepper(value: $height, in: 4...80) {
                        LabeledContent("Height", value: "\(height) cells")
                    }
                }
                Section {
                    Stepper(value: $lookAheadDepth, in: 0...20) {
                        LabeledContent("Look-ahead depth",
                                       value: lookAheadDepth == 0 ? "off"
                                                                  : "\(lookAheadDepth)")
                    }
                } header: {
                    Text("Look-ahead")
                } footer: {
                    Text("Higher values produce harder mazes (longer corridors, fewer dead ends) but slow generation.")
                        .font(.footnote)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // CRITICAL: sheets do not reliably release a previously
            // set `.preferredColorScheme(nil)`. To make picking
            // "System" actually revert the sheet to the live system
            // scheme, we always apply an EXPLICIT (.light / .dark)
            // override here -- if the user picked System, we resolve
            // to the current OS scheme right now. Same pattern used
            // in our other SwiftUI apps in work/twbuild.
            .preferredColorScheme(resolvedScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.width          = width
                        viewModel.height         = height
                        viewModel.lookAheadDepth = lookAheadDepth
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }
}
