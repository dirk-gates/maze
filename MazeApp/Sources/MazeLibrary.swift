// MazeLibrary -- on-disk history of generated mazes. JSON file in
// the app's Documents directory, auto-loaded on init and rewritten
// whenever the collection changes. Capped FIFO so a long session
// doesn't grow unbounded; pinned/favorited mazes will get exempt
// treatment in a later slice.

import Foundation
import MazeKit
import Observation

@MainActor
@Observable
final class MazeLibrary {
    private(set) var mazes: [SavedMaze] = []

    /// Cap on the persisted history. Beyond this, the oldest entries
    /// get evicted. 200 is plenty for casual play and tiny on disk.
    private let maxEntries = 200

    init() { load() }

    /// Insert at the head, dedupe by (seed, dims, look-ahead) so
    /// re-rolling the same maze doesn't pile duplicates, then prune
    /// to maxEntries and persist.
    func append(_ maze: SavedMaze) {
        mazes.removeAll {
               $0.seed           == maze.seed
            && $0.width          == maze.width
            && $0.height         == maze.height
            && $0.lookAheadDepth == maze.lookAheadDepth
        }
        mazes.insert(maze, at: 0)
        if mazes.count > maxEntries {
            mazes.removeLast(mazes.count - maxEntries)
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        mazes.remove(atOffsets: offsets)
        save()
    }

    func remove(_ maze: SavedMaze) {
        mazes.removeAll { $0.id == maze.id }
        save()
    }

    func clear() {
        mazes.removeAll()
        save()
    }

    // ----- private I/O -----

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory,
                                           in : .userDomainMask).first!
        return dir.appendingPathComponent("MazeLibrary.json")
    }

    private func load() {
        guard let data    = try? Data(contentsOf: MazeLibrary.fileURL),
              let decoded = try? JSONDecoder().decode([SavedMaze].self, from: data)
        else { return }
        mazes = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mazes) else { return }
        try? data.write(to: MazeLibrary.fileURL, options: .atomic)
    }
}
