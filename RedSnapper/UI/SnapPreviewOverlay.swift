import AppKit

/// The translucent rectangle shown while dragging a window over a snap zone.
final class SnapPreviewOverlay {
    private let panel: NSPanel
    private(set) var isVisible = false

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 3
        view.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
        tint.autoresizingMask = [.width, .height]
        view.addSubview(tint)

        panel.contentView = view
    }

    /// Shows (or moves) the preview to `frame`, in AppKit coordinates.
    func show(_ frame: CGRect) {
        let inset = frame.insetBy(dx: 4, dy: 4)
        if isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().setFrame(inset, display: true)
            }
        } else {
            panel.setFrame(inset, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
            isVisible = true
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        })
    }
}
