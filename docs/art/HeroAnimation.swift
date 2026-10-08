// Renders the animated README hero: `swift docs/art/HeroAnimation.swift` (writes docs/images/hero.gif).
// Same layout and colors as Hero.swift, but the desktop plays a loop: messy windows get snapped
// into a 2x2 grid with keyboard shortcuts, then the last one is dragged into its corner.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let snapperRed = Color(red: 1.0, green: 0.23, blue: 0.19)
let ink = Color(red: 0.10, green: 0.05, blue: 0.07)
let windowFill = Color(red: 0.14, green: 0.12, blue: 0.15)

let fps = 20.0
let duration = 8.0
let outputScale: CGFloat = 0.8   // 1280×640 layout → 1024×512 GIF

// MARK: - Timeline

func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
/// 0 before `start`, 1 after `start + length`, eased in between.
func progress(_ t: Double, _ start: Double, _ length: Double) -> Double {
    let p = clamp((t - start) / length)
    return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
}
func mix(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
    let p = CGFloat(p)
    return CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                  width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
}
func mix(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * CGFloat(p), y: a.y + (b.y - a.y) * CGFloat(p))
}

// Desktop geometry (inside the 720×450 screen, below a 20pt menu bar).
let screenW: CGFloat = 720, screenH: CGFloat = 450, barH: CGFloat = 20, gap: CGFloat = 10
let cellW = (screenW - gap * 3) / 2, cellH = (screenH - barH - gap * 3) / 2
func cell(_ col: Int, _ row: Int) -> CGRect {
    CGRect(x: gap + CGFloat(col) * (cellW + gap), y: barH + gap + CGFloat(row) * (cellH + gap), width: cellW, height: cellH)
}

// Messy starting frames, and the beats of the loop.
let messy = [
    CGRect(x: 60, y: 60, width: 380, height: 250),    // Studio
    CGRect(x: 300, y: 110, width: 360, height: 240),  // main.swift
    CGRect(x: 120, y: 200, width: 330, height: 210),  // Messages
    CGRect(x: 380, y: 170, width: 290, height: 230),  // Notes
]
let snapStarts = [0.9, 1.9, 2.9]          // ⌃⌥U, ⌃⌥I, ⌃⌥J
let snapLength = 0.45
let dragStart = 4.0, dragLength = 1.3, dropAt = 5.5
let resetStart = 7.4, resetLength = 0.6

struct Beat {
    var frames: [CGRect]
    var keys: [String]?        // keycaps on screen
    var keysOpacity = 0.0
    var cursor: CGPoint?
    var previewOpacity = 0.0
    var dragTilt = 0.0
    var activeChip: Int?       // 0 keyboard, 1 drag
    var highlight: Int?        // window being acted on
    var fish: CGPoint?         // the swimming fish (nil = at home in the menu bar)
    var fishFacingLeft = false
    var bubbles: [(CGPoint, Double)] = []   // position, opacity
}

