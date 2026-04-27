// MazeThumbnail -- render a finished Maze to a small PNG cached on
// disk, and load it back as a SwiftUI Image. Called from the view
// model on every .finished event so the library list can show a
// recognizable preview alongside each row's metadata.
//
// Files live in Documents/thumbnails/<uuid>.png. We always write a
// neutral light-on-dark thumbnail (independent of the user's
// appearance pick) so it reads consistently in either system mode --
// the row chrome around it follows the live theme.

import CoreGraphics
import Foundation
import ImageIO
import MazeKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum MazeThumbnail {
    /// Edge length of the rendered thumbnail in pixels. 200 @2x =
    /// 400px on retina, plenty for a list row preview.
    private static let pixelSize: Int = 200

    /// Lazily create / return the thumbnails directory. Failure to
    /// create is non-fatal -- writes will just no-op and the row
    /// will fall back to the placeholder cell.
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in : .userDomainMask).first!
        let dir  = docs.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at                       : dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Render `maze` to PNG at `directory/<id>.png`. Returns the
    /// filename (not full path) on success so the caller can store
    /// it on the SavedMaze record without baking in the absolute
    /// container path -- which changes every install / restore.
    static func write(maze: Maze, id: UUID) -> String? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : pixelSize,
            height          : pixelSize,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        // White paths on near-black walls -- reads cleanly in both
        // light and dark library rows.
        let wallColor   = CGColor(gray: 0.10, alpha: 1.0)
        let carvedColor = CGColor(gray: 0.96, alpha: 1.0)

        ctx.setFillColor(carvedColor)
        ctx.fill(bounds)

        MazeRenderer.render(maze, in: ctx,
                            bounds     : bounds,
                            wallColor  : wallColor,
                            carvedColor: carvedColor)

        guard let image = ctx.makeImage() else { return nil }
        let filename = "\(id.uuidString).png"
        let fileURL  = url(for: filename)
        guard let dest = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return filename
    }

    /// Load a thumbnail by filename. Returns nil if the file is
    /// missing or unreadable -- caller falls back to a placeholder.
    static func image(filename: String) -> Image? {
        let path = url(for: filename).path
        #if os(iOS)
        guard let ui = UIImage(contentsOfFile: path) else { return nil }
        return Image(uiImage: ui)
        #elseif os(macOS)
        guard let ns = NSImage(contentsOfFile: path) else { return nil }
        return Image(nsImage: ns)
        #else
        return nil
        #endif
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
