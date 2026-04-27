// Maze3DView -- RealityKit-backed 3D rendering of a finished Maze.
// Phase 5b: first-person camera at eye height with iOS twin-stick
// controls (left = move, right = look) and axis-separated wall
// collision. Reaching the exit cell flashes a "you escaped"
// overlay. macOS keeps an overhead camera until WASD/mouselook
// lands in a follow-up slice.
//
// World coordinates:
//   +X right, +Y up, +Z forward (into the screen, away from the
//   maze entrance which sits at z=0).
//   maze grid x → world x; maze grid y → world z. One cell =
//   `cellSize` world units; walls `wallThickness` thick by
//   `wallHeight` tall. Floor at y=0; player eye at `eyeHeight`.

import MazeKit
import RealityKit
import SwiftUI

// MARK: - World constants

private let cellSize     : Float = 1.0
private let wallHeight   : Float = 2.0
private let wallThickness: Float = 0.18
private let eyeHeight    : Float = 1.55

// MARK: - Collision

/// Axis-aligned wall rectangle in the maze's XZ plane.
private struct WallAABB {
    let minX: Float, maxX: Float
    let minZ: Float, maxZ: Float
}

// MARK: - Player

/// Live first-person state. Bound to RealityView's per-frame
/// scene update so movement / look input applied this frame
/// shows up next frame. Inputs are SIMD2<Float> in -1...1 set
/// by the joystick gestures.
@MainActor
@Observable
private final class PlayerState {
    var position : SIMD3<Float>     // .y already includes altitudeOffset
    var yaw      : Float
    var pitch    : Float = 0
    var moveInput: SIMD2<Float> = .zero
    var won      : Bool         = false

    /// Current camera height ABOVE eye-height. 0 = walking on the
    /// floor; positive = hovering. The camera Y is always
    /// `eyeHeight + altitudeOffset`.
    var altitudeOffset: Float = 0
    /// Lerp target for `altitudeOffset`; tick() interpolates the
    /// current value toward it so altitude changes feel smooth.
    var targetAltitude: Float = 0

    /// True when we're high enough to be over the top of the
    /// hedges -- collision is disabled in this state so the player
    /// can fly across the maze without being walled in.
    var isFlying: Bool { altitudeOffset > flyClearance }

    let maxAltitude  : Float
    private let flyClearance: Float = wallHeight - eyeHeight + 0.1

    private let walls       : [WallAABB]
    private let exitCellX   : Int
    private let exitCellZ   : Int
    private let playerRadius: Float = 0.22
    private let moveSpeed   : Float = 2.6
    private let altitudeRate: Float = 4.0   // 1/seconds: ~0.25 s to converge

    init(start: SIMD3<Float>, yaw: Float,
         walls: [WallAABB], exitCellX: Int, exitCellZ: Int,
         maxAltitude: Float)
    {
        self.position    = start
        self.yaw         = yaw
        self.walls       = walls
        self.exitCellX   = exitCellX
        self.exitCellZ   = exitCellZ
        self.maxAltitude = maxAltitude
    }

    func applyLookDelta(_ delta: CGSize) {
        let sens: Float = 0.005
        yaw   -= Float(delta.width)  * sens
        pitch -= Float(delta.height) * sens
        pitch = max(-1.4, min(1.4, pitch))
    }

    /// Step the altitude target up / down. Caller usually calls
    /// these from button taps; the actual altitude lerps toward
    /// the target across multiple ticks.
    func raiseAltitude(by step: Float) {
        targetAltitude = min(maxAltitude, targetAltitude + step)
    }
    func lowerAltitude(by step: Float) {
        targetAltitude = max(0, targetAltitude - step)
    }

    /// Apply one frame of movement + altitude at `dt` seconds.
    func tick(dt: Float) {
        guard !won else { return }

        // Smooth altitude lerp toward the target the buttons set.
        let beforeFlying = isFlying
        let dy = targetAltitude - altitudeOffset
        altitudeOffset += dy * min(1, dt * altitudeRate)

        let f = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let r = SIMD3<Float>( cos(yaw), 0, -sin(yaw))
        let dxz = (r * moveInput.x + f * moveInput.y) * moveSpeed * dt

        var p = position
        if isFlying {
            // Hover only -- the joystick is ignored above the hedge.
            // You go up, look around, come back down, and walk.
            // No horizontal drift.
        } else {
            // On (or near) the ground: axis-separated collision.
            let nx = SIMD3(p.x + dxz.x, eyeHeight, p.z)
            if !collides(at: nx) { p.x = nx.x }
            let nz = SIMD3(p.x, eyeHeight, p.z + dxz.z)
            if !collides(at: nz) { p.z = nz.z }
        }
        p.y = eyeHeight + altitudeOffset

        // Landing: if we just dropped below fly clearance and our
        // XZ position is inside a wall, snap to the center of the
        // current cell so collision doesn't trap us.
        if beforeFlying && !isFlying {
            let test = SIMD3(p.x, eyeHeight, p.z)
            if collides(at: test) {
                let cx = (floor(p.x / cellSize) + 0.5) * cellSize
                let cz = (floor(p.z / cellSize) + 0.5) * cellSize
                p.x = cx
                p.z = cz
            }
        }
        position = p

        // Win condition: stand on the exit cell while NOT flying.
        if !isFlying {
            let cx = Int(position.x / cellSize)
            let cz = Int(position.z / cellSize)
            if cx == exitCellX && cz == exitCellZ {
                won = true
            }
        }
    }