func beat(at t: Double) -> Beat {
    var frames = messy
    var b = Beat(frames: frames)
    let targets = [cell(0, 0), cell(1, 0), cell(0, 1)]
    let keySets = [["⌃", "⌥", "U"], ["⌃", "⌥", "I"], ["⌃", "⌥", "J"]]

    for i in 0..<3 {
        frames[i] = mix(messy[i], targets[i], progress(t, snapStarts[i], snapLength))
        if t >= snapStarts[i] - 0.35 && t < snapStarts[i] + 0.75 {
            b.keys = keySets[i]
            b.keysOpacity = min(clamp((t - (snapStarts[i] - 0.35)) / 0.15), clamp((snapStarts[i] + 0.75 - t) / 0.15))
            b.activeChip = 0
            b.highlight = i
        }
    }

    // Drag the Notes window by its title bar toward the bottom-right corner.
    let grab = CGPoint(x: 140, y: 11)   // offset of the cursor within the dragged window
    let notesStart = messy[3]
    let notesHeld = CGRect(origin: CGPoint(x: screenW - 250, y: screenH - 190), size: CGSize(width: 230, height: 180))
    let dragP = progress(t, dragStart, dragLength)
    if t >= dragStart - 0.5 && t < dropAt + 0.5 { b.activeChip = 1; b.highlight = 3 }
    if t < dropAt {
        // While dragging, the window shrinks a little and tilts, as in Hero.swift.
        frames[3] = mix(notesStart, notesHeld, dragP)
        b.dragTilt = -2.5 * dragP
        let approach = progress(t, dragStart - 0.6, 0.5)   // cursor moves onto the title bar first
        let titleBar = CGPoint(x: notesStart.minX + grab.x, y: notesStart.minY + grab.y)
        b.cursor = t < dragStart ? mix(CGPoint(x: 640, y: 380), titleBar, approach)
                                 : CGPoint(x: frames[3].minX + grab.x, y: frames[3].minY + grab.y)
        b.previewOpacity = clamp((t - (dragStart + dragLength * 0.6)) / 0.3)
    } else {
        let snapP = progress(t, dropAt, 0.3)
        frames[3] = mix(notesHeld, cell(1, 1), snapP)
        b.dragTilt = -2.5 * (1 - snapP)
        b.previewOpacity = 1 - clamp((t - dropAt) / 0.2)
        b.cursor = mix(CGPoint(x: notesHeld.minX + grab.x, y: notesHeld.minY + grab.y), CGPoint(x: 600, y: 120),
                       progress(t, dropAt + 0.3, 0.8))
    }

    // Back to the mess for a seamless loop.
    let r = progress(t, resetStart, resetLength)
    if r > 0 {
        let snapped = [cell(0, 0), cell(1, 0), cell(0, 1), cell(1, 1)]
        for i in 0..<4 { frames[i] = mix(snapped[i], messy[i], r) }
        b.cursor = mix(CGPoint(x: 600, y: 120), CGPoint(x: 640, y: 380), r)
    }
    b.frames = frames
    b.fish = fishPosition(at: t)
    if let p = b.fish, let q = fishPosition(at: t - 0.05) { b.fishFacingLeft = p.x < q.x - 0.5 }
    // A trail of bubbles from where the fish just was, rising and fading.
    for k in 1...6 {
        let born = t - Double(k) * 0.14
        guard let p = fishPosition(at: born) else { continue }
        let age = t - born
        b.bubbles.append((CGPoint(x: p.x + CGFloat(sin(born * 9)) * 6, y: p.y - 8 - CGFloat(age) * 45), max(0, 0.7 - age * 0.8)))
    }
    // Celebration burst once the grid is complete.
    let burst = t - (dropAt + 0.35)
    if burst > 0 && burst < 1.2 {
        let c = CGPoint(x: screenW / 2, y: barH + (screenH - barH) / 2)
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi
            let r = 30 + burst * 90
            b.bubbles.append((CGPoint(x: c.x + CGFloat(cos(a) * r), y: c.y + CGFloat(sin(a) * r) - CGFloat(burst) * 20), max(0, 1 - burst / 1.2)))
        }
    }
    return b
}

