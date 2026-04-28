// MazeCanvasView -- vector rendering of the maze. Carve-out-of-
// material visual (white walls on black in dark mode, black walls
// on white in light mode); generation animates by progressively
// painting cells and wall slots with `theme.carved` over the solid
// `theme.material` block.

import SwiftUI
import MazeKit

struct MazeCanvasView: View {
    @Bindable var viewModel: MazeViewModel
    let theme: Theme

    var body: some View {
        // TimelineView(.animation) drives a 60fps redraw so the
        // leaf particles can fade + drift over real time. The maze
        // body itself is also redrawn every frame; that's fast
        // enough for our cell counts on modern hardware and saves
        // us managing two layers.
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(context: context, size: size, theme: theme, now: timeline.date)
            }
        }
        .background(theme.background)
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    private func draw(context: GraphicsContext, size: CGSize, theme: Theme, now: Date) {
        let w = viewModel.width
        let h = viewModel.height

        // 3:1 cell-to-wall ratio; fit the larger of the two axes.
        let unitsX = CGFloat(w * 3 + (w + 1))
        let unitsY = CGFloat(h * 3 + (h + 1))
        let unit   = min(size.width / unitsX, size.height / unitsY)
        let cs     = unit * 3
        let ws     = unit * 1
        let stride = cs + ws

        let mazeW = CGFloat(w) * cs + CGFloat(w + 1) * ws
        let mazeH = CGFloat(h) * cs + CGFloat(h + 1) * ws
        let ox    = (size.width  - mazeW) / 2
        let oy    = (size.height - mazeH) / 2

        // -------- floor (path color fills the whole maze rect) -----
        // Walls are drawn AFTER the carved-path computation as the
        // SUBTRACTED inverse of the carved area, so we can apply a
        // shadow filter that casts onto the path floor below.
        context.fill(
            Path(CGRect(x: ox, y: oy, width: mazeW, height: mazeH)),
            with: .color(theme.carved))

        // -------- helpers --------
        func cellRect(_ c: Coord) -> CGRect {
            let x = ox + ws + CGFloat(c.x) * stride
            let y = oy + ws + CGFloat(c.y) * stride
            return CGRect(x: x, y: y, width: cs, height: cs)
        }

        func wallRect(_ edge: MazeKit.Edge) -> CGRect {
            let a = edge.a
            let b = edge.b
            if a.y == b.y {
                let wallIdx = max(a.x, b.x)
                let x = ox + CGFloat(wallIdx) * stride
                let y = oy + ws + CGFloat(a.y) * stride
                return CGRect(x: x, y: y, width: ws, height: cs)
            } else {
                let wallIdx = max(a.y, b.y)
                let x = ox + ws + CGFloat(a.x) * stride
                let y = oy + CGFloat(wallIdx) * stride
                return CGRect(x: x, y: y, width: cs, height: ws)
            }
        }

        // Build a single Path containing every carved region (cells,
        // open walls, gates). Filling each rect separately produces
        // faint anti-aliasing seams at adjacent boundaries; a single
        // path treats them as one shape.
        var carvedPath = Path()
        for c in viewModel.carvedCells {
            carvedPath.addRect(cellRect(c))
        }
        for edge in viewModel.openWalls {
            carvedPath.addRect(wallRect(edge))
        }
        if let entrance = viewModel.entranceGate, entrance.x >= 0, entrance.x < w {
            let x = ox + ws + CGFloat(entrance.x) * stride
            carvedPath.addRect(CGRect(x: x, y: oy, width: cs, height: ws))
        }
        if let exit = viewModel.exitGate, exit.x >= 0, exit.x < w {
            let x = ox + ws + CGFloat(exit.x) * stride
            let y = oy + mazeH - ws
            carvedPath.addRect(CGRect(x: x, y: y, width: cs, height: ws))
        }

        // -------- walls = (maze rect) − (carved path) --------
        // Fake-3D extrusion: draw the walls TWICE.
        //   1) A darker copy shifted down-right: reads as the
        //      "shaded side" of the hedge.
        //   2) The original on top: the "lit top" of the hedge.
        // Works in both light and dark mode because both colors
        // come from the wall material, not the floor.
        let mazeRectPath = Path(CGRect(x: ox, y: oy, width: mazeW, height: mazeH))
        let wallsPath    = mazeRectPath.subtracting(carvedPath)

        let extrude = max(2.0, ws * 0.9)
        context.drawLayer { layer in
            layer.translateBy(x: extrude, y: extrude)
            layer.fill(wallsPath, with: .color(theme.wallShadow))
        }
        context.fill(wallsPath, with: .color(theme.material))

        // -------- solution path (themed stroke through cell centers) --------
        let cellsDrawn = min(viewModel.solveProgress, viewModel.solutionPath.count)
        if cellsDrawn > 1 {
            var solPath = Path()
            for (i, c) in viewModel.solutionPath.prefix(cellsDrawn).enumerated() {
                let cx = ox + ws + CGFloat(c.x) * stride + cs / 2
                let cy = oy + ws + CGFloat(c.y) * stride + cs / 2
                if i == 0 { solPath.move (to: CGPoint(x: cx, y: cy)) }
                else      { solPath.addLine(to: CGPoint(x: cx, y: cy)) }
            }
            context.stroke(
                solPath,
                with: .color(theme.solution),
                style: StrokeStyle(lineWidth: cs * 0.36,
                                   lineCap: .round, lineJoin: .round))
        }

        // -------- carve animation: leaves + lawnmower --------
        // Drawn AFTER the maze so they sit on top. Only show
        // while we're still generating (lastCarve is nil after
        // .finished).
        // Leaves fly out from where they spawned; cell origin
        // shifts via velocity * age + a little gravity.
        let gravity: CGFloat = 60.0   // px/s² downward
        for leaf in viewModel.leaves {
            let age = now.timeIntervalSince(leaf.spawnedAt)
            if age > 1.0 { continue }
            let cellOX = ox + ws + CGFloat(leaf.cellX) * stride + cs / 2
            let cellOY = oy + ws + CGFloat(leaf.cellY) * stride + cs / 2
            let dx = leaf.velocityX * CGFloat(age)
            let dy = leaf.velocityY * CGFloat(age)
                   + 0.5 * gravity   * CGFloat(age * age)
            let px = cellOX + dx
            let py = cellOY + dy
            let opacity = max(0, 1.0 - age)
            let color   = Color(hue       : leaf.hue,
                                saturation: 0.7,
                                brightness: 0.55)
                          .opacity(opacity)
            context.fill(
                Path(ellipseIn: CGRect(
                    x     : px - leaf.size / 2,
                    y     : py - leaf.size / 2,
                    width : leaf.size,
                    height: leaf.size
                )),
                with: .color(color)
            )
        }

        if let head = viewModel.lastCarve, viewModel.maze == nil {
            let r = cellRect(head)
            drawLawnmower(
                context: context,
                center : CGPoint(x: r.midX, y: r.midY),
                ws     : ws
            )
        }
    }

    /// Tiny stylised lawnmower: a brown rounded body with two
    /// black wheels at the bottom. Sized relative to the wall
    /// thickness so it fits within a single cell.
    private func drawLawnmower(context: GraphicsContext,
                               center : CGPoint,
                               ws     : CGFloat)
    {
        let s        = max(3.0, ws * 1.4)
        let bodyRect = CGRect(
            x     : center.x - s,
            y     : center.y - s * 0.45,
            width : s * 2,
            height: s * 0.9
        )
        context.fill(
            Path(roundedRect: bodyRect, cornerRadius: s * 0.18),
            with: .color(Color(red: 0.74, green: 0.30, blue: 0.18))
        )
        // Wheels just below the body
        let wr = s * 0.32
        let wy = bodyRect.maxY - wr * 0.15
        context.fill(
            Path(ellipseIn: CGRect(
                x     : bodyRect.minX - wr * 0.25,
                y     : wy - wr,
                width : wr * 2,
                height: wr * 2
            )),
            with: .color(.black)
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x     : bodyRect.maxX - wr * 1.75,
                y     : wy - wr,
                width : wr * 2,
                height: wr * 2
            )),
            with: .color(.black)
        )
    }
}
