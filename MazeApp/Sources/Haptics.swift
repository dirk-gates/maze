// Haptics -- iOS-only haptic feedback wrapper. Methods are no-ops
// on macOS; call sites stay clean of #if os().
//
// Calls are rate-limited so a 600-cell maze generation doesn't
// produce 600 buzzes -- one tap every N events plus a single
// success pulse on solve completion.

import Foundation

#if os(iOS)
import UIKit
#endif

@MainActor
final class Haptics {
    static let shared = Haptics()

    /// Minimum interval between successive carving impacts.
    private let minInterval: TimeInterval = 0.040
    private var lastImpactAt: Date = .distantPast

    /// Soft tap during cell carving. No-ops on macOS.
    func carveTick() {
        #if os(iOS)
        let now = Date()
        guard now.timeIntervalSince(lastImpactAt) >= minInterval else { return }
        lastImpactAt = now
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.35)
        #endif
    }

    /// Stronger tap on milestone events (e.g. attempt boundary).
    func milestone() {
        #if os(iOS)
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
        #endif
    }

    /// Success notification on solve completion.
    func success() {
        #if os(iOS)
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
        #endif
    }
}
