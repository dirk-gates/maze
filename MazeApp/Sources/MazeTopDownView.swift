// MazeTopDownView -- 3D top-down render of the maze that replaces
// the 2D Canvas on the first page. Phase 5d slice 1: solid hedge
// initially, then individual cell + wall entities hide as the
// generator emits .carved / .opened / .gates events. Reads as
// "trimmers carving paths out of a hedge block from above".
//
// Coordinate system + scale match Maze3DView so the eventual
// "descend into the maze" transition can happen by lerping a
// shared camera between the two views.
//
// Cells: 1 hedge block per (x, y), full cellSize × wallH × cellSize.
//        Hidden when in viewModel.carvedCells.
// Walls: 1 thin slab per possible internal wall slot; visible only
//        when BOTH adjacent cells are carved AND the wall isn't
//        in viewModel.openWalls.
// Border walls: top / bottom / left / right; visible when the
//        adjacent cell is carved AND it isn't the entrance / exit
//        gate cell.

import MazeKit
import RealityKit
import SwiftUI

struct MazeTopDownView: View {
    @Bindable var viewModel: MazeViewModel

    private let cellSize     : Float = 1.0
    private let wallHeight   : Float = 2.0
    private let wallThickness: Float = 0.18

    // Entity caches keyed by their grid identity. We rebuild the
    // whole scene whenever the maze dimensions change; visibility
    // is updated every frame from the view model.
    @State private var cellEntities       : [Coord: Entity] = [:]
    @State private var internalWallNS     : [Coord: Entity] = [:]   // wall north of cell
    @State private var internalWallEW     : [Coord: Entity] = [:]   // wall east of cell
    @State private var topBorderEntities  : [Int: Entity]   = [:]
    @State private var botBorderEntities  : [Int: Entity]   = [:]
    @State private var leftBorderEntities : [Int: Entity]   = [:]
    @State private var rightBorderEntities: [Int: Entity]   = [:]
    @State private var builtFor: SIMD2<Int> = SIMD2(0, 0)

    var body: some View {
        RealityView { content in
            build(content)
        } update: { _ in
            updateVisibility()
        }
        .background(skyBackground)
    }

    // MARK: scene build

