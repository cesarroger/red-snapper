// Renders the README hero image: `swift docs/art/Hero.swift` (writes docs/images/hero.png).
// Drawn in code so it matches the app exactly: same reds, the real app icon, and the
// translucent snap-preview overlay RED SNAPPER shows while dragging.
import SwiftUI
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let snapperRed = Color(red: 1.0, green: 0.23, blue: 0.19)
let deepRed = Color(red: 0.62, green: 0.04, blue: 0.10)
let ink = Color(red: 0.10, green: 0.05, blue: 0.07)
let windowFill = Color(red: 0.14, green: 0.12, blue: 0.15)

// MARK: - Mini macOS window

struct MiniWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 8, height: 8)
                Spacer()
                Text(title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Color.clear.frame(width: 34, height: 1)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Color.white.opacity(0.05))
            content
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(windowFill)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.09)))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 7)
    }
}

struct Bar: View {
    var width: CGFloat
    var color: Color = .white.opacity(0.16)
    var body: some View { Capsule().fill(color).frame(width: width, height: 5) }
}

struct CodeContent: View {
    let rows: [[(CGFloat, Color)]] = [
        [(30, .pink.opacity(0.7)), (60, .white.opacity(0.25))],
        [(14, .clear), (44, .orange.opacity(0.65)), (50, .white.opacity(0.2))],
        [(14, .clear), (70, .cyan.opacity(0.55))],
        [(14, .clear), (28, .pink.opacity(0.7)), (40, .white.opacity(0.2)), (24, .green.opacity(0.55))],
        [(36, .white.opacity(0.2))],
        [(30, .pink.opacity(0.7)), (52, .cyan.opacity(0.55))],
        [(14, .clear), (64, .white.opacity(0.2)), (20, .orange.opacity(0.65))],
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 5) { ForEach(rows[i].indices, id: \.self) { j in Bar(width: rows[i][j].0, color: rows[i][j].1) } }
            }
        }
    }
}

struct MusicContent: View {
    let levels: [CGFloat] = [0.3, 0.55, 0.8, 0.45, 0.95, 0.6, 0.35, 0.7, 0.9, 0.5, 0.25, 0.65, 0.85, 0.4, 0.6, 0.3, 0.75, 0.5]
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [snapperRed, Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 62, height: 62)
                .overlay(Image(systemName: "waveform").font(.system(size: 22, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 6) {
                Bar(width: 90, color: .white.opacity(0.45))
                Bar(width: 56)
                HStack(alignment: .center, spacing: 3) {
                    ForEach(levels.indices, id: \.self) { i in
                        Capsule().fill(i < 8 ? snapperRed.opacity(0.9) : .white.opacity(0.22)).frame(width: 3.5, height: 34 * levels[i])
                    }
                }
                .frame(height: 36)
            }
        }
    }
}

struct ChatContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bubble(110, mine: false)
            bubble(80, mine: true)
            bubble(130, mine: false)
            bubble(60, mine: true)
        }
        .frame(maxWidth: .infinity)
    }
    func bubble(_ w: CGFloat, mine: Bool) -> some View {
        HStack {
            if mine { Spacer() }
            RoundedRectangle(cornerRadius: 9).fill(mine ? snapperRed.opacity(0.85) : .white.opacity(0.13)).frame(width: w, height: 18)
            if !mine { Spacer() }
        }
    }
}

struct NotesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Bar(width: 110, color: .white.opacity(0.5)).frame(height: 7)
            Bar(width: 150); Bar(width: 132); Bar(width: 144)
            HStack(spacing: 6) { Circle().fill(snapperRed).frame(width: 6, height: 6); Bar(width: 100) }
            HStack(spacing: 6) { Circle().fill(snapperRed).frame(width: 6, height: 6); Bar(width: 84) }
        }
    }
}

// MARK: - Desktop scene

struct Screen: View {
    let w: CGFloat = 720, h: CGFloat = 450, bar: CGFloat = 20, gap: CGFloat = 10