    private func collides(at p: SIMD3<Float>) -> Bool {
        let r = playerRadius
        for w in walls {
            let cx = max(w.minX, min(p.x, w.maxX))
            let cz = max(w.minZ, min(p.z, w.maxZ))
            let dx = p.x - cx
            let dz = p.z - cz
            if dx * dx + dz * dz < r * r { return true }
        }
        return false
    }
}

// MARK: - Virtual joystick

/// Floating thumbpad. Drag inside (or anywhere over) it; the
/// knob clamps to the radius and writes a normalized -1...1
/// vector to `value`. Releasing recenters.
private struct VirtualJoystick: View {
    @Binding var value: SIMD2<Float>
    let radius: CGFloat
    let label: String

    @GestureState private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.35),
                                         lineWidth: 1))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(.white.opacity(0.65))
                .frame(width: radius * 0.7, height: radius * 0.7)
                .offset(x: CGFloat(value.x) * radius,
                        y: CGFloat(-value.y) * radius)   // visual: up = forward
                .allowsHitTesting(false)
        }
        .accessibilityLabel(label)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($drag) { v, state, _ in state = v.translation }
                .onChanged { v in
                    let dx = v.translation.width
                    let dy = v.translation.height
                    let mag = sqrt(dx * dx + dy * dy)
                    let scale = min(mag, radius) / max(radius, 1)
                    if mag > 0 {
                        value = SIMD2(
                            Float(dx / mag) * Float(scale),
                            Float(-dy / mag) * Float(scale)
                        )
                    } else {
                        value = .zero
                    }
                }
                .onEnded { _ in value = .zero }
        )
    }
}

// MARK: - Main view

struct Maze3DView: View {
    let maze: Maze
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    // Built once on view appear.
    @State private var player: PlayerState?
    @State private var walls : [WallAABB] = []
    @State private var cameraEntity   = PerspectiveCamera()
    @State private var solutionEntity = Entity()
    @State private var showingSolution = false

    /// Cumulative drag translation last seen during a look gesture
    /// -- used to derive a per-frame delta. SwiftUI's DragGesture
    /// reports cumulative translation, so the difference between
    /// successive callbacks is the actual finger motion since
    /// last frame.
    @State private var lookAnchor: CGSize = .zero

    private func applyLook(translation: CGSize) {
        let delta = CGSize(
            width : translation.width  - lookAnchor.width,
            height: translation.height - lookAnchor.height
        )
        lookAnchor = translation
        // Look gesture works at every altitude -- on the ground
        // and while hovering you can still pan to look around.
        player?.applyLookDelta(delta)
    }

    var body: some View {
        ZStack {
            RealityView { content in
                buildScene(content)
            } update: { content in
                _ = content
            }
            .ignoresSafeArea()
            // Sky: prefer the bundled "Sky" photo, fall back to a
            // gradient. RealityKit's scene is transparent where
            // there's no geometry, so the SwiftUI background reads
            // through whenever the player looks above the maze.
            .background(skyBackground)

            #if os(iOS)
            // PUBG-style: full-screen drag-to-look. Sits BELOW the
            // joystick + buttons in the ZStack so thumb taps on
            // those still reach them (SwiftUI hit-tests top-down).
            lookSurface
            controlsOverlay
            #endif

            // Top bar: close on the left, altitude steppers + Solve
            // on the right. Down on the inside, up on the outside,
            // so the pair reads as "the up arrow lifts you higher".
            VStack {
                HStack(spacing: 0) {
                    closeButton
                    Spacer()
                    flyDownButton
                    flyUpButton
                    solveToggle
                }
                Spacer()
            }

            // Win overlay
            if let player, player.won {
                winOverlay
            }
        }
    }

    // MARK: scene build

