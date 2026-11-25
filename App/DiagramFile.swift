#if !os(tvOS)
import DiagramCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.mmd` / `.mermaid`. Declared under UTExportedTypeDeclarations in project.yml.
    static let mermaidDiagram = UTType(
        exportedAs: "com.example.chartz.mermaid", conformingTo: .plainText)

    /// `.dsl`. Declared under UTImportedTypeDeclarations in project.yml.
    static let structurizrDSL = UTType(
        importedAs: "com.example.chartz.structurizr", conformingTo: .plainText)
}

/// A diagram on disk: plain text, so files diff cleanly and can live in a repo.
struct DiagramFile: FileDocument {
    // The first type is what "New Document" creates.
    static var readableContentTypes: [UTType] { [.mermaidDiagram, .structurizrDSL, .plainText] }

    var source: String
    var format: DiagramFormat

    init(source: String = SampleDiagrams.starter, format: DiagramFormat = .mermaid) {
        self.source = source
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.source = text
        self.format = configuration.contentType == .structurizrDSL ? .structurizr : .mermaid
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}
#endif
