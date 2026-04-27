// LibraryView -- presented as a sheet from ControlsView. Lists every
// saved maze (newest first) with its dims, look-ahead, and date. Tap
// a row to replay it (deterministic via the persisted seed). Swipe a
// row to delete; toolbar Clear wipes the lot. No thumbnails yet --
// rendering miniatures will come in a follow-up slice.

import MazeKit
import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: MazeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    if !viewModel.library.mazes.isEmpty {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Clear", role: .destructive) {
                                viewModel.library.clear()
                            }
                        }
                    }
                }
                .preferredColorScheme(resolvedScheme)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.library.mazes.isEmpty {
            ContentUnavailableView(
                "No saved mazes yet",
                systemImage: "square.grid.3x3.square",
                description: Text("Generated mazes appear here automatically. Tap one to replay it.")
            )
        } else {
            List {
                ForEach(viewModel.library.mazes) { saved in
                    Button {
                        viewModel.load(saved)
                        dismiss()
                    } label: {
                        row(for: saved)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    viewModel.library.remove(at: offsets)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private func row(for saved: SavedMaze) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: saved)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(saved.width) × \(saved.height)")
                    .font(.headline.monospacedDigit())
                Text(metadataLine(for: saved))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(saved.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for saved: SavedMaze) -> some View {
        let placeholder = RoundedRectangle(cornerRadius: 6)
            .fill(.tertiary)
            .frame(width: 56, height: 56)
        if let name = saved.thumbnailFilename,
           let img  = MazeThumbnail.image(filename: name) {
            img.resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 0.5)
                )
        } else {
            placeholder
        }
    }

    private func metadataLine(for saved: SavedMaze) -> String {
        let look = saved.lookAheadDepth == 0 ? "no look-ahead"
                                             : "look-ahead \(saved.lookAheadDepth)"
        // Last 6 hex digits of the seed -- distinctive enough to
        // recognise across rows without dominating the row.
        let seedTag = String(format: "#%06llx", saved.seed & 0xffffff)
        return "\(look) • \(seedTag)"
    }

    /// Always explicit (.light or .dark) so the sheet respects the
    /// appearance picker reliably -- nil overrides on sheets do not
    /// release a previously applied scheme. Same trick used in
    /// SettingsView.
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
}
