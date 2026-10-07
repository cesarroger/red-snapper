import SwiftUI
import AppKit
import SnapCore

/// A miniature screen with `zone` highlighted.
struct ZoneIcon: View {
    let zone: SnapZone
    var highlighted = false

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            let screen = Path(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 4)
            ctx.stroke(screen, with: .color(.secondary.opacity(0.6)), lineWidth: 1.2)

            let inner = bounds.insetBy(dx: 3, dy: 3)
            var r = LayoutEngine.frame(for: zone, in: inner, gap: 0,
                                       windowSize: CGSize(width: inner.width * 0.55, height: inner.height * 0.55))
            r.origin.y = bounds.height - r.maxY // LayoutEngine is y-up; Canvas is y-down
            ctx.fill(Path(roundedRect: r, cornerRadius: 2),
                     with: .color(highlighted ? .red : .red.opacity(0.55)))
        }
    }
}

struct SnapPickerView: View {
    let appName: String
    let onPick: (HotKeyAction) -> Void

    private let rows: [[HotKeyAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize],
        [.topLeft, .topRight, .bottomLeft, .bottomRight, .center],
        [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
    ]
    @State private var hovered: HotKeyAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hovered?.displayName ?? appName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row) { action in
                            Button { onPick(action) } label: {
                                ZoneIcon(zone: action.zone ?? .maximize, highlighted: hovered == action)
                                    .frame(width: 44, height: 30)
                                    .padding(3)
                                    .background(RoundedRectangle(cornerRadius: 6)
                                        .fill(hovered == action ? Color.red.opacity(0.12) : .clear))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovered = $0 ? action : (hovered == action ? nil : hovered) }
                            .help(action.displayName)
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 6) {
                footerButton(.previousDisplay, "arrow.left.to.line", "Previous Display")
                footerButton(.nextDisplay, "arrow.right.to.line", "Next Display")
                Spacer()
                footerButton(.restore, "arrow.uturn.backward", "Restore")
            }
        }
        .padding(10)
        .frame(width: 286)
    }

    private func footerButton(_ action: HotKeyAction, _ symbol: String, _ title: String) -> some View {
        Button { onPick(action) } label: {
            Label(title, systemImage: symbol).font(.caption)
        }
        .buttonStyle(.borderless)
        .help(action.displayName)
    }
}

/// Floating, non-activating panel hosting the picker next to the cursor.
final class SnapPickerPanel {
    private final class KeyablePanel: NSPanel {
        var onCancel: () -> Void = {}
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { onCancel() }
        override func resignKey() { super.resignKey(); onCancel() }
    }

    /// RED SNAPPER is never the active app while the picker is up, so without this the first
    /// click on a tile would only focus the panel instead of pressing the button.
    private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var panel: KeyablePanel?
    private var outsideClickMonitor: Any?

    func show(at point: NSPoint, appName: String, onPick: @escaping (HotKeyAction) -> Void) {
        close()
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.close() }

        let root = SnapPickerView(appName: appName) { [weak self] action in
            self?.close()
            onPick(action)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
        let hosting = FirstClickHostingView(rootView: root)
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)

        // Open just below-right of the cursor, kept on the cursor's screen.
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - 20, y: point.y - size.height - 8)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        guard let panel else { return }
        self.panel = nil
        panel.onCancel = {}
        panel.orderOut(nil)
    }
}
