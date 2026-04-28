// IconGenerator -- one-off command-line tool that renders a square
// PNG of a maze, suitable for Asset Catalog AppIcon slots. Same
// visual style as the live in-app render: black background with
// green hedges drawn over a darker-green offset shadow that gives
// each wall a fake-3D extrusion.
//
// Usage:
//   swift run MazeIconGenerator SIZE OUTPUT_PATH
//
// Run once per target size (16, 32, 64, 128, 256, 512, 1024) to
// produce all the per-slot PNGs Xcode wants for macOS, plus the
// single 1024 used by iOS.
//
// File is intentionally NOT named main.swift -- with @main, Swift
// disallows that. The struct's static main() is the entry point.

import CoreGraphics
import Foundation
import ImageIO
import MazeKit
import UniformTypeIdentifiers

@main
struct IconGenerator {
    static func main() async {
        guard CommandLine.arguments.count >= 3,
              let canvasSize = Int(CommandLine.arguments[1]) else {
            FileHandle.standardError.write(
                Data("Usage: MazeIconGenerator SIZE OUTPUT_PATH\n".utf8))
            exit(1)
        }
        let outPath = CommandLine.arguments[2]

        // Maze dimensions: chosen so cells look crisp at 1024 and the
        // texture is dense enough to read as "a maze" at small icon
        // sizes. Slightly portrait matches the live-app screenshot.
        // Same fixed seed across all sizes so the icon is the SAME
        // maze rendered at every resolution.
        let mw   = 18
        let mh   = 22
        let seed: UInt64 = 314_159

        let params = GeneratorParameters(
            width         : mw,
            height        : mh,
            lookAheadDepth: 4,
            seed          : seed)

        var maze: Maze?
        for await event in Generator(params).generate() {
            if case .finished(let m) = event { maze = m }
        }
        guard let maze else {
            FileHandle.standardError.write(Data("Generator produced no maze\n".utf8))
            exit(1)
        }

        // ---- geometry ----
        // Fit to WIDTH, let the height bleed off top and bottom. The
        // system mask rounds the corners, so the maze appearing to
        // "extend past the bezel" is intentional. 1:5 wall-to-cell.

        let canvas : CGFloat = CGFloat(canvasSize)
        let unitsX = CGFloat(mw * 5 + (mw + 1))
        let unit   = canvas / unitsX
        let cs     = unit * 5
        let ws     = unit * 1
        let stride = cs + ws
        let mazeW  = canvas
        let mazeH  = CGFloat(mh) * cs + CGFloat(mh + 1) * ws
        let ox     : CGFloat = 0
        let oy     = (canvas - mazeH) / 2     // negative -- maze taller than canvas
        // Shadow extrude matches MazeCanvasView's `max(2.0, ws*0.9)`.
        let extrude = max(2.0, ws * 0.9)

        // ---- context ----

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data            : nil,
            width           : Int(canvas),
            height          : Int(canvas),
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : colorSpace,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            FileHandle.standardError.write(Data("Could not create CGContext\n".utf8))
            exit(1)
        }
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy   (x: 1, y: -1)

        // ---- walls path ----
        // Build a single path that covers the WALL regions only,
        // using the even-odd fill rule: maze rect minus every cell
        // / open-wall slot / gate. Filling this path twice (offset
        // for shadow, then at origin for the lit top) reproduces
        // the in-app fake-3D extrusion.

        let walls = CGMutablePath()
        walls.addRect(CGRect(x: ox, y: oy, width: mazeW, height: mazeH))

        // cells (carved squares)
        for y in 0..<mh {
            for x in 0..<mw {
                walls.addRect(CGRect(
                    x     : ox + ws + CGFloat(x) * stride,
                    y     : oy + ws + CGFloat(y) * stride,
                    width : cs,
                    height: cs
                ))
            }
        }

        // open passages between adjacent cells
        for y in 0..<mh {
            for x in 0..<mw {
                let here = Coord(x: x, y: y)
                if x + 1 < mw, !maze.wall(between: here, Coord(x: x + 1, y: y)) {
                    walls.addRect(CGRect(
                        x     : ox + CGFloat(x + 1) * stride,
                        y     : oy + ws + CGFloat(y) * stride,
                        width : ws,
                        height: cs
                    ))
                }
                if y + 1 < mh, !maze.wall(between: here, Coord(x: x, y: y + 1)) {
                    walls.addRect(CGRect(
                        x     : ox + ws + CGFloat(x) * stride,
                        y     : oy + CGFloat(y + 1) * stride,
                        width : cs,
                        height: ws
                    ))
                }
            }
        }

        // entrance / exit gates -- carved through the perimeter wall
        if maze.entrance.x >= 0, maze.entrance.x < mw {
            walls.addRect(CGRect(
                x     : ox + ws + CGFloat(maze.entrance.x) * stride,
                y     : oy,
                width : cs,
                height: ws
            ))
        }
        if maze.exit.x >= 0, maze.exit.x < mw {
            walls.addRect(CGRect(
                x     : ox + ws + CGFloat(maze.exit.x) * stride,
                y     : oy + mazeH - ws,
                width : cs,
                height: ws
            ))
        }

        // ---- paint ----
        // Palette matches Theme.classic dark-mode hedges: lit top is
        // `material`, shaded side is `wallShadow`. Black background
        // = the carved-path color when no path tile is overlaid.

        let black      = CGColor(red: 0,    green: 0,    blue: 0,    alpha: 1)
        let material   = CGColor(red: 0.18, green: 0.45, blue: 0.18, alpha: 1)
        let wallShadow = CGColor(red: 0.07, green: 0.20, blue: 0.07, alpha: 1)

        ctx.setFillColor(black)
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

        // Shadow: same walls path, drawn first, shifted +x +y.
        ctx.saveGState()
        ctx.translateBy(x: extrude, y: extrude)
        ctx.setFillColor(wallShadow)
        ctx.addPath(walls)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // Lit top.
        ctx.setFillColor(material)
        ctx.addPath(walls)
        ctx.fillPath(using: .evenOdd)

        // ---- write ----

        guard let image = ctx.makeImage() else {
            FileHandle.standardError.write(Data("Could not finalize image\n".utf8))
            exit(1)
        }
        let url = URL(fileURLWithPath: outPath)
        guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1, nil) else {
            FileHandle.standardError.write(Data("Could not create destination\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            FileHandle.standardError.write(Data("Could not finalize PNG\n".utf8))
            exit(1)
        }
        print("Wrote \(url.path) (\(canvasSize)x\(canvasSize))")
    }
}
