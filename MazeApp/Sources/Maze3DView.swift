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
    var position : SIMD3<Float>
    var yaw      : Float            // radians, around +Y; 0 = facing -Z
    var moveInput: SIMD2<Float> = .zero  // x = strafe, y = forward
    var lookInput: SIMD2<Float> = .zero  // x = yaw rate, y = pitch (unused yet)
    var won      : Bool         = false

    private let walls       : [WallAABB]
    private let exitCellX   : Int
    private let exitCellZ   : Int
    private let playerRadius: Float = 0.22
    private let moveSpeed   : Float = 2.6     // world units / sec
    private let lookSpeed   : Float = 2.2     // radians / sec

    init(start: SIMD3<Float>, yaw: Float,
         walls: [WallAABB], exitCellX: Int, exitCellZ: Int)
    {
        self.position  = start
        self.yaw       = yaw
        self.walls     = walls
        self.exitCellX = exitCellX
        self.exitCellZ = exitCellZ
    }

    /// Apply one frame of input at `dt` seconds.
    func tick(dt: Float) {
        guard !won else { return }
        // Yaw first so movement feels responsive to look changes.
        yaw -= lookInput.x * lookSpeed * dt

        let f = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let r = SIMD3<Float>( cos(yaw), 0, -sin(yaw))
        let dxz = (r * moveInput.x + f * moveInput.y) * moveSpeed * dt

        // Axis-separated move so we slide along walls instead of
        // sticking when a diagonal would clip a corner.
        var p = position
        let nx = SIMD3(p.x + dxz.x, eyeHeight, p.z)
        if !collides(at: nx) { p.x = nx.x }
        let nz = SIMD3(p.x, eyeHeight, p.z + dxz.z)
        if !collides(at: nz) { p.z = nz.z }
        position = SIMD3(p.x, eyeHeight, p.z)

        // Win condition: stand on the exit cell.
        let cx = Int(position.x / cellSize)
        let cz = Int(position.z / cellSize)
        if cx == exitCellX && cz == exitCellZ {
            won = true
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
    @State private var cameraEntity = PerspectiveCamera()

    var body: some View {
        ZStack {
            RealityView { content in
                buildScene(content)
            } update: { content in
                // RealityView's update closure fires when SwiftUI
                // diffs the view -- we use the SceneEvents.Update
                // subscription set up in build for the per-frame
                // tick instead.
                _ = content
            }
            .ignoresSafeArea()
            .background(scheme == .dark ? Color.black : Color(white: 0.85))

            // Joystick overlays (iOS only -- macOS keeps the
            // overhead camera for now)
            #if os(iOS)
            joystickOverlay
            #endif

            // Top-left close button
            VStack(alignment: .leading) {
                HStack {
                    closeButton
                    Spacer()
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

        // floor
        let floor = ModelEntity(
            mesh: .generatePlane(width: mazeW, depth: mazeH),
            materials: [SimpleMaterial(color: .init(white: 0.55, alpha: 1.0),
                                       roughness: 0.95, isMetallic: false)]
        )
        floor.position = SIMD3(mazeW / 2, 0, mazeH / 2)
        content.add(floor)

        // walls
        let wallMat = SimpleMaterial(color: hedgeColor,
                                     roughness: 0.85, isMetallic: false)
        let wallRoot = Entity()
        wallRoot.name = "walls"
        content.add(wallRoot)

        var aabbs: [WallAABB] = []
        for (cx, cz, wx, wz) in wallSlots() {
            let mesh   = MeshResource.generateBox(size: SIMD3(wx, wallHeight, wz))
            let entity = ModelEntity(mesh: mesh, materials: [wallMat])
            entity.position = SIMD3(cx, wallHeight / 2, cz)
            wallRoot.addChild(entity)
            aabbs.append(WallAABB(
                minX: cx - wx / 2, maxX: cx + wx / 2,
                minZ: cz - wz / 2, maxZ: cz + wz / 2
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

        // sun
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

        // camera + player
        cameraEntity.camera.fieldOfViewInDegrees = 70

        #if os(iOS)
        // First-person: stand at the entrance cell, face into the maze.
        let startX = Float(maze.entrance.x) * cellSize + cellSize / 2
        let startZ = cellSize / 2
        let p = PlayerState(
            start: SIMD3(startX, eyeHeight, startZ),
            yaw  : .pi,                         // face +Z (toward exit)
            walls: aabbs,
            exitCellX: maze.exit.x,
            exitCellZ: maze.height - 1
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
        #if os(iOS)
        _ = content.subscribe(to: SceneEvents.Update.self) { event in
            Task { @MainActor in
                guard let player = self.player else { return }
                player.tick(dt: Float(event.deltaTime))
                self.cameraEntity.position = player.position
                self.cameraEntity.orientation = simd_quatf(
                    angle: player.yaw, axis: [0, 1, 0]
                )
            }
        }
        #endif
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

    private func wallSlots() -> [(Float, Float, Float, Float)] {
        var slots: [(Float, Float, Float, Float)] = []
        let mazeW = Float(maze.width)  * cellSize
        let mazeH = Float(maze.height) * cellSize

        for x in 0..<maze.width where x != maze.entrance.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          0, cellSize, wallThickness))
        }
        for x in 0..<maze.width where x != maze.exit.x {
            slots.append((Float(x) * cellSize + cellSize / 2,
                          mazeH, cellSize, wallThickness))
        }
        for y in 0..<maze.height {
            slots.append((0,     Float(y) * cellSize + cellSize / 2,
                          wallThickness, cellSize))
            slots.append((mazeW, Float(y) * cellSize + cellSize / 2,
                          wallThickness, cellSize))
        }
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let here = Coord(x: x, y: y)
                if x + 1 < maze.width {
                    let east = Coord(x: x + 1, y: y)
                    if maze.wall(between: here, east) {
                        slots.append((Float(x + 1) * cellSize,
                                      Float(y) * cellSize + cellSize / 2,
                                      wallThickness, cellSize))
                    }
                }
                if y + 1 < maze.height {
                    let south = Coord(x: x, y: y + 1)
                    if maze.wall(between: here, south) {
                        slots.append((Float(x) * cellSize + cellSize / 2,
                                      Float(y + 1) * cellSize,
                                      cellSize, wallThickness))
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

    #if os(iOS)
    private var joystickOverlay: some View {
        // ZStack-positioned thumbpads at the bottom corners.
        // Sized for thumb reach without dominating the screen.
        let radius: CGFloat = 64
        return VStack {
            Spacer()
            HStack {
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

                VirtualJoystick(
                    value: Binding(
                        get: { player?.lookInput ?? .zero },
                        set: { player?.lookInput = $0 }
                    ),
                    radius: radius,
                    label : "Look"
                )
                .padding(.trailing, 28)
                .padding(.bottom  , 32)
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
}

#if os(iOS)
private typealias SystemColor = UIColor
#elseif os(macOS)
private typealias SystemColor = NSColor
#else
private typealias SystemColor = Color
#endif
