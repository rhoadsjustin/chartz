#if !os(tvOS)
import DiagramCore
import SwiftUI
import UniformTypeIdentifiers

/// The editor: source on one side, live preview on the other.
///
/// Layout follows the width it is given rather than the device, so one view
/// covers a folded phone (tabs), an unfolded Duo, an iPad in Split View, a
/// resized Mac window and a Vision Pro window (side by side).
public struct DiagramEditorView: View {
    @Binding private var source: String
    private let engine: any DiagramEngine

    @Environment(\.colorScheme) private var colorScheme
    @State private var result = RenderResult()
    @State private var lastGood: RenderedDiagram?
    @State private var pane: Pane = .code
    @State private var exportFile: ExportedFile?
    @State private var isExporting = false
    @State private var exportFailed = false

    /// Narrower than this, the panes become tabs.
    private static let splitThreshold: CGFloat = 640

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

    public var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.splitThreshold {
                sideBySide(width: proxy.size.width)
            } else {
                stacked
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { exportMenu }
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

    private func sideBySide(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            codePane
                .frame(width: max(280, width * 0.42))
            Divider()
            previewPane
        }
    }

    private var stacked: some View {
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
            CodeEditorView(text: $source)
            Divider()
            DiagnosticsList(diagnostics: result.diagnostics)
        }
    }

    private var previewPane: some View {
        // While the source is broken mid-edit, keep the last good render on
        // screen (dimmed) instead of flashing an empty state on every keystroke.
        DiagramCanvasView(
            diagram: result.diagram ?? lastGood,
            isStale: result.diagram == nil && lastGood != nil)
            .background(Color(white: colorScheme == .dark ? 0.11 : 1))
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

/// Plain monospaced text editing. Milestone 2 swaps this for a
/// TextKit-backed editor with syntax highlighting and line numbers.
struct CodeEditorView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            #if os(iOS) || os(visionOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            #endif
    }
}

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
