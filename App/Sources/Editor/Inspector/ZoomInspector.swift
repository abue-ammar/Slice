//
//  ZoomInspector.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import AVFoundation
import SliceCore
import SwiftUI

struct ZoomInspector: View {
    @ObservedObject var editor: EditorModel
    let block: ZoomBlock

    private func bind<T>(_ keyPath: WritableKeyPath<ZoomBlock, T>) -> Binding<T> {
        Binding(get: { block[keyPath: keyPath] }, set: { v in editor.updateZoomBlock(block.id) { $0[keyPath: keyPath] = v } })
    }

    private func lens(_ keyPath: WritableKeyPath<LensSettings, Double>) -> Binding<Double> {
        bind((\ZoomBlock.lens).appending(path: keyPath))
    }

    private var isLens: Bool { block.kind == .liquidGlass }

    var body: some View {
        let d = LensSettings()
        VStack(alignment: .leading, spacing: 18) {
            InfoRow(title: "Time", value: "\(format(block.start)) – \(format(block.end))")
            SegmentedControl(selection: bind(\.kind), options: ZoomKind.allCases, title: \.label,
                             symbol: { $0 == .liquidGlass ? "drop" : "plus.magnifyingglass" })
            PanelNote(isLens
                ? "A glass lens floats over the recording and magnifies what's under it."
                : "The view moves in on the area you frame.")

            PanelSection(isLens ? "Lens" : "Zoom") {
                SegmentedControl(selection: bind(\.followsCursor), options: [true, false],
                                 title: { $0 ? "Follow cursor" : "Manual" },
                                 symbol: { $0 ? "cursorarrow.rays" : "hand.draw" })
                if block.followsCursor {
                    PanelNote(isLens ? "The lens follows the pointer." : "The zoom follows the pointer.")
                } else if !isLens {
                    ZoomFramePicker(editor: editor, block: block)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                PanelSlider(isLens ? "Magnification" : "Zoom level", value: bind(\.scale), in: isLens ? 1.2 ... 4 : 1 ... 4,
                            default: 2) { String(format: "%.1f×", $0) }
                scalePresets
                if isLens {
                    PanelSlider("Size", value: lens(\.size), in: 0.15 ... 1, default: d.size) { "\(Int(($0 * 100).rounded()))%" }
                    SegmentedControl(selection: bind((\ZoomBlock.lens).appending(path: \LensSettings.shape)),
                                     options: LensShape.allCases, title: \.label)
                }
                if !block.followsCursor {
                    PanelToggle(isLens ? "Glide to a second spot" : "Pan to a second spot", isOn: Binding(
                        get: { block.endFocus != nil },
                        set: { on in
                            editor.updateZoomBlock(block.id) { z in
                                z.endFocus = on ? CGPoint(x: min(z.focus.x + 0.25, 0.9), y: z.focus.y) : nil
                            }
                        }))
                    PanelNote(isLens
                        ? (block.endFocus == nil ? "Drag the lens in the preview to place it."
                            : "Drag the Start and End lenses in the preview. It glides between them over the zoom.")
                        : (block.endFocus == nil ? "Drag the frame above (or in the preview) to choose what it zooms on."
                            : "Drag the Start and End frames. It pans between them over the zoom."))
                }
            }

            PanelDivider()
            PanelSection("Motion") {
                PanelSlider("Zoom in / out time",
                            value: Binding(get: { block.transition ?? editor.project.style.zoomTransitionDuration },
                                           set: { v in editor.updateZoomBlock(block.id) { $0.transition = v } }),
                            in: 0 ... 2, default: editor.project.style.zoomTransitionDuration) { String(format: "%.1fs", $0) }
                    .help("How long it takes to zoom in at the start and back out at the end")
                MotionPicker(easing: bind(\.easing), curve: bind(\.curve),
                             duration: block.transition ?? editor.project.style.zoomTransitionDuration)
            }

            if !isLens {
                PanelDivider()
                tiltSection
            }

            if isLens {
                PanelDivider()
                PanelSection("Glass") {
                    ChoiceChips(options: GlassLook.all.map(\.name), selected: GlassLook.matching(block.lens)?.name,
                                title: { $0 }) { name in
                        guard let look = GlassLook.all.first(where: { $0.name == name }) else { return }
                        editor.updateZoomBlock(block.id) { look.apply(to: &$0.lens) }
                    }
                    PanelNote(GlassLook.matching(block.lens)?.note ?? "Your own mix. Pick a look above to start again.")
                    MoreOptions("Fine-tune the glass", id: "glass") {
                        PanelSlider("Refraction", value: lens(\.refraction), in: 0 ... 1, default: d.refraction) { pct($0) }
                            .help("How strongly the thick edge bends the picture")
                        PanelSlider("Thickness", value: lens(\.thickness), in: 0 ... 1, default: d.thickness) { pct($0) }
                            .help("How far in from the rim the bending reaches")
                        PanelSlider("Dispersion", value: lens(\.dispersion), in: 0 ... 1, default: d.dispersion) { pct($0) }
                            .help("Rainbow fringing at the edge")
                        PanelSlider("Frost", value: lens(\.blur), in: 0 ... 1, default: d.blur) { $0 < 0.01 ? "Off" : pct($0) }
                        PanelSlider("Rim light", value: lens(\.rim), in: 0 ... 1, default: d.rim) { pct($0) }
                        PanelSlider("Shadow", value: lens(\.shadow), in: 0 ... 1, default: d.shadow) { pct($0) }
                        PanelSlider("Opacity", value: lens(\.opacity), in: 0.2 ... 1, default: d.opacity) { pct($0) }
                    }
                }
            }

            Button("Delete zoom") { editor.deleteSelection() }.buttonStyle(DestructiveButtonStyle())
        }
        .animation(.snappy, value: block.kind)
        .animation(.snappy, value: block.followsCursor)
        .animation(.snappy, value: block.endFocus == nil)
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private var tiltSection: some View {
        PanelSection("3D tilt", trailing: AnyView(
            Toggle("3D tilt", isOn: bind((\ZoomBlock.tilt).appending(path: \ZoomTilt.enabled)).animation(.snappy))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
                .help("Turn the screen in 3D while zoomed in"))) {
            if block.tilt.enabled {
                Group {
                    SegmentedControl(selection: bind((\ZoomBlock.tilt).appending(path: \ZoomTilt.direction)),
                                     options: TiltDirection.allCases, title: \.label)
                        .help("Which side leans away from you")
                    PanelSlider("Strength", value: bind((\ZoomBlock.tilt).appending(path: \ZoomTilt.strength)),
                                in: 0.1 ... 1, default: ZoomTilt().strength) {
                        "\(Int(($0 * ZoomTilt.maxAngle).rounded()))°"
                    }
                    PanelNote("Turns as it zooms in and back as it zooms out, with the zoom's own timing.")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: block.tilt.enabled)
    }

    private var scalePresets: some View {
        let levels = [1.5, 2, 2.5, 3]
        return ChoiceChips(options: levels, selected: levels.first { abs(block.scale - $0) < 0.01 },
                           title: { String(format: $0 == $0.rounded() ? "%.0f×" : "%.1f×", $0) }, rounded: true) {
            editor.updateZoom(block.id, scale: $0)
        }
    }
}

private struct GlassLook {
    let name: String
    let note: String
    let refraction, thickness, dispersion, blur, rim, shadow, opacity: Double

    static let all: [GlassLook] = {
        let d = LensSettings()
        return [
            GlassLook(name: "Clear", note: "Crisp glass that bends the picture at its edge.",
                      refraction: d.refraction, thickness: d.thickness, dispersion: d.dispersion, blur: d.blur,
                      rim: d.rim, shadow: d.shadow, opacity: d.opacity),
            GlassLook(name: "Subtle", note: "Barely there: a light edge and a soft shadow.",
                      refraction: 0.2, thickness: 0.2, dispersion: 0, blur: 0, rim: 0.4, shadow: 0.35, opacity: 1),
            GlassLook(name: "Bold", note: "Thick, bright glass with colour at the edge.",
                      refraction: 0.8, thickness: 0.5, dispersion: 0.5, blur: 0, rim: 1, shadow: 0.7, opacity: 1),
            GlassLook(name: "Frosted", note: "Soft, frosted glass.",
                      refraction: 0.35, thickness: 0.35, dispersion: 0.1, blur: 0.55, rim: 0.6, shadow: 0.5, opacity: 1),
        ]
    }()

    static func matching(_ lens: LensSettings) -> GlassLook? {
        all.first { l in
            [l.refraction - lens.refraction, l.thickness - lens.thickness, l.dispersion - lens.dispersion, l.blur - lens.blur,
             l.rim - lens.rim, l.shadow - lens.shadow, l.opacity - lens.opacity].allSatisfy { abs($0) < 0.005 }
        }
    }

    func apply(to lens: inout LensSettings) {
        lens.refraction = refraction
        lens.thickness = thickness
        lens.dispersion = dispersion
        lens.blur = blur
        lens.rim = rim
        lens.shadow = shadow
        lens.opacity = opacity
    }
}

struct ZoomFramePicker: View {
    @ObservedObject var editor: EditorModel
    let block: ZoomBlock
    @State private var image: CGImage?
    @State private var drag: (end: Bool, center: CGPoint)?

    private var clipIndex: Int { editor.project.clipStarts.lastIndex { $0 <= block.start } ?? 0 }

    private var geometry: ScreenGeometry {
        let project = editor.project
        let clip = project.clips.indices.contains(clipIndex) ? project.clips[clipIndex] : nil
        return ScreenGeometry(contentSize: clip?.screenPixelSize ?? editor.previewSize, output: editor.previewSize,
                              style: project.style, shapedByAlpha: clip?.device != nil)
    }

    private func frame(_ focus: CGPoint, _ g: ScreenGeometry) -> CGRect {
        let r = g.zoomedView(scale: block.scale, focus: focus), c = g.contentRect
        return CGRect(x: (r.minX - c.minX) / c.width, y: (r.minY - c.minY) / c.height,
                      width: r.width / c.width, height: r.height / c.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private var frameTime: (clip: Int, local: Double)? {
        editor.project.sourceTime(edited: (block.start + block.end) / 2).map { ($0.clipIndex, $0.local) }
    }

    var body: some View {
        let g = geometry
        let c = g.contentRect
        let start = frame(block.focus, g)
        let end = block.endFocus.map { frame($0, g) }
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                    } else {
                        Rectangle().fill(Theme.control)
                    }
                }
                .frame(width: size.width, height: size.height)
                .overlay(Color.black.opacity(0.35))
                if let end { marker(end, in: size, label: "End", primary: false) }
                marker(start, in: size, label: end == nil ? nil : "Start", primary: true)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let loc = CGPoint(x: v.startLocation.x / size.width, y: v.startLocation.y / size.height)
                    if drag == nil {
                        if let end, end.contains(loc) { drag = (true, CGPoint(x: end.midX, y: end.midY)) }
                        else if start.contains(loc) { drag = (false, CGPoint(x: start.midX, y: start.midY)) }
                        else { drag = (false, loc) }
                    }
                    guard let drag else { return }
                    let rect = drag.end ? (end ?? start) : start
                    let p = CGPoint(x: drag.center.x + v.translation.width / size.width,
                                    y: drag.center.y + v.translation.height / size.height)
                    let focus = CGPoint(x: min(max(p.x, rect.width / 2), 1 - rect.width / 2),
                                        y: min(max(p.y, rect.height / 2), 1 - rect.height / 2))
                    if drag.end { editor.updateZoom(block.id, endFocus: focus) } else { editor.updateZoom(block.id, focus: focus) }
                }
                .onEnded { _ in drag = nil })
            .pointerStyle(drag == nil ? .grabIdle : .grabActive)
        }
        .aspectRatio(c.width / max(c.height, 1), contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke))
        .task(id: frameTime.map { "\($0.clip)-\(Int($0.local * 2))" }) { await loadImage() }
        .accessibilityElement()
        .accessibilityLabel("Zoom framing")
        .accessibilityValue(String(format: "Centred at %d%% across, %d%% down",
                                   Int(block.focus.x * 100), Int(block.focus.y * 100)))
    }

    private func marker(_ r: CGRect, in size: CGSize, label: String?, primary: Bool) -> some View {
        let rect = CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width,
                          height: r.height * size.height)
        let color = primary ? Theme.accent : Color.white
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color.opacity(0.12))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: primary ? [] : [5, 4]))
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(color))
                    .padding(4)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
    }

    private func loadImage() async {
        guard let t = frameTime, editor.project.clips.indices.contains(t.clip) else { return }
        let asset = AVURLAsset(url: editor.bundle.file(editor.project.clips[t.clip].screenFile))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        if let cg = try? await generator.image(at: CMTime(seconds: t.local, preferredTimescale: 600)).image {
            withAnimation(.easeOut(duration: 0.2)) { image = cg }
        }
    }
}
