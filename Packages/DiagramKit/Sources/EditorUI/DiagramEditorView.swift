#if !os(tvOS)
import DiagramCore
import SwiftUI
import UniformTypeIdentifiers

/// The editor: source in one pane, live preview in the other.
///
/// Layout follows the horizontal size class and the shape of the space, not
/// the device. Compact width (iPhone, the Duo's outer display, a narrow iPad
/// split) shows one pane at a time. Regular width shows both: side by side
/// when the space is wider than tall, stacked when it is taller than wide, and
/// either side of the fold when a Duo is partly open.
public struct DiagramEditorView: View {
    @Binding private var source: String
    private let engine: any DiagramEngine

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var result = RenderResult()
    @State private var lastGood: RenderedDiagram?
    @State private var pane: Pane = .code
    @State private var exportFile: ExportedFile?
    @State private var isExporting = false
    @State private var exportFailed = false
    @State private var pendingTemplate: SampleDiagram?

    private enum Pane: String, CaseIterable, Identifiable {
        case code = "Code"
        case preview = "Preview"

        var id: String { rawValue }
    }

    public init(source: Binding<String>, engine: any DiagramEngine) {
        self._source = source
        self.engine = engine
    }

    private var options: RenderOptions {
        RenderOptions(prefersDark: colorScheme == .dark)
    }

    private var templates: [SampleDiagram] {
        SampleDiagrams.all.filter { $0.format == engine.format }
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                onePane
            } else {
                twoPanes
            }
        }
        .toolbar {
            // Each item has a title and a symbol, so the system can pick the
            // representation when the bar runs down the side of a Duo.
            ToolbarItemGroup(placement: .primaryAction) {
                if !templates.isEmpty { templateMenu }
                exportMenu
            }
        }
        .task(id: RenderKey(source: source, options: options)) {
            await refresh()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportFile,
            contentType: exportFile?.contentType ?? .png,
            defaultFilename: "diagram"
        ) { _ in
            exportFile = nil
        }
        .alert("Nothing to export", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Fix the errors in the source, then try again.")
        }
    }

    // MARK: - Layouts

    /// Both panes at once.
    @ViewBuilder
    private var twoPanes: some View {
        // ArrangementView ships in the iOS 27.1 SDK only; the Mac, Vision Pro
        // and older iOS get the same shape-driven split without fold handling.
        #if os(iOS)
        if #available(iOS 27.1, *) {
            // The system picks the axis from the shape of the space and keeps
            // both panes clear of the fold on a partly open Duo.
            ArrangementView {
                codePane
            } secondary: {
                previewPane
            }
            .arrangementViewStyle(.split)
        } else {
            shapeDrivenSplit
        }
        #else
        shapeDrivenSplit
        #endif
    }

    /// Side by side when wider than tall, stacked when taller than wide.
    private var shapeDrivenSplit: some View {
        GeometryReader { proxy in
            if proxy.size.width >= proxy.size.height {
                HStack(spacing: 0) {
                    codePane.frame(width: proxy.size.width * 0.42)
                    Divider()
                    previewPane
                }
            } else {
                VStack(spacing: 0) {
                    previewPane
                    Divider()
                    codePane.frame(height: proxy.size.height * 0.42)
                }
            }
        }
    }

    /// One pane at a time, for compact width.
    private var onePane: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $pane) {
                ForEach(Pane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch pane {
            case .code: codePane
            case .preview: previewPane
            }
        }
    }

    private var codePane: some View {
        VStack(spacing: 0) {
            CodeEditorView(text: $source, format: engine.format, diagnostics: result.diagnostics)
            Divider()
            DiagnosticsList(diagnostics: result.diagnostics)
        }
    }

    private var previewPane: some View {
        // While the source is broken mid-edit, keep the last good render on
        // screen (dimmed) instead of flashing an empty state on every keystroke.
        let diagram = result.diagram ?? lastGood
        return DiagramCanvasView(
            diagram: diagram,
            isStale: result.diagram == nil && lastGood != nil)
            .background(previewBackground(for: diagram))
    }

    private func previewBackground(for diagram: RenderedDiagram?) -> Color {
        if let background = diagram?.background {
            return Color(cgColor: background)
        }
        return Color(white: colorScheme == .dark ? 0.11 : 1)
    }

    // MARK: - Rendering

    private func refresh() async {
        try? await Task.sleep(for: RenderPipeline.debounce)
        guard !Task.isCancelled else { return }
        let fresh = await RenderPipeline.run(source: source, engine: engine, options: options)
        guard !Task.isCancelled else { return }
        result = fresh
        if let diagram = fresh.diagram {
            lastGood = diagram
        }
    }

    // MARK: - Export

    private var exportMenu: some View {
        Menu {
            ForEach(ExportKind.allCases) { kind in
                Button("Export as \(kind.displayName)") { export(kind) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(result.diagram == nil)
    }

    private var templateMenu: some View {
        Menu {
            ForEach(templates) { template in
                Button(template.name) { apply(template) }
            }
        } label: {
            Label("Templates", systemImage: "square.on.square.dashed")
        }
        // Attached here so the dialog points at the button that raised it.
        .confirmationDialog(
            "Replace the current diagram?",
            isPresented: Binding(
                get: { pendingTemplate != nil },
                set: { if !$0 { pendingTemplate = nil } }),
            titleVisibility: .visible,
            presenting: pendingTemplate
        ) { template in
            Button("Replace with \(template.name)", role: .destructive) {
                source = template.source
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The source you have now will be replaced by the template.")
        }
    }

    /// Replaces the source with `template`, asking first if that would throw
    /// away something the user wrote.
    private func apply(_ template: SampleDiagram) {
        let current = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUntouched = current.isEmpty || SampleDiagrams.all.contains {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines) == current
        }
        if isUntouched {
            source = template.source
        } else {
            pendingTemplate = template
        }
    }

    private func export(_ kind: ExportKind) {
        guard let data = engine.export(source, as: kind, options: options) else {
            exportFailed = true
            return
        }
        exportFile = ExportedFile(data: data, kind: kind)
        isExporting = true
    }
}

// MARK: - Pieces

struct DiagnosticsList: View {
    let diagnostics: [Diagnostic]

    var body: some View {
        if diagnostics.isEmpty {
            Label("No problems", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diagnostics) { diagnostic in
                        Label(
                            diagnostic.summary,
                            systemImage: diagnostic.severity == .error
                                ? "xmark.octagon.fill" : "info.circle")
                            .font(.footnote)
                            .foregroundStyle(
                                diagnostic.severity == .error ? Color.red : Color.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 110)
        }
    }
}

/// Wraps export bytes so `fileExporter` can save them.
struct ExportedFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .pdf, .svg] }

    let data: Data
    let kind: ExportKind

    var contentType: UTType { kind.contentType }

    init(data: Data, kind: ExportKind) {
        self.data = data
        self.kind = kind
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        switch configuration.contentType {
        case .pdf: self.kind = .pdf
        case .svg: self.kind = .svg
        default: self.kind = .png
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension ExportKind {
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return .svg
        }
    }
}
#endif