    @MainActor
    private func build(_ content: any RealityViewContentProtocol) {
        let w = viewModel.width
        let h = viewModel.height
        builtFor = SIMD2(w, h)
        let mazeW = Float(w) * cellSize
        let mazeH = Float(h) * cellSize
        let span  = max(mazeW, mazeH)

        let hedgeMat = makeHedgeMaterial()
        let floorMat = makeFloorMaterial()

        // floor
        let floor = ModelEntity(
            mesh: .generatePlane(width: mazeW, depth: mazeH),
            materials: [floorMat]
        )
        floor.position = SIMD3(mazeW / 2, -0.01, mazeH / 2)
        content.add(floor)

        // cells -- full hedge blocks
        cellEntities.removeAll(keepingCapacity: true)
        for y in 0..<h {
            for x in 0..<w {
                let block = ModelEntity(
                    mesh     : .generateBox(size: SIMD3(cellSize, wallHeight, cellSize)),
                    materials: [hedgeMat]
                )
                block.position = SIMD3(
                    Float(x) * cellSize + cellSize / 2,
                    wallHeight / 2,
                    Float(y) * cellSize + cellSize / 2
                )
                content.add(block)
                cellEntities[Coord(x: x, y: y)] = block
            }
        }

        // internal walls: NS = horizontal slab between row y-1 and y;
        // EW = vertical slab between col x-1 and x.
        // Indexed by the cell on the BOTTOM (NS) or RIGHT (EW) of the
        // wall so the keys are unique per slab.
        internalWallNS.removeAll(keepingCapacity: true)
        internalWallEW.removeAll(keepingCapacity: true)
        for y in 1..<h {
            for x in 0..<w {
                let slab = ModelEntity(
                    mesh     : .generateBox(size: SIMD3(cellSize, wallHeight, wallThickness)),
                    materials: [hedgeMat]
                )
                slab.position = SIMD3(
                    Float(x) * cellSize + cellSize / 2,
                    wallHeight / 2,
                    Float(y) * cellSize
                )
                slab.isEnabled = false   // visible only when both cells carved and wall closed
                content.add(slab)
                internalWallNS[Coord(x: x, y: y)] = slab
            }
        }
        for y in 0..<h {
            for x in 1..<w {
                let slab = ModelEntity(
                    mesh     : .generateBox(size: SIMD3(wallThickness, wallHeight, cellSize)),
                    materials: [hedgeMat]
                )
                slab.position = SIMD3(
                    Float(x) * cellSize,
                    wallHeight / 2,
                    Float(y) * cellSize + cellSize / 2
                )
                slab.isEnabled = false
                content.add(slab)
                internalWallEW[Coord(x: x, y: y)] = slab
            }
        }

        // border walls
        topBorderEntities  .removeAll(keepingCapacity: true)
        botBorderEntities  .removeAll(keepingCapacity: true)
        leftBorderEntities .removeAll(keepingCapacity: true)
        rightBorderEntities.removeAll(keepingCapacity: true)

        for x in 0..<w {
            let top = ModelEntity(
                mesh     : .generateBox(size: SIMD3(cellSize, wallHeight, wallThickness)),
                materials: [hedgeMat]
            )
            top.position = SIMD3(Float(x) * cellSize + cellSize / 2,
                                 wallHeight / 2,
                                 0)
            top.isEnabled = false
            content.add(top)
            topBorderEntities[x] = top

            let bot = ModelEntity(
                mesh     : .generateBox(size: SIMD3(cellSize, wallHeight, wallThickness)),
                materials: [hedgeMat]
            )
            bot.position = SIMD3(Float(x) * cellSize + cellSize / 2,
                                 wallHeight / 2,
                                 mazeH)
            bot.isEnabled = false
            content.add(bot)
            botBorderEntities[x] = bot
        }
        for y in 0..<h {
            let left = ModelEntity(
                mesh     : .generateBox(size: SIMD3(wallThickness, wallHeight, cellSize)),
                materials: [hedgeMat]
            )
            left.position = SIMD3(0,
                                  wallHeight / 2,
                                  Float(y) * cellSize + cellSize / 2)
            left.isEnabled = false
            content.add(left)
            leftBorderEntities[y] = left

            let right = ModelEntity(
                mesh     : .generateBox(size: SIMD3(wallThickness, wallHeight, cellSize)),
                materials: [hedgeMat]
            )
            right.position = SIMD3(mazeW,
                                   wallHeight / 2,
                                   Float(y) * cellSize + cellSize / 2)
            right.isEnabled = false
            content.add(right)
            rightBorderEntities[y] = right
        }

        // sun
        let sun = DirectionalLight()
        sun.light.intensity = 6500
        sun.light.color     = .init(red: 1.0, green: 0.96, blue: 0.86, alpha: 1.0)
        sun.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: max(50, span * 1.5),
            depthBias      : 6
        )
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
                        * simd_quatf(angle:  .pi / 6, axis: [0, 1, 0])
        sun.position = SIMD3(mazeW / 2, span * 1.5, mazeH / 2)
        content.add(sun)

        let fill = DirectionalLight()
        fill.light.intensity = 1800
        fill.light.color = .init(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fill.orientation = simd_quatf(angle: .pi / 4, axis: [1, 0, 0])
        content.add(fill)

        // camera -- extreme bird's-eye, slight forward tilt
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 65
        let from = SIMD3<Float>(mazeW / 2, span * 1.05, mazeH * 0.95 + span * 0.15)
        let to   = SIMD3<Float>(mazeW / 2, 0, mazeH / 2)
        camera.position = from
        camera.look(at: to, from: from, relativeTo: nil)
        content.add(camera)

        // initial visibility
        updateVisibility()
    }

    // MARK: visibility

