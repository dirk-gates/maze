// IconGenerator -- one-off command-line tool that renders a square
// PNG of a maze, suitable for Asset Catalog AppIcon slots. Same
// visual style as the live app: solid black field with thin white
// walls and a green solution path.
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
        // "extend past the bezel" is intentional.
        // 1:5 wall-to-cell ratio.

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

        // ---- paint ----

        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let green = CGColor(red: 0.227, green: 0.835, blue: 0.408, alpha: 1)

        ctx.setFillColor(black)
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

        ctx.setFillColor(white)
        ctx.fill(CGRect(x: ox, y: oy, width: mazeW, height: mazeH))

        ctx.setFillColor(black)
        for y in 0..<mh {
            for x in 0..<mw {
                let cx = ox + ws + CGFloat(x) * stride
                let cy = oy + ws + CGFloat(y) * stride
                ctx.fill(CGRect(x: cx, y: cy, width: cs, height: cs))
            }
        }
        for y in 0..<mh {
            for x in 0..<mw {
                let cur = Coord(x: x, y: y)
                if x + 1 < mw, !maze.wall(between: cur, Coord(x: x + 1, y: y)) {
                    let wx = ox + CGFloat(x + 1) * stride
                    let wy = oy + ws + CGFloat(y) * stride
                    ctx.fill(CGRect(x: wx, y: wy, width: ws, height: cs))
                }
                if y + 1 < mh, !maze.wall(between: cur, Coord(x: x, y: y + 1)) {
                    let wx = ox + ws + CGFloat(x) * stride
                    let wy = oy + CGFloat(y + 1) * stride
                    ctx.fill(CGRect(x: wx, y: wy, width: cs, height: ws))
                }
            }
        }

        let entranceX = ox + ws + CGFloat(maze.entrance.x) * stride
        ctx.fill(CGRect(x: entranceX, y: oy, width: cs, height: ws))
        let exitX = ox + ws + CGFloat(maze.exit.x) * stride
        ctx.fill(CGRect(x: exitX, y: oy + mazeH - ws, width: cs, height: ws))

        if let path = maze.solution, path.count > 1 {
            ctx.setStrokeColor(green)
            ctx.setLineWidth(max(1, cs * 0.7))
            ctx.setLineCap (.round)
            ctx.setLineJoin(.round)
            ctx.beginPath()
            for (i, c) in path.enumerated() {
                let cx = ox + ws + CGFloat(c.x) * stride + cs / 2
                let cy = oy + ws + CGFloat(c.y) * stride + cs / 2
                if i == 0 { ctx.move(to: CGPoint(x: cx, y: cy)) }
                else      { ctx.addLine(to: CGPoint(x: cx, y: cy)) }
            }
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to:    CGPoint(x: entranceX + cs / 2, y: oy))
            ctx.addLine(to: CGPoint(x: entranceX + cs / 2, y: oy + ws + cs / 2))
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to:    CGPoint(x: exitX + cs / 2, y: oy + mazeH - ws - cs / 2))
            ctx.addLine(to: CGPoint(x: exitX + cs / 2, y: oy + mazeH))
            ctx.strokePath()
        }

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