    @MainActor
    private func buildScene(_ content: any RealityViewContentProtocol) {
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize
        let span  = max(mazeW, mazeH)

        // floor -- sits 1 cm below y=0 so it doesn't share depth
        // with the wall side faces at their base. Co-occupied
        // depth at the bottom edge of every wall was causing a
        // visible flicker stripe along each wall-floor seam --
        // dropping the floor 1cm separates them cleanly.
        let floor = ModelEntity(
            mesh: .generatePlane(width: mazeW, depth: mazeH),
            materials: [floorMaterial()]
        )
        floor.position = SIMD3(mazeW / 2, -0.01, mazeH / 2)
        content.add(floor)

        // walls -- procedural leaf-noise hedge texture
        let wallMat = hedgeMaterial()
        let wallRoot = Entity()
        wallRoot.name = "walls"
        content.add(wallRoot)

        var aabbs: [WallAABB] = []
        let (slots, corners) = wallSlotsAndCorners()
        for (cx, cz, wx, wz) in slots {
            let mesh   = MeshResource.generateBox(size: SIMD3(wx, wallHeight, wz))
            let entity = ModelEntity(mesh: mesh, materials: [wallMat])
            entity.position = SIMD3(cx, wallHeight / 2, cz)
            wallRoot.addChild(entity)
            aabbs.append(WallAABB(
                minX: cx - wx / 2, maxX: cx + wx / 2,
                minZ: cz - wz / 2, maxZ: cz + wz / 2
            ))
        }

        // Corner pillars only at TRUE corners. Use a custom mesh
        // with UVs scaled to wallT / cellSize (~0.22) on the side
        // faces so the pillar shows just a *slice* of the hedge
        // texture at the same density as the surrounding wall
        // slabs. With the seamless tiling hedge texture, the slice
        // reads as a continuation of the wall instead of a
        // squashed full-texture stripe.
        let pillarUVScale = wallThickness / cellSize
        let cornerMesh = Self.makePillarMesh(
            thickness: wallThickness,
            height   : wallHeight,
            uvScale  : pillarUVScale
        )
        for (cx, cz) in corners {
            let pillar = ModelEntity(mesh: cornerMesh, materials: [wallMat])
            pillar.position = SIMD3(cx, 0, cz)
            wallRoot.addChild(pillar)
            aabbs.append(WallAABB(
                minX: cx - wallThickness / 2, maxX: cx + wallThickness / 2,
                minZ: cz - wallThickness / 2, maxZ: cz + wallThickness / 2
            ))
        }
        walls = aabbs

        // entrance / exit pads
        addPad(into: content,
               x: Float(maze.entrance.x) * cellSize + cellSize / 2,
               z: cellSize / 2,
               color: .systemBlue)
        addPad(into: content,
               x: Float(maze.exit.x) * cellSize + cellSize / 2,
               z: mazeH - cellSize / 2,
               color: .systemGreen)

        // Solution path -- always built, hidden until the user
        // toggles it on. Built up front so the toggle is instant.
        solutionEntity.name = "solution"
        solutionEntity.isEnabled = showingSolution
        buildSolutionPath(into: solutionEntity)
        content.add(solutionEntity)

        // sun -- warmer, brighter, casts soft shadows down the
        // corridors. Outdoor daylight feel.
        let sun = DirectionalLight()
        sun.light.intensity = 6500
        // Slight golden warmth -- pure white reads as overcast.
        sun.light.color = .init(red: 1.0, green: 0.96, blue: 0.86, alpha: 1.0)
        sun.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: max(50, span * 1.5),
            depthBias      : 6
        )
        sun.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
                        * simd_quatf(angle:  .pi / 6, axis: [0, 1, 0])
        sun.position    = SIMD3(mazeW / 2, span * 1.5, mazeH / 2)
        content.add(sun)

        // Soft fill from the sky to keep shadowed corridors from
        // going pitch black. Cool tone balances the warm sun.
        let fill = DirectionalLight()
        fill.light.intensity = 1800
        fill.light.color = .init(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fill.orientation = simd_quatf(angle: .pi / 4, axis: [1, 0, 0])
        content.add(fill)

        // Clouds drifting overhead -- alpha-blended planes that
        // face down so the player sees them when looking up.
        addClouds(into: content, mazeW: mazeW, mazeH: mazeH, span: span)

        // camera + player
        // 90° is the classic "comfortable wide" FPS FOV -- spacious
        // in narrow corridors but well short of the fish-eye
        // distortion that creeps in past ~100°.
        cameraEntity.camera.fieldOfViewInDegrees = 90

        #if os(iOS)
        // First-person: stand at the entrance cell, face into the maze.
        let startX = Float(maze.entrance.x) * cellSize + cellSize / 2
        let startZ = cellSize / 2
        // Max altitude scales to the maze size -- enough to see
        // the whole layout from above when fully ascended.
        let maxAlt = max(span * 0.9, 8)
        let p = PlayerState(
            start      : SIMD3(startX, eyeHeight, startZ),
            yaw        : .pi,                  // face +Z (toward exit)
            walls      : aabbs,
            exitCellX  : maze.exit.x,
            exitCellZ  : maze.height - 1,
            maxAltitude: maxAlt
        )
        player = p
        cameraEntity.position    = p.position
        cameraEntity.orientation = simd_quatf(angle: p.yaw,
                                              axis : [0, 1, 0])
        #else
        // Overhead-tilted on macOS until WASD/mouselook lands.
        let camY = span * 1.4
        let camZ = mazeH + span * 0.9
        cameraEntity.position = SIMD3(mazeW / 2, camY, camZ)
        cameraEntity.look(at: SIMD3(mazeW / 2, 0, mazeH / 2),
                          from: cameraEntity.position,
                          relativeTo: nil)
        #endif
        content.add(cameraEntity)

        // Per-frame update: drive the camera from PlayerState.
        // Continuous -- altitude lerps toward target inside tick()
        // so we always want the camera to follow the lerp.
        #if os(iOS)
        _ = content.subscribe(to: SceneEvents.Update.self) { event in
            Task { @MainActor in
                guard let player = self.player else { return }
                player.tick(dt: Float(event.deltaTime))
                self.cameraEntity.position = player.position
                let qYaw   = simd_quatf(angle: player.yaw,   axis: [0, 1, 0])
                let qPitch = simd_quatf(angle: player.pitch, axis: [1, 0, 0])
                self.cameraEntity.orientation = qYaw * qPitch
            }
        }
        #endif
    }

