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
