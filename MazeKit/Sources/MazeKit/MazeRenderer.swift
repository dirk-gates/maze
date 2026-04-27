// MazeRenderer -- headless drawing of a finished Maze into a
// CGContext. Pure CoreGraphics, no UIKit/AppKit, so it works for
// thumbnails (bitmap context), PDF export, share images, etc. on
// every Apple platform.
//
// Call shape mirrors MazeCanvasView's draw step: fill the maze
// rect with `wallColor`, then carve cells, open walls, and the
// entrance / exit gates with `carvedColor`. The maze is centered
// inside `bounds` and uniformly scaled so cells stay square.

import CoreGraphics

public enum MazeRenderer {
    /// Render `maze` into `ctx` at `bounds`. Both colors should be
    /// fully opaque -- partial transparency would expose whatever
    /// the caller painted under `bounds` first.
    public static func render(
        _ maze     : Maze,
        in ctx     : CGContext,
        bounds     : CGRect,
        wallColor  : CGColor,
        carvedColor: CGColor
    ) {
        let w = maze.width
        let h = maze.height
        // 3:1 cell:wall ratio matches MazeCanvasView so thumbnails
        // visually match the live render.
        let unitsX = CGFloat(w * 4 + 1)
        let unitsY = CGFloat(h * 4 + 1)
        let unit   = min(bounds.width / unitsX, bounds.height / unitsY)
        let cs     = unit * 3
        let ws     = unit
        let stride = cs + ws
        let mazeW  = CGFloat(w) * cs + CGFloat(w + 1) * ws
        let mazeH  = CGFloat(h) * cs + CGFloat(h + 1) * ws
        let ox     = bounds.minX + (bounds.width  - mazeW) / 2
        let oy     = bounds.minY + (bounds.height - mazeH) / 2

        // ---- material (walls fill the whole maze rect) ----
        ctx.setFillColor(wallColor)
        ctx.fill(CGRect(x: ox, y: oy, width: mazeW, height: mazeH))

        // ---- carved regions in one fill pass ----
        ctx.setFillColor(carvedColor)
        ctx.beginPath()

        // cells
        for y in 0..<h {
            for x in 0..<w {
                ctx.addRect(CGRect(
                    x     : ox + ws + CGFloat(x) * stride,
                    y     : oy + ws + CGFloat(y) * stride,
                    width : cs,
                    height: cs
                ))
            }
        }

        // open walls between adjacent cells
        for y in 0..<h {
            for x in 0..<w {
                let here = Coord(x: x, y: y)
                if x + 1 < w {
                    let east = Coord(x: x + 1, y: y)
                    if !maze.wall(between: here, east) {
                        ctx.addRect(CGRect(
                            x     : ox + CGFloat(x + 1) * stride,
                            y     : oy + ws + CGFloat(y) * stride,
                            width : ws,
                            height: cs
                        ))
                    }
                }
                if y + 1 < h {
                    let south = Coord(x: x, y: y + 1)
                    if !maze.wall(between: here, south) {
                        ctx.addRect(CGRect(
                            x     : ox + ws + CGFloat(x) * stride,
                            y     : oy + CGFloat(y + 1) * stride,
                            width : cs,
                            height: ws
                        ))
                    }
                }
            }
        }

        // entrance / exit gates (sit on the maze border, outside the cell grid)
        if maze.entrance.x >= 0, maze.entrance.x < w {
            ctx.addRect(CGRect(
                x     : ox + ws + CGFloat(maze.entrance.x) * stride,
                y     : oy,
                width : cs,
                height: ws
            ))
        }
        if maze.exit.x >= 0, maze.exit.x < w {
            ctx.addRect(CGRect(
                x     : ox + ws + CGFloat(maze.exit.x) * stride,
                y     : oy + mazeH - ws,
                width : cs,
                height: ws
            ))
        }

        ctx.fillPath()
    }
}