    /// Build the solution path as a chain of thin elongated boxes
    /// hovering just above the floor. Uses an unlit material so
    /// the line "glows" -- it ignores scene lighting and reads
    /// brightly even in the shadowed corridors.
    @MainActor
    private func buildSolutionPath(into root: Entity) {
        guard let path = maze.solution, path.count >= 2 else { return }
        let mat = UnlitMaterial(color: .cyan)
        let lineWidth: Float = 0.10
        let lineY    : Float = 0.04

        func center(_ c: Coord) -> SIMD3<Float> {
            SIMD3(
                Float(c.x) * cellSize + cellSize / 2,
                lineY,
                Float(c.y) * cellSize + cellSize / 2
            )
        }

        for i in 0 ..< path.count - 1 {
            let a = center(path[i])
            let b = center(path[i + 1])
            let mid    = (a + b) * 0.5
            let dx     = b.x - a.x
            let dz     = b.z - a.z
            let length = sqrt(dx * dx + dz * dz)
            if length < 0.001 { continue }
            let yaw    = atan2(dx, dz)

            // A box's default depth axis is +Z, so a yaw rotation
            // around Y aligns that depth axis with (dx, 0, dz).
            let mesh = MeshResource.generateBox(
                size: SIMD3(lineWidth, lineWidth, length)
            )
            let seg = ModelEntity(mesh: mesh, materials: [mat])
            seg.position    = mid
            seg.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            root.addChild(seg)

            // Joint pad at the elbow so corners look continuous.
            let elbow = ModelEntity(
                mesh: .generateBox(size: SIMD3(lineWidth, lineWidth, lineWidth)),
                materials: [mat]
            )
            elbow.position = b
            root.addChild(elbow)
        }
    }

    @MainActor
    private func addPad(into content: any RealityViewContentProtocol,
                        x: Float, z: Float, color: SystemColor)
    {
        let mat = SimpleMaterial(color: color, isMetallic: false)
        let pad = ModelEntity(
            mesh: .generateBox(size: SIMD3(cellSize * 0.85, 0.02, cellSize * 0.85)),
            materials: [mat]
        )
        pad.position = SIMD3(x, 0.011, z)
        content.add(pad)
    }