/// Where the fish is at time `t`: out of the menu bar, nudging each window into its corner,
/// swimming alongside the drag, a happy loop, then home again.
let fishHome = CGPoint(x: screenW - 64, y: 10)
func titleBar(_ r: CGRect) -> CGPoint { CGPoint(x: r.minX + 46, y: r.minY - 2) }   // riding on the title bar, past the traffic lights
func fishPosition(at t: Double) -> CGPoint? {
    guard t > 0.3 && t < 7.45 else { return nil }
    let f = { (time: Double) in beatFrames(at: time) }
    let snapEnd = snapStarts.map { $0 + snapLength }
    func swim(_ from: CGPoint, _ to: CGPoint, _ start: Double, _ end: Double) -> CGPoint {
        mix(from, to, progress(t, start, end - start))
    }
    // Swim to a window, then ride with it while it snaps.
    let legs: [(Double, Double, Int)] = [(0.3, snapStarts[0], 0), (snapEnd[0], snapStarts[1], 1), (snapEnd[1], snapStarts[2], 2)]
    for (n, (start, arrive, i)) in legs.enumerated() {
        let from = n == 0 ? fishHome : titleBar(f(start)[legs[n - 1].2])
        if t < arrive { return swim(from, titleBar(f(arrive)[i]), start, arrive) }
        if t < snapEnd[i] { return titleBar(f(t)[i]) }
    }
    // Swim alongside the dragged Notes window, a little above the cursor.
    let alongside = { (time: Double) -> CGPoint in let r = f(time)[3]; return CGPoint(x: r.minX + 70, y: r.minY - 18) }
    if t < dragStart { return swim(titleBar(f(snapEnd[2])[2]), alongside(dragStart), snapEnd[2], dragStart) }
    if t < dropAt + 0.35 { return alongside(t) }
    // Happy loop around the middle of the finished grid.
    let center = CGPoint(x: screenW / 2, y: barH + (screenH - barH) / 2)
    let loopStart = dropAt + 0.35, loopEnd = 6.9
    let loopEntry = CGPoint(x: center.x + 55, y: center.y)
    if t < loopStart + 0.3 { return swim(alongside(dropAt + 0.35), loopEntry, loopStart, loopStart + 0.3) }
    if t < loopEnd {
        let a = (t - loopStart - 0.3) / (loopEnd - loopStart - 0.3) * 2 * .pi
        return CGPoint(x: center.x + CGFloat(cos(a)) * 55, y: center.y - CGFloat(sin(a)) * 40)
    }
    return swim(loopEntry, fishHome, loopEnd, 7.45)
}
/// Window frames at time `t` (the same timeline `beat` uses, without the extras).
func beatFrames(at t: Double) -> [CGRect] {
    var frames = messy
    let targets = [cell(0, 0), cell(1, 0), cell(0, 1)]
    for i in 0..<3 { frames[i] = mix(messy[i], targets[i], progress(t, snapStarts[i], snapLength)) }
    let held = CGRect(origin: CGPoint(x: screenW - 250, y: screenH - 190), size: CGSize(width: 230, height: 180))
    frames[3] = t < dropAt ? mix(messy[3], held, progress(t, dragStart, dragLength)) : mix(held, cell(1, 1), progress(t, dropAt, 0.3))
    return frames
}

// MARK: - Views (from Hero.swift)

struct MiniWindow<Content: View>: View {
    let title: String
    var highlighted = false
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
            GeometryReader { geo in
                content
                    .frame(minWidth: max(0, geo.size.width - 20), alignment: .topLeading)
                    .fixedSize()
                    .padding(10)
            }
            .clipped()
        }
        .background(windowFill)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(highlighted ? snapperRed.opacity(0.9) : .white.opacity(0.09), lineWidth: highlighted ? 2 : 1))
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
            bubble(110, mine: false); bubble(80, mine: true); bubble(130, mine: false); bubble(60, mine: true)
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

struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25)))
    }
}

struct Chip: View {
    let symbol: String, text: String
    var active = false
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(active ? .white : snapperRed)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(active ? snapperRed.opacity(0.85) : .white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(active ? snapperRed : .white.opacity(0.12)))
    }
}

