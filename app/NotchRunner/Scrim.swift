import AppKit

/// A full-screen dim behind the island, so the expanded strip reads as the
/// thing to look at rather than one more window competing with everything else.
///
/// Deliberately **click-through**. The whole premise is that Claude is busy and
/// you are not, so the app must never stand between you and your screen: the
/// scrim is a visual cue, not a modal.
final class Scrim {
    /// 40% black.
    static let opacity: CGFloat = 0.4

    private let window: NSWindow
    private var shown = false

    init(level: NSWindow.Level) {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.backgroundColor = .black
        window.alphaValue = 0
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true          // never takes clicks
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(on screen: NSScreen) {
        window.setFrame(screen.frame, display: false)
        if !shown {
            window.orderFrontRegardless()
            shown = true
        }
        fade(to: Self.opacity)
    }

    func hide() {
        guard shown else { return }
        fade(to: 0) { [weak self] in
            self?.window.orderOut(nil)
            self?.shown = false
        }
    }

    /// Matches the island's own transition. Honours Reduce Motion, which the
    /// stylesheet already respects for the island and the glow.
    private func fade(to alpha: CGFloat, then done: (() -> Void)? = nil) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.alphaValue = alpha
            done?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = alpha > 0 ? 0.45 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = alpha
        }, completionHandler: done)
    }
}
