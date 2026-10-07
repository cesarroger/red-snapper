import AppKit
import SwiftUI

/// A brief, click-through notice near the bottom of the screen with the mouse
/// (e.g. "Restored 5 of 6 windows").
final class HUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ message: String, detail: String? = nil, symbol: String = "fish.fill") {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let view = HStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil); if self?.panel === panel { self?.panel = nil } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