    /// Build a wallT × wallH × wallT pillar with custom UVs that
    /// show only a `uvScale`-wide slice of the bound texture on
    /// each side face. Standard MeshResource.generateBox would map
    /// the full 0..1 texture onto every face -- on the pillar's
    /// 0.18-wide face that squashes the hedge image into a stretched
    /// stripe. Mapping UV.u from 0..uvScale matches the texture
    /// density of the surrounding wall slabs (whose visible faces
    /// span cellSize and so use uvU = 1.0 over cellSize).
    ///
    /// Box origin is at the FOOT (Y=0) and centered in X/Z, so the
    /// caller positions it by setting `entity.position` to the
    /// floor-level grid intersection.
    @MainActor
    static func makePillarMesh(thickness: Float,
                               height   : Float,
                               uvScale  : Float) -> MeshResource
    {
        let h: Float = thickness / 2
        let H: Float = height
        let u: Float = uvScale       // ~0.22 -- u extent on side faces
        let v: Float = 1.0           // full v on side faces (vertical)

        // 24 vertices, 4 per face × 6 faces; order: +X, -X, +Y, -Y, +Z, -Z
        let positions: [SIMD3<Float>] = [
            // +X
            SIMD3( h, 0, -h), SIMD3( h, 0,  h), SIMD3( h, H,  h), SIMD3( h, H, -h),
            // -X
            SIMD3(-h, 0,  h), SIMD3(-h, 0, -h), SIMD3(-h, H, -h), SIMD3(-h, H,  h),
            // +Y (top)
            SIMD3(-h, H, -h), SIMD3( h, H, -h), SIMD3( h, H,  h), SIMD3(-h, H,  h),
            // -Y (bottom)
            SIMD3(-h, 0,  h), SIMD3( h, 0,  h), SIMD3( h, 0, -h), SIMD3(-h, 0, -h),
            // +Z
            SIMD3( h, 0,  h), SIMD3(-h, 0,  h), SIMD3(-h, H,  h), SIMD3( h, H,  h),
            // -Z
            SIMD3(-h, 0, -h), SIMD3( h, 0, -h), SIMD3( h, H, -h), SIMD3(-h, H, -h),
        ]

        let normals: [SIMD3<Float>] = [
            SIMD3( 1, 0, 0), SIMD3( 1, 0, 0), SIMD3( 1, 0, 0), SIMD3( 1, 0, 0),
            SIMD3(-1, 0, 0), SIMD3(-1, 0, 0), SIMD3(-1, 0, 0), SIMD3(-1, 0, 0),
            SIMD3( 0, 1, 0), SIMD3( 0, 1, 0), SIMD3( 0, 1, 0), SIMD3( 0, 1, 0),
            SIMD3( 0,-1, 0), SIMD3( 0,-1, 0), SIMD3( 0,-1, 0), SIMD3( 0,-1, 0),
            SIMD3( 0, 0, 1), SIMD3( 0, 0, 1), SIMD3( 0, 0, 1), SIMD3( 0, 0, 1),
            SIMD3( 0, 0,-1), SIMD3( 0, 0,-1), SIMD3( 0, 0,-1), SIMD3( 0, 0,-1),
        ]

        // Side faces use u × v slice; top/bottom show a u × u slice
        // (small square -- rarely visible at altitude anyway).
        let uvs: [SIMD2<Float>] = [
            // +X
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // -X
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // +Y top
            SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u),
            // -Y bottom
            SIMD2(0, 0), SIMD2(u, 0), SIMD2(u, u), SIMD2(0, u),
            // +Z
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
            // -Z
            SIMD2(0, v), SIMD2(u, v), SIMD2(u, 0), SIMD2(0, 0),
        ]

        var indices: [UInt32] = []
        for face: UInt32 in 0..<6 {
            let b = face * 4
            indices.append(contentsOf: [b, b + 1, b + 2, b, b + 2, b + 3])
        }

        var d = MeshDescriptor(name: "Pillar")
        d.positions          = MeshBuffers.Positions(positions)
        d.normals            = MeshBuffers.Normals(normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives         = .triangles(indices)
        return try! MeshResource.generate(from: [d])
    }

