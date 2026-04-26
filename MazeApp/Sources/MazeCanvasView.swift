// MazeCanvasView -- vector rendering of the maze. New visual model:
// the maze starts as a solid block of "material" (white), and
// generation carves cells and wall slots out of it (black). When
// generation finishes, the rendered image is unchanged -- there's
// no flicker or transition because the carved set IS the final maze.
//
// Layout uses a 3:1 cell-to-wall ratio. Each cell is a square of
// `cs` units; each wall slot between cells is `ws = cs / 3` thick.
// Wall corners stay solid white (they're never carved).

import SwiftUI
import MazeKit

struct MazeCanvasView: View {
    @Bindable var viewModel: MazeViewModel

    var body: some View {
        Canvas { context, size in
            draw(context: context, size: size)
        }
        .background(Color.black)
    }

    // ------------------------------------------------------------------
    // Drawing
    // ------------------------------------------------------------------

    private func draw(context: GraphicsContext, size: CGSize) {
        let w = viewModel.width
        let h = viewModel.height

        // 3:1 cell-to-wall ratio; fit the larger of the two axes.
        let unitsX = CGFloat(w * 3 + (w + 1))
        let unitsY = CGFloat(h * 3 + (h + 1))
        let unit   = min(size.width / unitsX, size.height / unitsY)
        let cs     = unit * 3      // cell side
        let ws     = unit * 1      // wall thickness

        let mazeW = CGFloat(w) * cs + CGFloat(w + 1) * ws
        let mazeH = CGFloat(h) * cs + CGFloat(h + 1) * ws
        let ox    = (size.width  - mazeW) / 2
        let oy    = (size.height - mazeH) / 2

        // -------- material (uncarved) --------
        context.fill(
            Path(CGRect(x: ox, y: oy, width: mazeW, height: mazeH)),
            with: .color(.white))

        // -------- helpers --------
        let stride = cs + ws

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

        let carvedColor = GraphicsContext.Shading.color(.black)

        // -------- carved cells --------
        for c in viewModel.carvedCells {
            context.fill(Path(cellRect(c)), with: carvedColor)
        }

        // -------- open wall slots --------
        for edge in viewModel.openWalls {
            context.fill(Path(wallRect(edge)), with: carvedColor)
        }

        // -------- entrance / exit gates in the border --------
        if let entrance = viewModel.entranceGate, entrance.x >= 0, entrance.x < w {
            let x = ox + ws + CGFloat(entrance.x) * stride
            context.fill(
                Path(CGRect(x: x, y: oy, width: cs, height: ws)),
                with: carvedColor)
        }
        if let exit = viewModel.exitGate, exit.x >= 0, exit.x < w {
            let x = ox + ws + CGFloat(exit.x) * stride
            let y = oy + mazeH - ws
            context.fill(
                Path(CGRect(x: x, y: y, width: cs, height: ws)),
                with: carvedColor)
        }

        // -------- solution path (green stroke through cell centers) --------
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
                with: .color(.green),
                style: StrokeStyle(lineWidth: cs * 0.36,
                                   lineCap: .round, lineJoin: .round))
        }
    }
}
