// MazeCanvasView -- vector rendering of the maze and the live carving
// animation. Pure SwiftUI Canvas, no per-cell views, no AppKit.
// Phase 3 will add theme support; this is the "Classic" baseline.

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

        let cellSize = min(size.width  / CGFloat(w + 2),
                           size.height / CGFloat(h + 2))
        let mazeW = cellSize * CGFloat(w)
        let mazeH = cellSize * CGFloat(h)
        let ox    = (size.width  - mazeW) / 2
        let oy    = (size.height - mazeH) / 2

        // -------- carved-cell shading (visible during generation) --------
        if viewModel.maze == nil {
            let pathCellColor = Color.white.opacity(0.16)
            for c in viewModel.carvedCells {
                let rect = CGRect(
                    x      : ox + CGFloat(c.x) * cellSize,
                    y      : oy + CGFloat(c.y) * cellSize,
                    width  : cellSize,
                    height : cellSize)
                context.fill(Path(rect), with: .color(pathCellColor))
            }
        }

        guard let maze = viewModel.maze else { return }

        // -------- solution path (drawn beneath walls) --------
        let cellsDrawn = min(viewModel.solveProgress, viewModel.solutionPath.count)
        if cellsDrawn > 1 {
            var solPath = Path()
            for (i, c) in viewModel.solutionPath.prefix(cellsDrawn).enumerated() {
                let cx = ox + CGFloat(c.x) * cellSize + cellSize / 2
                let cy = oy + CGFloat(c.y) * cellSize + cellSize / 2
                if i == 0 { solPath.move (to: CGPoint(x: cx, y: cy)) }
                else      { solPath.addLine(to: CGPoint(x: cx, y: cy)) }
            }
            context.stroke(
                solPath,
                with: .color(.green.opacity(0.85)),
                style: StrokeStyle(lineWidth: cellSize * 0.42,
                                   lineCap: .round, lineJoin: .round))
        }

        // -------- walls --------
        var walls = Path()
        let lineWidth = max(1.0, cellSize * 0.06)

        // Top border with entrance gap
        walls.move (to: CGPoint(x: ox, y: oy))
        walls.addLine(to: CGPoint(x: ox + CGFloat(maze.entrance.x) * cellSize, y: oy))
        walls.move (to: CGPoint(x: ox + CGFloat(maze.entrance.x + 1) * cellSize, y: oy))
        walls.addLine(to: CGPoint(x: ox + mazeW, y: oy))

        // Right
        walls.move (to: CGPoint(x: ox + mazeW, y: oy))
        walls.addLine(to: CGPoint(x: ox + mazeW, y: oy + mazeH))

        // Bottom border with exit gap
        walls.move (to: CGPoint(x: ox + mazeW, y: oy + mazeH))
        walls.addLine(to: CGPoint(x: ox + CGFloat(maze.exit.x + 1) * cellSize, y: oy + mazeH))
        walls.move (to: CGPoint(x: ox + CGFloat(maze.exit.x) * cellSize, y: oy + mazeH))
        walls.addLine(to: CGPoint(x: ox, y: oy + mazeH))

        // Left
        walls.move (to: CGPoint(x: ox, y: oy + mazeH))
        walls.addLine(to: CGPoint(x: ox, y: oy))

        // Internal walls
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let cur = Coord(x: x, y: y)
                if x + 1 < maze.width,
                   maze.wall(between: cur, Coord(x: x + 1, y: y)) {
                    let wx = ox + CGFloat(x + 1) * cellSize
                    walls.move (to: CGPoint(x: wx, y: oy + CGFloat(y    ) * cellSize))
                    walls.addLine(to: CGPoint(x: wx, y: oy + CGFloat(y + 1) * cellSize))
                }
                if y + 1 < maze.height,
                   maze.wall(between: cur, Coord(x: x, y: y + 1)) {
                    let wy = oy + CGFloat(y + 1) * cellSize
                    walls.move (to: CGPoint(x: ox + CGFloat(x    ) * cellSize, y: wy))
                    walls.addLine(to: CGPoint(x: ox + CGFloat(x + 1) * cellSize, y: wy))
                }
            }
        }
        context.stroke(walls, with: .color(.white), lineWidth: lineWidth)
    }
}