struct AnimatedScreen: View {
    let b: Beat
    let t: Double
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.05, blue: 0.12), Color(red: 0.12, green: 0.04, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [snapperRed.opacity(0.35), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 420)

            HStack(spacing: 14) {
                Text("RED SNAPPER").font(.system(size: 10, weight: .bold))
                Text("File").font(.system(size: 10)); Text("Edit").font(.system(size: 10)); Text("View").font(.system(size: 10))
                Spacer()
                Image(systemName: "fish.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(snapperRed)
                    .opacity(b.fish == nil ? 1 : 0.15)   // it's out swimming
                Image(systemName: "wifi").font(.system(size: 10))
                Text("9:41").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(width: screenW, height: barH)
            .background(.black.opacity(0.35))

            // Snap preview for the drag (under the dragged window).
            let target = cell(1, 1)
            RoundedRectangle(cornerRadius: 11)
                .fill(snapperRed.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(snapperRed.opacity(0.9), lineWidth: 2.5))
                .frame(width: target.width - 4, height: target.height - 4)
                .offset(x: target.minX + 2, y: target.minY + 2)
                .opacity(b.previewOpacity)

            window(0, "Studio") { MusicContent() }
            window(1, "main.swift") { CodeContent() }
            window(2, "Messages") { ChatContent() }
            window(3, "Notes") { NotesContent() }

            if let keys = b.keys {
                HStack(spacing: 8) { ForEach(keys, id: \.self) { Keycap(key: $0) } }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
                    .offset(x: screenW / 2 - 85, y: screenH - 90)
                    .opacity(b.keysOpacity)
                    .scaleEffect(0.9 + 0.1 * b.keysOpacity, anchor: .center)
                    .zIndex(2)   // above the raised (highlighted) window
            }
            ForEach(b.bubbles.indices, id: \.self) { k in
                Circle()
                    .strokeBorder(.white.opacity(0.75), lineWidth: 1.2)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .frame(width: 7 + CGFloat(k % 3) * 2, height: 7 + CGFloat(k % 3) * 2)
                    .offset(x: b.bubbles[k].0.x, y: b.bubbles[k].0.y)
                    .opacity(b.bubbles[k].1)
                    .zIndex(2)
            }
            if let p = b.fish {
                Image(systemName: "fish.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(snapperRed)
                    .shadow(color: .white.opacity(0.9), radius: 0.8)
                    .shadow(color: snapperRed.opacity(0.8), radius: 8)
                    .scaleEffect(x: (b.fishFacingLeft ? -1 : 1) * (1 + 0.06 * sin(t * 26)), y: 1)   // tail wiggle
                    .rotationEffect(.degrees(sin(t * 13) * 7))
                    .offset(x: p.x - 24, y: p.y - 18)
                    .zIndex(2.5)
            }
            if let c = b.cursor {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .offset(x: c.x - 4, y: c.y - 2)
                    .zIndex(3)
            }
        }
        .frame(width: screenW, height: screenH)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
    }

    func window<C: View>(_ i: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        let f = b.frames[i]
        return MiniWindow(title: title, highlighted: b.highlight == i) { content() }
            .frame(width: f.width, height: f.height)
            .rotationEffect(.degrees(i == 3 ? b.dragTilt : 0))
            .offset(x: f.minX, y: f.minY)
            .zIndex(b.highlight == i ? 1 : 0)
    }
}

struct HeroFrame: View {
    let icon: NSImage
    let t: Double

    var body: some View {
        let b = beat(at: t)
        ZStack {
            LinearGradient(colors: [ink, Color(red: 0.20, green: 0.04, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                        HStack(spacing: 8) {
                            Chip(symbol: "keyboard", text: "⌃⌥ + arrows", active: b.activeChip == 0)
                            Chip(symbol: "hand.draw", text: "Drag to snap", active: b.activeChip == 1)
                        }
                        HStack(spacing: 8) { Chip(symbol: "square.grid.2x2", text: "4-up grid"); Chip(symbol: "rectangle.3.group", text: "Saved layouts") }
                    }
                    .padding(.top, 6)
                }
                .frame(width: 420, alignment: .leading)

                AnimatedScreen(b: b, t: t)
            }
        }
        .frame(width: 1280, height: 640)
    }
}

// MARK: - Render

MainActor.assumeIsolated {
    let iconURL = root.appendingPathComponent("RedSnapper/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
    guard let icon = NSImage(contentsOf: iconURL) else { fatalError("missing app icon at \(iconURL.path)") }
    let out = root.appendingPathComponent("docs/images/hero.gif")
    let frameCount = Int(duration * fps)
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { fatalError("can't write gif") }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps,
                                                      kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary
    for i in 0..<frameCount {
        let renderer = ImageRenderer(content: HeroFrame(icon: icon, t: Double(i) / fps).environment(\.colorScheme, .dark))
        renderer.scale = outputScale
        guard let cg = renderer.cgImage else { fatalError("render failed at frame \(i)") }
        CGImageDestinationAddImage(dest, cg, frameProps)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("gif finalize failed") }
    let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
    print("wrote \(out.lastPathComponent): \(frameCount) frames, \(size / 1024) KB")
}
