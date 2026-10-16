//
//  AppModel.swift
//  Slice
//
//  Created by rit3zh CX on 10/3/26.
//

import Combine
import SliceCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Screen {
        case home
        case editor(EditorModel)
    }

    static let mainWindowID = "main"
    static let captureBarID = "capture"
    static weak var captureBarWindow: NSWindow?
    static weak var mainWindow: NSWindow?
    static var pendingReveal: (rect: CGRect, radius: CGFloat)?
    static var prewarming = false
    private static var prewarmed = false

    @Published private(set) var screen: Screen = .home
    @Published private(set) var covered = false
    @Published private(set) var setupAppendTo: EditorModel?
    @Published private(set) var recordingPhase: RecordingController.Phase?
    private var phaseWatch: AnyCancellable?
    var openWindow: OpenWindowAction? { didSet { openPendingFiles() } }
    var dismissWindow: DismissWindowAction?
    @Published var recording: RecordingController?
    @Published var projects: [ProjectBundle] = []
    @Published var error: String?
    var launchedWithProject = false
    private var pendingFiles: [URL] = []

    var openEditor: EditorModel? {
        if case let .editor(editor) = screen { editor } else { nil }
    }

    private init() { reloadProjects() }

    func reloadProjects() { projects = ProjectBundle.list(adding: NSDocumentController.shared.recentDocumentURLs) }

    /// Drops the card straight away and moves the bundle to the Trash off the main thread; a big bundle froze the grid.
    func trash(_ bundle: ProjectBundle) {
        projects.removeAll { $0.url == bundle.url }
        let url = bundle.url
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                await MainActor.run { [weak self] in self?.reloadProjects() }
            }
        }
    }

    func newRecording(appendTo editor: EditorModel? = nil) {
        setupAppendTo = editor
        recordingPhase = nil
        openWindow?(id: Self.captureBarID)
        NSApp.activate()
    }

    func cancelSetup() {
        dismissWindow?(id: Self.captureBarID)
        setupAppendTo = nil
    }

    func showProjects() {
        openWindow?(id: Self.mainWindowID)
        NSApp.activate()
    }

    /// Builds the main window once, out of sight, soon after launch. Making it (and laying out the projects for the
    /// first time) is heavy, and done on the first Open Projects it made the morph out of the bar stutter; made ahead,
    /// the first open is like every other.
    func prewarmMainWindow() {
        guard !Self.prewarmed, openEditor == nil else { return }
        Self.prewarmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, Self.mainWindow == nil, Self.pendingReveal == nil, recording == nil else { return }
            Self.prewarming = true
            openWindow?(id: Self.mainWindowID)
        }
    }

    func openProjectsFromBar() {
        presentMainWindow(from: CaptureBar.surface(for: nil))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard self?.recording == nil else { return }
            self?.cancelSetup()
        }
    }

    func show(_ screen: Screen, animated: Bool = true) {
        guard animated else {
            withTransaction(\.disablesAnimations, true) { self.screen = screen }
            return
        }
        switchScreen { screen }
    }

    /// Dips the window to its background, makes and swaps in the next screen while nothing is visible (the editor's
    /// first layout and frame are heavy, and would stutter any animation running over them), then lifts. `make`
    /// returning nil leaves things as they were.
    private func switchScreen(_ make: @escaping () -> Screen?) {
        withAnimation(.easeIn(duration: 0.14)) { covered = true } completion: { [weak self] in
            guard let self else { return }
            if let next = make() {
                withTransaction(\.disablesAnimations, true) { self.screen = next }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                withAnimation(.easeOut(duration: 0.26)) { self?.covered = false }
            }
        }
    }

    func importNewProject(_ urls: [URL]) {
        Task {
            do {
                let name = urls.first?.deletingPathExtension().lastPathComponent ?? "Imported"
                let (bundle, project) = try Wallpapers.newProject(name: name)
                let editor = EditorModel(bundle: bundle, project: project)
                await editor.importClips(urls)
                guard !editor.project.clips.isEmpty else {
                    try? FileManager.default.removeItem(at: bundle.url)
                    self.error = editor.transcribeError ?? "Nothing could be imported."
                    return
                }
                show(.editor(editor))
                reloadProjects()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func open(_ bundle: ProjectBundle) {
        switchScreen { [weak self] in self?.editorScreen(for: bundle) }
    }

    private func editorScreen(for bundle: ProjectBundle) -> Screen? {
        do {
            let project = try bundle.load()
            openEditor?.close()
            NSDocumentController.shared.noteNewRecentDocumentURL(bundle.url)
            return .editor(EditorModel(bundle: bundle, project: project))
        } catch {
            self.error = "Couldn't open “\(bundle.displayName)”: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Project files

    func openFiles(_ urls: [URL]) {
        guard let url = urls.first else { return }
        guard openWindow != nil else {
            pendingFiles = urls
            return
        }
        guard recording == nil else {
            NSSound.beep()
            return
        }
        if launchedWithProject {
            launchedWithProject = false
            cancelSetup()
        }
        if let current = openEditor {
            if current.bundle.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() {
                presentMainWindow(from: nil)
                return
            }
            if current.exportJob?.isRunning == true {
                presentMainWindow(from: nil)
                error = "Wait for the export to finish (or stop it) before opening another project."
                return
            }
        }
        let bundle: ProjectBundle
        do {
            let found = try ProjectBundle(opening: url)
            bundle = found.isWritable ? found : try found.copy()
        } catch {
            presentMainWindow(from: nil)
            self.error = error.localizedDescription
            return
        }
        if let window = Self.mainWindow, window.isVisible, !window.isMiniaturized {
            open(bundle)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if let next = editorScreen(for: bundle) {
            show(next, animated: false)
            presentMainWindow(from: nil)
        } else {
            presentMainWindow(from: nil)
        }
        reloadProjects()
    }

    private func openPendingFiles() {
        guard !pendingFiles.isEmpty, openWindow != nil else { return }
        let urls = pendingFiles
        pendingFiles = []
        DispatchQueue.main.async { [weak self] in self?.openFiles(urls) }
    }

    func chooseProjectToOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sliceProject]
        panel.directoryURL = ProjectBundle.defaultDirectory
        panel.message = "Choose a Slice project to open."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFiles([url])
    }

    func presentMainWindow(from source: (rect: CGRect, radius: CGFloat)?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = Self.mainWindow else {
            Self.pendingReveal = source
            openWindow?(id: Self.mainWindowID)
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        } else if let source, !window.isVisible {
            WindowMorph.reveal(window, from: source.rect, radius: source.radius)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func startRecording(settings: Recorder.Settings, appendTo editor: EditorModel?) {
        let controller = RecordingController(settings: settings, editor: editor) { [weak self] result in
            guard let self else { return }
            let source = CaptureBar.surface(for: recordingPhase)
            phaseWatch = nil
            setupAppendTo = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.recording == nil { self?.recordingPhase = nil }
            }
            var problem = recording?.warning
            let hidden = recording?.hidden ?? []
            recording = nil
            switch result {
            case let .success(editor):
                if let editor {
                    editor.reloadAfterRecording()
                    show(.editor(editor), animated: false)
                } else {
                    show(.home, animated: false)
                }
            case let .failure(err):
                problem = err.localizedDescription
                show(editor.map { .editor($0) } ?? .home, animated: false)
            }
            reloadProjects()
            hidden.filter { $0 !== Self.mainWindow }.forEach { $0.orderFront(nil) }
            presentMainWindow(from: source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, recording == nil else { return }
                dismissWindow?(id: Self.captureBarID)
            }
            if let problem {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.error = problem }
            }
        }
        recording = controller
        phaseWatch = controller.$phase.sink { [weak self] in self?.recordingPhase = $0 }
        controller.start()
    }
}
