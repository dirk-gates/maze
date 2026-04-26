// SettingsView -- presented as a sheet. Exposes the live-tunable
// generator parameters (size, look-ahead) and an Apply button that
// kicks off a fresh generation with the new values.
//
// Keeps the view-model untouched until "Apply" so users can tweak
// freely without instantly re-triggering a multi-second animation.

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: MazeViewModel
    @Environment(\.dismiss) private var dismiss

    // Editing copies; written back on Apply.
    @State private var width         : Int
    @State private var height        : Int
    @State private var lookAheadDepth: Int
    @State private var appearance    : AppearancePreference

    init(viewModel: MazeViewModel) {
        self.viewModel = viewModel
        self._width          = State(initialValue: viewModel.width)
        self._height         = State(initialValue: viewModel.height)
        self._lookAheadDepth = State(initialValue: viewModel.lookAheadDepth)
        self._appearance     = State(initialValue: viewModel.appearance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Size") {
                    Stepper(value: $width, in: 4...80) {
                        LabeledContent("Width", value: "\(width) cells")
                    }
                    Stepper(value: $height, in: 4...80) {
                        LabeledContent("Height", value: "\(height) cells")
                    }
                }
                Section {
                    Stepper(value: $lookAheadDepth, in: 0...10) {
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
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.width          = width
                        viewModel.height         = height
                        viewModel.lookAheadDepth = lookAheadDepth
                        viewModel.appearance     = appearance
                        viewModel.generate()
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }
}
