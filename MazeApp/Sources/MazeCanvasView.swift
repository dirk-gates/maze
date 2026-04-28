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
            // Direction of motion = lastCarve - prevCarve, in
            // pixel space. Defaults to facing east when there's
            // no prev (start of generation).
            var angle: CGFloat = 0
            if let prev = viewModel.prevCarve {
                let dx = CGFloat(head.x - prev.x)
                let dy = CGFloat(head.y - prev.y)
                if dx != 0 || dy != 0 {
                    angle = atan2(dy, dx)
                }
            }
            drawHedgehog(
                context: context,
                center : CGPoint(x: r.midX, y: r.midY),
                angle  : angle,
                cs     : cs,
                now    : now
            )
        }
    }

    /// Top-down hedgehog head chomping its way through the hedge,
    /// Pac-Man style: round body, quills fanning around the back
    /// half, and a wedge mouth at the front that opens and closes
    /// at ~3.5 Hz to "eat" through the maze. Same role as the old
    /// lawnmower icon -- reads as "the carve head is here, moving
    /// in this direction".
    private func drawHedgehog(context: GraphicsContext,
                              center : CGPoint,
                              angle  : CGFloat,
                              cs     : CGFloat,
                              now    : Date)
    {
        let s = min(32.0, max(14.0, cs * 0.45))

        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: .radians(angle))
        // After rotation: +X is forward (carving direction).

        // Chomp animation. cos so phase=0 starts mouth fully open;
        // ~3.5 Hz feels lively without being frantic. Floor the
        // half-angle slightly above zero so even a "closed" mouth
        // shows a thin slit -- reads as a face, not a featureless
        // ball.
        let t = now.timeIntervalSinceReferenceDate
        let cycle = (cos(t * 2 * .pi * 3.5) + 1) / 2          // 0..1
        let mouthHalf: CGFloat = 0.04 + CGFloat(cycle) * 0.55  // ~2°..34°

        let body  = Color(red: 0.62, green: 0.45, blue: 0.27)  // warm tan
        let quill = Color(red: 0.32, green: 0.20, blue: 0.10)  // dark brown
        let mouth = Color(red: 0.30, green: 0.10, blue: 0.10)  // dark red-brown

        // ---- quills: short triangles fanning across the back
        //      hemisphere, from upper-back through rear to lower-
        //      back. Each is a thin isoceles triangle pointing
        //      radially outward. Drawn first so the body covers
        //      their bases.
        let quillCount    = 13
        let quillStartA   : CGFloat = .pi * 0.40   // upper back, behind eye
        let quillEndA     : CGFloat = .pi * 1.60   // lower back
        let quillBaseR    = s * 0.62
        let quillTipR     = s * 1.05
        for i in 0..<quillCount {
            let frac  = CGFloat(i) / CGFloat(quillCount - 1)
            let theta = quillStartA + frac * (quillEndA - quillStartA)
            let dir   = CGPoint(x: cos(theta),  y: sin(theta))
            let perp  = CGPoint(x: -dir.y,      y: dir.x)
            let halfW = s * 0.045
            var path = Path()
            path.move(to: CGPoint(
                x: quillBaseR * dir.x + halfW * perp.x,
                y: quillBaseR * dir.y + halfW * perp.y))
            path.addLine(to: CGPoint(
                x: quillTipR * dir.x,
                y: quillTipR * dir.y))
            path.addLine(to: CGPoint(
                x: quillBaseR * dir.x - halfW * perp.x,
                y: quillBaseR * dir.y - halfW * perp.y))
            path.closeSubpath()
            ctx.fill(path, with: .color(quill))
        }

        // ---- body: full circle ----
        let bodyR = s * 0.7
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: -bodyR, y: -bodyR,
                width: bodyR * 2, height: bodyR * 2)),
            with: .color(body))

        // ---- mouth wedge cut into the front of the body ----
        // Pivots at body center, sweeps ±mouthHalf around forward.
        // Filled in dark mouth color so the wedge reads as an
        // open mouth instead of a hole through the head.
        var mouthPath = Path()
        mouthPath.move(to: .zero)
        mouthPath.addArc(
            center    : .zero,
            radius    : bodyR + 0.5,                 // +0.5 to fully cover edge
            startAngle: .radians(-mouthHalf),
            endAngle  : .radians( mouthHalf),
            clockwise : false)
        mouthPath.closeSubpath()
        ctx.fill(mouthPath, with: .color(mouth))

        // ---- eye: small black dot, forward + above center ----
        let eyeR = s * 0.085
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: s * 0.20 - eyeR, y: -s * 0.30 - eyeR,
                width: eyeR * 2, height: eyeR * 2)),
            with: .color(.black))
    }
}
