// MazeCanvasView -- vector rendering of the maze. Carve-out-of-
// material visual (white walls on black in dark mode, black walls
// on white in light mode); generation animates by progressively
// painting cells and wall slots with `theme.carved` over the solid
// `theme.material` block.

import SwiftUI
import MazeKit

struct MazeCanvasView: View {
    @Bindable var viewModel: MazeViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme.classic(colorScheme)
        Canvas { context, size in
            draw(context: context, size: size, theme: theme)
        }
        .background(theme.background)
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    private func draw(context: GraphicsContext, size: CGSize, theme: Theme) {
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

        // -------- material (uncarved) --------
        context.fill(
            Path(CGRect(x: ox, y: oy, width: mazeW, height: mazeH)),
            with: .color(theme.material))

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

        let carvedShade = GraphicsContext.Shading.color(theme.carved)

        // -------- carved cells --------
        for c in viewModel.carvedCells {
            context.fill(Path(cellRect(c)), with: carvedShade)
        }

        // -------- open wall slots --------
        for edge in viewModel.openWalls {
            context.fill(Path(wallRect(edge)), with: carvedShade)
        }

        // -------- entrance / exit gates in the border --------
        if let entrance = viewModel.entranceGate, entrance.x >= 0, entrance.x < w {
            let x = ox + ws + CGFloat(entrance.x) * stride
            context.fill(
                Path(CGRect(x: x, y: oy, width: cs, height: ws)),
                with: carvedShade)
        }
        if let exit = viewModel.exitGate, exit.x >= 0, exit.x < w {
            let x = ox + ws + CGFloat(exit.x) * stride
            let y = oy + mazeH - ws
            context.fill(
                Path(CGRect(x: x, y: y, width: cs, height: ws)),
                with: carvedShade)
        }

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
    }
}