    /// Walls + pillars in one pass.
    ///
    /// A pillar is needed ONLY at intersections where walls along
    /// both axes (X-run and Z-run) converge -- i.e. true L / T / +
    /// junctions. At "continuation" points where two collinear
    /// slabs meet (e.g. two top-edge walls at adjacent cells with
    /// no perpendicular wall between them), the slabs touch each
    /// other directly and no pillar is placed -- otherwise the
    /// pillar's wallT-wide face would render the full hedge
    /// texture squashed into 0.18 units, which reads as a visible
    /// vertical seam in the middle of the wall.
    ///
    /// Each slab is shortened by `wallThickness/2` ONLY at ends
    /// where a pillar is placed; ends that are collinear
    /// continuations stay flush with the grid line so adjacent
    /// slabs meet seam-to-seam.
    private func wallSlotsAndCorners() ->
        (slots: [(Float, Float, Float, Float)], corners: [(Float, Float)])
    {
        struct Run {
            let start: SIMD2<Int>
            let end  : SIMD2<Int>
            let isXRun: Bool   // true = wall length runs along X axis
        }
        var runs    = [Run]()
        var xKeys   = Set<SIMD2<Int>>()
        var zKeys   = Set<SIMD2<Int>>()

        @inline(__always) func addX(_ s: SIMD2<Int>, _ e: SIMD2<Int>) {
            runs.append(Run(start: s, end: e, isXRun: true))
            xKeys.insert(s); xKeys.insert(e)
        }
        @inline(__always) func addZ(_ s: SIMD2<Int>, _ e: SIMD2<Int>) {
            runs.append(Run(start: s, end: e, isXRun: false))
            zKeys.insert(s); zKeys.insert(e)
        }

        // Top edge (X-axis runs at gy=0)
        for x in 0..<maze.width where x != maze.entrance.x {
            addX(SIMD2(x, 0), SIMD2(x + 1, 0))
        }
        // Bottom edge (X-axis runs at gy=maze.height)
        for x in 0..<maze.width where x != maze.exit.x {
            addX(SIMD2(x, maze.height), SIMD2(x + 1, maze.height))
        }
        // Left + right edges (Z-axis runs)
        for y in 0..<maze.height {
            addZ(SIMD2(0,          y), SIMD2(0,          y + 1))
            addZ(SIMD2(maze.width, y), SIMD2(maze.width, y + 1))
        }
        // Interior walls
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width,
                   maze.wall(between: here, Coord(x: x + 1, y: y))
                {
                    addZ(SIMD2(x + 1, y), SIMD2(x + 1, y + 1))
                }
                if y + 1 < maze.height,
                   maze.wall(between: here, Coord(x: x, y: y + 1))
                {
                    addX(SIMD2(x, y + 1), SIMD2(x + 1, y + 1))
                }
            }
        }

        // True corners = both axes converge at this intersection.
        let pillars = xKeys.intersection(zKeys)

        // Build slot tuples with per-end shortening based on
        // whether each end has a pillar.
        var slots = [(Float, Float, Float, Float)]()
        let half  = wallThickness / 2
        for r in runs {
            let startShort = pillars.contains(r.start) ? half : 0
            let endShort   = pillars.contains(r.end)   ? half : 0
            if r.isXRun {
                let gxA = Float(r.start.x) * cellSize + startShort
                let gxB = Float(r.end.x)   * cellSize - endShort
                let cz  = Float(r.start.y) * cellSize
                slots.append(((gxA + gxB) / 2, cz, gxB - gxA, wallThickness))
            } else {
                let gzA = Float(r.start.y) * cellSize + startShort
                let gzB = Float(r.end.y)   * cellSize - endShort
                let cx  = Float(r.start.x) * cellSize
                slots.append((cx, (gzA + gzB) / 2, wallThickness, gzB - gzA))
            }
        }

        let corners = pillars.map {
            (Float($0.x) * cellSize, Float($0.y) * cellSize)
        }
        return (slots, corners)
    }

    private func wallSlots() -> [(Float, Float, Float, Float)] {
        var slots: [(Float, Float, Float, Float)] = []
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize

        // Legacy path -- kept temporarily for reference; not used.
        let slabLen = cellSize - wallThickness

        for x in 0..<maze.width where x != maze.entrance.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          0, slabLen, wallThickness))
        }
        for x in 0..<maze.width where x != maze.exit.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          mazeH, slabLen, wallThickness))
        }
        for y in 0..<maze.height {
            slots.append((0,     Float(y) * cellSize + cellSize / 2,
                          wallThickness, slabLen))
            slots.append((mazeW, Float(y) * cellSize + cellSize / 2,
                          wallThickness, slabLen))
        }
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width {
                    let east = Coord(x: x + 1, y: y)
                    if maze.wall(between: here, east) {
                        slots.append((Float(x + 1) * cellSize,
                                      Float(y) * cellSize + cellSize / 2,
                                      wallThickness, slabLen))
                    }
                }
                if y + 1 < maze.height {
                    let south = Coord(x: x, y: y + 1)
                    if maze.wall(between: here, south) {
                        slots.append((Float(x) * cellSize + cellSize / 2,
                                      Float(y + 1) * cellSize,
                                      slabLen, wallThickness))
                    }
                }
            }
        }
        return slots
    }

    // MARK: overlays

    private var closeButton: some View {
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

    /// Step the camera up by ~1.25× hedge height. Tap repeatedly
    /// to climb -- starts at ground, max is the maze span (a near-
    /// bird's-eye view). Look-yaw + pitch stay live throughout.
    private var flyUpButton: some View {
        let atMax = (player?.targetAltitude ?? 0) >= (player?.maxAltitude ?? 0) - 0.01
        return Button {
            player?.raiseAltitude(by: flyStep)
        } label: {
            Image(systemName: "arrow.up")
                .font(.largeTitle)
                .padding(10)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
                .padding(.vertical)
        }
        .disabled(atMax)
        .opacity(atMax ? 0.4 : 1.0)
        .accessibilityLabel("Fly up")
    }

    /// Step the camera down. At ground level the button disables.
    private var flyDownButton: some View {
        let atGround = (player?.targetAltitude ?? 0) <= 0.01
        return Button {
            player?.lowerAltitude(by: flyStep)
        } label: {
            Image(systemName: "arrow.down")
                .font(.largeTitle)
                .padding(10)
                .background(Circle().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
                .padding(.vertical)
        }
        .disabled(atGround)
        .opacity(atGround ? 0.4 : 1.0)
        .accessibilityLabel("Fly down")
    }

    /// World units per altitude tap. Tuned so 1 tap = ~1.25× hedge
    /// (puts you just clear of the hedges from the ground).
    private let flyStep: Float = 2.5

    /// Top-right toggle that shows / hides the solution-path
    /// overlay. Tint cyan when active to mirror the line color.
    private var solveToggle: some View {
        Button {
            showingSolution.toggle()
            solutionEntity.isEnabled = showingSolution
        } label: {
            Image(systemName: "scope")
                .font(.largeTitle)
                .padding(10)
                .background(
                    Circle().fill(.black.opacity(0.55))
                )
                .foregroundStyle(showingSolution ? .cyan : .white)
                .padding()
        }
        .accessibilityLabel(showingSolution
                            ? "Hide solution path"
                            : "Show solution path")
    }

    #if os(iOS)
    /// Full-screen transparent layer that captures drag gestures
    /// for camera rotation. PUBG / Call of Duty pattern -- thumb
    /// can land anywhere and dragging rotates the view. Sits
    /// underneath the joystick + buttons in the ZStack so taps on
    /// those reach them first.
    private var lookSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Use the per-frame translation delta, not
                        // the cumulative one -- otherwise far drags
                        // accelerate the rotation. SwiftUI gives us
                        // cumulative `translation`, so we keep a
                        // running anchor.
                        applyLook(translation: value.translation)
                    }
                    .onEnded { _ in
                        lookAnchor = .zero
                    }
            )
    }

    /// Bottom-left movement joystick + reserved space along the
    /// right side for action buttons (Solve, Fly come in 5b/5c).
    /// Each subview owns its hit area so taps land on it instead
    /// of the look surface below.
    private var controlsOverlay: some View {
        let radius: CGFloat = 64
        return VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VirtualJoystick(
                    value: Binding(
                        get: { player?.moveInput ?? .zero },
                        set: { player?.moveInput = $0 }
                    ),
                    radius: radius,
                    label : "Move"
                )
                .padding(.leading, 28)
                .padding(.bottom , 32)

                Spacer()
            }
        }
    }
    #endif

    private var winOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
            Text("You escaped!")
                .font(.title.bold())
                .foregroundStyle(.white)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20))
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.35))
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: theme color

    private var hedgeColor: SystemColor {
        #if os(iOS)
        return UIColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #elseif os(macOS)
        return NSColor(red: 0.20, green: 0.45, blue: 0.20, alpha: 1.0)
        #else
        return .green
        #endif
    }

    private var skyGradientColors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.30, green: 0.42, blue: 0.55),
                Color(red: 0.08, green: 0.14, blue: 0.25)
            ]
        } else {
            return [
                Color(red: 0.65, green: 0.80, blue: 0.95),
                Color(red: 0.25, green: 0.50, blue: 0.85)
            ]
        }
    }

    /// Background view: bundled Sky photo when available, else a
    /// scheme-aware gradient. Wrapping in a ViewBuilder lets us
    /// swap a real photograph in just by adding the asset.
    @ViewBuilder
    private var skyBackground: some View {
        #if os(iOS)
        if let _ = UIImage(named: "Sky") {
            Image("Sky")
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: skyGradientColors,
                           startPoint: .bottom, endPoint: .top)
        }
        #elseif os(macOS)
        if NSImage(named: "Sky") != nil {
            Image("Sky")
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(colors: skyGradientColors,
                           startPoint: .bottom, endPoint: .top)
        }
        #else
        LinearGradient(colors: skyGradientColors,
                       startPoint: .bottom, endPoint: .top)
        #endif
    }

    // MARK: procedural materials

    @MainActor
    private func hedgeMaterial() -> RealityKit.Material {
        let tex = loadAssetTextureWithMipmaps("Hedge")
                 ?? generateLeafTexture()
        if let tex {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: hedgeColor,
                              roughness: 0.85, isMetallic: false)
    }

    @MainActor
    private func floorMaterial() -> RealityKit.Material {
        let tex = loadAssetTextureWithMipmaps("Floor")
                 ?? generateFloorTexture()
        if let tex {
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(texture: .init(tex))
            m.roughness = .init(floatLiteral: 0.95)
            m.metallic  = .init(floatLiteral: 0.00)
            return m
        }
        return SimpleMaterial(color: .init(white: 0.55, alpha: 1.0),
                              roughness: 0.95, isMetallic: false)
    }

    /// Asset-catalog → CGImage → TextureResource with explicit
    /// mipmap generation. The default load(named:) path doesn't
    /// always allocate mipmaps, which makes high-frequency
    /// textures (dense leaves, fine pebbles) sparkle / flicker
    /// when the surface is sampled at distance or steep angles.
    /// Allocating + generating all mip levels lets the GPU pick
    /// the right LOD per pixel.
    @MainActor
    private func loadAssetTextureWithMipmaps(_ name: String) -> TextureResource? {
        #if os(iOS)
        guard let ui = UIImage(named: name), let cg = ui.cgImage else {
            return nil
        }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(
                semantic   : .color,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
        #elseif os(macOS)
        guard let ns = NSImage(named: name),
              let cg = ns.cgImage(
                forProposedRect: nil, context: nil, hints: nil
              )
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

    /// Dark-green base with thousands of small leaf-bright specks.
    /// Reads plausibly leafy at any distance and avoids the
    /// "painted block" look of a flat color.
    @MainActor
    private func generateLeafTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0.07, green: 0.22, blue: 0.08, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<3500 {
            let x = Double.random(in: 0..<Double(size), using: &rng)
            let y = Double.random(in: 0..<Double(size), using: &rng)
            let r = Double.random(in: 0.8..<3.5, using: &rng)
            let bright = Double.random(in: 0.0..<1.0, using: &rng)
            ctx.setFillColor(CGColor(
                red  : 0.05 + bright * 0.18,
                green: 0.22 + bright * 0.45,
                blue : 0.05 + bright * 0.15,
                alpha: 1.0
            ))
            ctx.fillEllipse(in: CGRect(
                x: x - r/2, y: y - r/2, width: r, height: r
            ))
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }

    /// Scatter cloud-billboards above the maze. Each is a flat
    /// plane facing down, alpha-blended over the sky gradient.
    /// Looks great when the player looks up while flying.
    @MainActor
    private func addClouds(into content: any RealityViewContentProtocol,
                           mazeW: Float, mazeH: Float, span: Float)
    {
        // Try to load a bundled "Sky" / cloud asset first; fall
        // back to a procedurally generated puffy white shape.
        let cloudTex = (try? TextureResource.load(named: "Sky"))
                     ?? generateCloudTexture()
        guard let cloudTex else { return }

        var mat = UnlitMaterial()
        mat.color = .init(texture: .init(cloudTex))
        // Treat the texture's alpha channel as transparency so the
        // soft cloud edges blend into the sky.
        mat.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        var rng = SystemRandomNumberGenerator()
        let cloudCount = 24
        for _ in 0..<cloudCount {
            let cw = Float.random(in: 8 ..< 22, using: &rng)
            let cd = cw * Float.random(in: 0.55 ..< 0.85, using: &rng)
            let cx = Float.random(in: -span * 0.6 ..< mazeW + span * 0.6, using: &rng)
            let cz = Float.random(in: -span * 0.6 ..< mazeH + span * 0.6, using: &rng)
            let cy = Float.random(in: 28 ..< 55, using: &rng)
            let cloud = ModelEntity(
                mesh: .generatePlane(width: cw, depth: cd),
                materials: [mat]
            )
            cloud.position = SIMD3(cx, cy, cz)
            // Default plane faces +Y (up). Rotate by π around X so
            // the textured side faces -Y (down) toward the player.
            cloud.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            content.add(cloud)
        }
    }

    /// Procedural cloud texture: stacked soft white radial blobs
    /// on a transparent background. Renders as a puffy shape with
    /// soft edges that blend into the sky.
    @MainActor
    private func generateCloudTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

        let cw = Double(size)
        var rng = SystemRandomNumberGenerator()
        let bumps = 9
        for _ in 0..<bumps {
            let cx = Double.random(in: cw * 0.20 ..< cw * 0.80, using: &rng)
            let cy = Double.random(in: cw * 0.40 ..< cw * 0.60, using: &rng)
            let radius = Double.random(in: cw * 0.14 ..< cw * 0.28, using: &rng)
            guard let gradient = CGGradient(
                colorsSpace: cs,
                colors    : [
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.95),
                    CGColor(red: 1, green: 1, blue: 1, alpha: 0.00)
                ] as CFArray,
                locations : [0, 1]
            ) else { return nil }
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                endCenter  : CGPoint(x: cx, y: cy), endRadius: CGFloat(radius),
                options    : []
            )
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }

    /// Warm beige base with darker pebbles -- packed-earth path.
    @MainActor
    private func generateFloorTexture(size: Int = 256) -> TextureResource? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data            : nil,
            width           : size,
            height          : size,
            bitsPerComponent: 8,
            bytesPerRow     : 0,
            space           : cs,
            bitmapInfo      : CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0.55, green: 0.50, blue: 0.40, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2200 {
            let x  = Double.random(in: 0..<Double(size), using: &rng)
            let y  = Double.random(in: 0..<Double(size), using: &rng)
            let r  = Double.random(in: 0.8..<3.0, using: &rng)
            let dn = Double.random(in: -0.15..<0.15, using: &rng)
            ctx.setFillColor(CGColor(
                red  : 0.55 + dn,
                green: 0.50 + dn,
                blue : 0.40 + dn,
                alpha: 1.0
            ))
            ctx.fillEllipse(in: CGRect(
                x: x - r/2, y: y - r/2, width: r, height: r
            ))
        }

        guard let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(
            image  : cg,
            options: TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
        )
    }
}

#if os(iOS)
private typealias SystemColor = UIColor
#elseif os(macOS)
private typealias SystemColor = NSColor
#else
private typealias SystemColor = Color
#endif