    @MainActor
    private func updateVisibility() {
        // Rebuild trigger -- if the maze size changed, we need new
        // entities. (Cheap check; full rebuild is delegated to the
        // RealityView make closure, which fires on view identity.)
        if SIMD2(viewModel.width, viewModel.height) != builtFor { return }

        for (coord, entity) in cellEntities {
            entity.isEnabled = !viewModel.carvedCells.contains(coord)
        }
        // Internal walls: visible iff both adjacent cells are
        // carved AND the wall isn't open. NS is between (x, y-1)
        // and (x, y); EW is between (x-1, y) and (x, y).
        for (key, entity) in internalWallNS {
            let a = Coord(x: key.x, y: key.y - 1)
            let b = Coord(x: key.x, y: key.y)
            let bothCarved = viewModel.carvedCells.contains(a)
                          && viewModel.carvedCells.contains(b)
            let isOpen = viewModel.openWalls.contains(MazeKit.Edge(a, b))
            entity.isEnabled = bothCarved && !isOpen
        }
        for (key, entity) in internalWallEW {
            let a = Coord(x: key.x - 1, y: key.y)
            let b = Coord(x: key.x,     y: key.y)
            let bothCarved = viewModel.carvedCells.contains(a)
                          && viewModel.carvedCells.contains(b)
            let isOpen = viewModel.openWalls.contains(MazeKit.Edge(a, b))
            entity.isEnabled = bothCarved && !isOpen
        }
        // Border walls: visible iff adjacent cell is carved and
        // this isn't the gate cell.
        let entranceX = viewModel.entranceGate?.x ?? -1
        let exitX     = viewModel.exitGate?.x     ?? -1
        for (x, entity) in topBorderEntities {
            let cellCarved = viewModel.carvedCells.contains(Coord(x: x, y: 0))
            entity.isEnabled = cellCarved && x != entranceX
        }
        for (x, entity) in botBorderEntities {
            let cellCarved = viewModel.carvedCells.contains(
                Coord(x: x, y: viewModel.height - 1)
            )
            entity.isEnabled = cellCarved && x != exitX
        }
        for (y, entity) in leftBorderEntities {
            let cellCarved = viewModel.carvedCells.contains(Coord(x: 0, y: y))
            entity.isEnabled = cellCarved
        }
        for (y, entity) in rightBorderEntities {
            let cellCarved = viewModel.carvedCells.contains(
                Coord(x: viewModel.width - 1, y: y)
            )
            entity.isEnabled = cellCarved
        }
    }

    // MARK: materials (reuses bundled assets shared with Maze3DView)

    @MainActor
    private func makeHedgeMaterial() -> RealityKit.Material {
        if let tex = loadAssetTextureWithMipmaps("Hedge") {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: .init(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0),
                              roughness: 0.85, isMetallic: false)
    }

    @MainActor
    private func makeFloorMaterial() -> RealityKit.Material {
        if let tex = loadAssetTextureWithMipmaps("Floor") {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: .init(white: 0.55, alpha: 1.0),
                              roughness: 0.95, isMetallic: false)
    }

    @MainActor
    private func loadAssetTextureWithMipmaps(_ name: String) -> TextureResource? {
        #if os(iOS)
        guard let ui = UIImage(named: name), let cg = ui.cgImage else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
        #elseif os(macOS)
        guard let ns = NSImage(named: name),
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
        #else
        return nil
        #endif
    }

    @ViewBuilder
    private var skyBackground: some View {
        #if os(iOS)
        if UIImage(named: "Sky") != nil {
            Image("Sky").resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(red: 0.65, green: 0.80, blue: 0.95),
                         Color(red: 0.25, green: 0.50, blue: 0.85)],
                startPoint: .bottom, endPoint: .top
            )
        }
        #elseif os(macOS)
        if NSImage(named: "Sky") != nil {
            Image("Sky").resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [Color(red: 0.65, green: 0.80, blue: 0.95),
                         Color(red: 0.25, green: 0.50, blue: 0.85)],
                startPoint: .bottom, endPoint: .top
            )
        }
        #else
        Color.gray
        #endif
    }
}
