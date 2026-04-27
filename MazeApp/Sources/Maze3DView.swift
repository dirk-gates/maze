// Maze3DView -- RealityKit-backed 3D rendering of a finished Maze.
// Phase 5 scaffold: walls extruded as boxes, a floor plane, default
// lighting, and an overhead camera so we can confirm the geometry
// maps correctly before dropping the camera to eye-height for
// first-person navigation.
//
// World coordinates:
//   +X right, +Y up, +Z forward (into the screen)
//   maze grid x → world x; maze grid y → world z
//   one cell = `cellSize` world units; walls are `wallThickness`
//   thick. Floor sits at y=0; walls extrude up to `wallHeight`.
//
// Presented full-screen from ControlsView. Dismiss via the X
// button in the top-left.

import MazeKit
import RealityKit
import SwiftUI

struct Maze3DView: View {
    let maze: Maze
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                buildScene(content)
            }
            .ignoresSafeArea()
            // Sky color depends on scheme so it doesn't flash white
            // in dark mode while RealityKit is loading.
            .background(scheme == .dark ? Color.black : Color(white: 0.85))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .padding()
            }
            .accessibilityLabel("Close 3D view")
        }
    }

    // ---------- world geometry constants ----------

    /// One maze cell in world units. Picked so wallHeight and a
    /// future eye-height (~1.7) read at a sensible scale.
    private let cellSize     : Float = 1.0
    private let wallHeight   : Float = 2.0
    private let wallThickness: Float = 0.18

    @MainActor
    private func buildScene(_ content: any RealityViewContentProtocol) {
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize

        // ---------- floor ----------
        let floorMaterial = SimpleMaterial(
            color: .init(white: 0.55, alpha: 1.0),
            roughness: 0.95,
            isMetallic: false
        )
        let floor = ModelEntity(
            mesh: .generatePlane(width: mazeW, depth: mazeH),
            materials: [floorMaterial]
        )
        floor.position = SIMD3(mazeW / 2, 0, mazeH / 2)
        content.add(floor)

        // ---------- walls (single batched mesh later; per-wall now) ----------
        let wallMaterial = SimpleMaterial(
            color: hedgeColor,
            roughness: 0.85,
            isMetallic: false
        )

        let wallRoot = Entity()
        wallRoot.name = "walls"
        content.add(wallRoot)

        for (cx, cz, wx, wz) in wallSlots() {
            let mesh = MeshResource.generateBox(
                size: SIMD3(wx, wallHeight, wz)
            )
            let entity = ModelEntity(mesh: mesh, materials: [wallMaterial])
            entity.position = SIMD3(cx, wallHeight / 2, cz)
            wallRoot.addChild(entity)
        }

        // ---------- entrance / exit markers ----------
        // Bright pads at the entrance (top edge) and exit (bottom
        // edge) cells so the player can see where to start / aim for.
        let entranceMat = SimpleMaterial(color: .systemBlue, isMetallic: false)
        let exitMat     = SimpleMaterial(color: .systemGreen, isMetallic: false)
        let pad: Float  = cellSize * 0.85
        let padHeight   : Float = 0.02

        if maze.entrance.x >= 0, maze.entrance.x < maze.width {
            let pos = SIMD3(
                Float(maze.entrance.x) * cellSize + cellSize / 2,
                padHeight / 2 + 0.001,
                cellSize / 2
            )
            let m = ModelEntity(mesh: .generateBox(size: SIMD3(pad, padHeight, pad)),
                                materials: [entranceMat])
            m.position = pos
            content.add(m)
        }
        if maze.exit.x >= 0, maze.exit.x < maze.width {
            let pos = SIMD3(
                Float(maze.exit.x) * cellSize + cellSize / 2,
                padHeight / 2 + 0.001,
                mazeH - cellSize / 2
            )
            let m = ModelEntity(mesh: .generateBox(size: SIMD3(pad, padHeight, pad)),
                                materials: [exitMat])
            m.position = pos
            content.add(m)
        }

        // ---------- camera ----------
        // Overhead-tilted view for now -- gets us a clear picture
        // of the maze. First-person camera comes in the next slice.
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        let span    = max(mazeW, mazeH)
        let camY    = span * 1.4
        let camZ    = mazeH + span * 0.9
        camera.position = SIMD3(mazeW / 2, camY, camZ)
        camera.look(at: SIMD3(mazeW / 2, 0, mazeH / 2),
                    from: camera.position,
                    relativeTo: nil)
        content.add(camera)

        // ---------- lighting ----------
        // RealityView's default lighting is fine for a first cut;
        // adding a directional light to soften shadows on the walls.
        let sun = DirectionalLight()
        sun.light.intensity = 3500
        sun.light.color     = .white
        sun.shadow          = DirectionalLightComponent.Shadow(
            maximumDistance: max(50, span * 1.5),
            depthBias      : 5
        )
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
                        * simd_quatf(angle:  .pi / 6, axis: [0, 1, 0])
        sun.position    = SIMD3(mazeW / 2, span * 1.5, mazeH / 2)
        content.add(sun)
    }

    /// Yields one tuple per wall slot to render: (centerX, centerZ,
    /// width, depth). Borders + interior walls combined.
    private func wallSlots() -> [(Float, Float, Float, Float)] {
        var slots: [(Float, Float, Float, Float)] = []
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize

        // Top edge (z = 0): one wall per cell except the entrance.
        for x in 0..<maze.width where x != maze.entrance.x {
            slots.append((
                Float(x) * cellSize + cellSize / 2,
                0,
                cellSize,
                wallThickness
            ))
        }
        // Bottom edge (z = mazeH): one wall per cell except the exit.
        for x in 0..<maze.width where x != maze.exit.x {
            slots.append((
                Float(x) * cellSize + cellSize / 2,
                mazeH,
                cellSize,
                wallThickness
            ))
        }
        // Left and right edges -- one wall per row.
        for y in 0..<maze.height {
            slots.append((0,
                          Float(y) * cellSize + cellSize / 2,
                          wallThickness,
                          cellSize))
            slots.append((mazeW,
                          Float(y) * cellSize + cellSize / 2,
                          wallThickness,
                          cellSize))
        }
        // Interior walls -- one north-side per cell pair, one west-
        // side per cell pair, only if the maze has a wall there.
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width {
                    let east = Coord(x: x + 1, y: y)
                    if maze.wall(between: here, east) {
                        slots.append((
                            Float(x + 1) * cellSize,
                            Float(y) * cellSize + cellSize / 2,
                            wallThickness,
                            cellSize
                        ))
                    }
                }
                if y + 1 < maze.height {
                    let south = Coord(x: x, y: y + 1)
                    if maze.wall(between: here, south) {
                        slots.append((
                            Float(x) * cellSize + cellSize / 2,
                            Float(y + 1) * cellSize,
                            cellSize,
                            wallThickness
                        ))
                    }
                }
            }
        }
        return slots
    }

    /// Hedge green. Switching to a textured material will come in
    /// the themes slice (5c).
    private var hedgeColor: SystemColor {
        #if os(iOS)
        return UIColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #elseif os(macOS)
        return NSColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #else
        return .green
        #endif
    }
}

#if os(iOS)
private typealias SystemColor = UIColor
#elseif os(macOS)
private typealias SystemColor = NSColor
#else
private typealias SystemColor = Color
#endif
