//
//  ProjectsView.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AVFoundation
import SliceCore
import SmoothGradient
import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var lightsInset: CGFloat?
    @State private var scrolled: CGFloat = 0
    @State private var columns = Self.lastColumns
    @State private var laidOut = false
    /// The grid comes back with the columns it had, so it doesn't reflow under a picture flying back into it.
    private static var lastColumns = 3

    static let barHeight: CGFloat = 52
    private static let gutter: CGFloat = 22
    private static let margin: CGFloat = 32
    private static let minCard: CGFloat = 240

    private var shown: [ProjectBundle] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.projects }
        return model.projects.filter { $0.displayName.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
            bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .ignoresSafeArea(.container, edges: .top)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(Theme.accent)
        .onAppear {
            model.reloadProjects()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { laidOut = true }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let found = urls.filter(ProjectBundle.isProject)
            guard !found.isEmpty else { return false }
            model.openFiles(found)
            return true
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Projects")
                    .font(.rounded(15, .semibold))
                if !model.projects.isEmpty {
                    Text("\(model.projects.count)")
                        .font(.rounded(13, .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
            .allowsHitTesting(false)
            Spacer(minLength: 16)
            GlassGroup {
                HStack(spacing: 8) {
                    if !model.projects.isEmpty { SearchField(text: $search) }
                    Button(action: importVideos) {
                        Label("Import Video…", systemImage: "square.and.arrow.down")
                    }
                    .modifier(GlassOr(shape: Circle(), pill: false))
                    .help("Start a project from videos you already have")
                    NewRecordingButton { model.newRecording() }
                }
            }
        }
        .padding(.leading, (lightsInset ?? 14) + 4)
        .padding(.trailing, 16)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ScrollEdge(edge: .top, height: Self.barHeight + 36, strength: 0.8, blur: 0.95)
                .frame(height: Self.barHeight + 36, alignment: .top)
                .opacity(scrolled)
                .allowsHitTesting(false)
        }
        .background { DragArea() }
        .background(TrafficLights(height: Self.barHeight, leading: 20) { lightsInset = $0 })
        .animation(Theme.slide, value: model.projects.count)
    }

    // MARK: Grid

    @ViewBuilder private var content: some View {
        let shown = self.shown
        let days = ProjectDay.group(shown)
        let firstURL = days.first?.projects.first?.url
        if model.projects.isEmpty {
            EmptyProjects(record: { model.newRecording() }, importVideos: importVideos)
        } else if shown.isEmpty {
            VStack(spacing: 4) {
                Text("No results")
                    .font(.system(size: 13, weight: .medium))
                Text("Nothing called “\(search.trimmingCharacters(in: .whitespaces))”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, Self.barHeight)
            .transition(.opacity)
        } else {
            ScrollView {
                // Plain VStack: a LazyVStack sometimes left an emptied day behind as a blank gap.
                VStack(alignment: .leading, spacing: 34) {
                    ForEach(days) { day in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(day.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gutter, alignment: .top),
                                                     count: columns),
                                      alignment: .leading, spacing: 26) {
                                ForEach(day.projects, id: \.url) { bundle in
                                    ProjectCard(bundle: bundle, first: bundle.url == firstURL) {
                                        model.open(bundle)
                                    } delete: {
                                        withAnimation(Theme.slide) { model.trash(bundle) }
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.top, 10)
                .padding(.bottom, 40)
                .animation(Theme.slide, value: shown.map(\.url))
            }
            .contentMargins(.top, Self.barHeight, for: .scrollContent)
            .contentMargins(.top, Self.barHeight, for: .scrollIndicators)
            .scrollIndicators(.automatic)
            .modifier(HidesSystemScrollEdge())
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max((geometry.contentOffset.y + geometry.contentInsets.top) / 24, 0), 1)
            } action: { _, amount in
                withAnimation(.smooth(duration: 0.18)) { scrolled = amount }
            }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 0.5 } action: { _, top in
                ProjectFaces.shared.gridAtTop = top
            }
            .onGeometryChange(for: Int.self) { geometry in
                let room = geometry.size.width - Self.margin * 2
                return max(1, Int((room + Self.gutter) / (Self.minCard + Self.gutter)))
            } action: { count in
                guard count != columns else { return }
                Self.lastColumns = count
                if laidOut {
                    withAnimation(.smooth(duration: 0.38)) { columns = count }
                } else {
                    columns = count
                }
            }
            .overlay(alignment: .bottom) {
                ScrollEdge(edge: .bottom, height: 56, strength: 0.6).allowsHitTesting(false)
            }
        }
    }

    private func importVideos() {
        if let urls = chooseVideos() { model.importNewProject(urls) }
    }
}

// MARK: - Scroll edge

private struct ScrollEdge: View {
    let edge: VerticalEdge
    let height: CGFloat
    var strength: Double = 0.75
    var blur: Double = 0.45

    var body: some View {
        let start: UnitPoint = edge == .top ? .top : .bottom
        let end: UnitPoint = edge == .top ? .bottom : .top
        let fade = SmoothLinearGradient(from: Theme.window.opacity(strength), to: Theme.window.opacity(0),
                                        startPoint: start, endPoint: end, curve: .easeInOut, steps: 32)
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(blur)
                .mask(SmoothLinearGradient(from: .black, to: .clear, startPoint: start, endPoint: end,
                                           curve: .easeOut, steps: 32))
            fade
        }
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
    }
}

/// macOS 26 adds its own soft edge under the title bar; the bar's blur replaces it so the two don't stack.
private struct HidesSystemScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectHidden(true, for: .all)
        } else {
            content
        }
    }
}

// MARK: - Days

private struct ProjectDay: Identifiable {
    let title: String
    var projects: [ProjectBundle]
    var id: String { title }

    static func group(_ bundles: [ProjectBundle]) -> [ProjectDay] {
        let calendar = Calendar.current
        var days: [ProjectDay] = []
        let dated = bundles.map { ($0, $0.lastModified) }.sorted { $0.1 > $1.1 }
        for (bundle, date) in dated {
            let title = Self.title(for: date, calendar: calendar)
            if let i = days.firstIndex(where: { $0.title == title }) {
                days[i].projects.append(bundle)
            } else {
                days.append(ProjectDay(title: title, projects: [bundle]))
            }
        }
        return days
    }

    private static func title(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        let thisYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        return thisYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
    }
}