    var body: some View {
        let deskH = h - bar
        let cellW = (w - gap * 3) / 2, cellH = (deskH - gap * 3) / 2
        ZStack(alignment: .topLeading) {
            // Wallpaper
            LinearGradient(colors: [Color(red: 0.32, green: 0.05, blue: 0.12), Color(red: 0.12, green: 0.04, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [snapperRed.opacity(0.35), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 420)

            // Menu bar with the red fish
            HStack(spacing: 14) {
                Text("RED SNAPPER").font(.system(size: 10, weight: .bold))
                Text("File").font(.system(size: 10)); Text("Edit").font(.system(size: 10)); Text("View").font(.system(size: 10))
                Spacer()
                Image(systemName: "fish.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(snapperRed)
                Image(systemName: "wifi").font(.system(size: 10))
                Text("9:41").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(width: w, height: bar)
            .background(.black.opacity(0.35))

            // Three tiled windows
            MiniWindow(title: "Studio") { MusicContent() }
                .frame(width: cellW, height: cellH).offset(x: gap, y: bar + gap)
            MiniWindow(title: "main.swift") { CodeContent() }
                .frame(width: cellW, height: cellH).offset(x: gap * 2 + cellW, y: bar + gap)
            MiniWindow(title: "Messages") { ChatContent() }
                .frame(width: cellW, height: cellH).offset(x: gap, y: bar + gap * 2 + cellH)

            // The snap preview where the fourth window is heading
            RoundedRectangle(cornerRadius: 11)
                .fill(snapperRed.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(snapperRed.opacity(0.9), lineWidth: 2.5))
                .frame(width: cellW - 4, height: cellH - 4)
                .offset(x: gap * 2 + cellW + 2, y: bar + gap * 2 + cellH + 2)

            // The window being dragged, with the cursor on its title bar
            MiniWindow(title: "Notes") { NotesContent() }
                .frame(width: cellW * 0.78, height: cellH * 0.82)
                .rotationEffect(.degrees(-2.5))
                .offset(x: gap * 2 + cellW + 62, y: bar + gap * 2 + cellH + 30)
                .opacity(0.97)
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .offset(x: gap * 2 + cellW + 250, y: bar + gap * 2 + cellH + 30)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
    }
}

// MARK: - Hero

struct Chip: View {
    let symbol: String, text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(snapperRed)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

struct Hero: View {
    let icon: NSImage

    var body: some View {
        ZStack {
            LinearGradient(colors: [ink, Color(red: 0.20, green: 0.04, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Faint snapping grid in the background
            Canvas { ctx, size in
                let step: CGFloat = 32
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.white.opacity(0.06)))
                        y += step
                    }
                    x += step
                }
            }
            RadialGradient(colors: [snapperRed.opacity(0.28), .clear], center: .init(x: 0.78, y: 0.55), startRadius: 20, endRadius: 520)

            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 112, height: 112)
                        .shadow(color: snapperRed.opacity(0.45), radius: 24, y: 8)
                    Text("RED SNAPPER")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.78, blue: 0.76)], startPoint: .top, endPoint: .bottom))
                    Text("Snap your windows into place.\nFast, free, and a little bit fishy.")
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineSpacing(4)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) { Chip(symbol: "keyboard", text: "⌃⌥ + arrows"); Chip(symbol: "hand.draw", text: "Drag to snap") }
                        HStack(spacing: 8) { Chip(symbol: "square.grid.2x2", text: "4-up grid"); Chip(symbol: "rectangle.3.group", text: "Saved layouts") }
                    }
                    .padding(.top, 6)
                }
                .frame(width: 420, alignment: .leading)

                Screen()
            }
        }
        .frame(width: 1280, height: 640)
    }
}

// MARK: - Render

MainActor.assumeIsolated {
    let iconURL = root.appendingPathComponent("RedSnapper/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
    guard let icon = NSImage(contentsOf: iconURL) else { fatalError("missing app icon at \(iconURL.path)") }
    let renderer = ImageRenderer(content: Hero(icon: icon))
    renderer.scale = 2
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let out = root.appendingPathComponent("docs/images/hero.png")
    try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    try! png.write(to: out)
    print("wrote \(out.path) (\(cg.width)×\(cg.height))")
}
