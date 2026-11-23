import Testing
@testable import DiagramCore

@Suite struct DiagramFormatTests {
    @Test func extensionMapsToFormat() {
        #expect(DiagramFormat(fileExtension: "mmd") == .mermaid)
        #expect(DiagramFormat(fileExtension: "MERMAID") == .mermaid)
        #expect(DiagramFormat(fileExtension: "dsl") == .structurizr)
        #expect(DiagramFormat(fileExtension: "txt") == .mermaid)
    }

    @Test func everyFormatHasAnExtension() {
        for format in DiagramFormat.allCases {
            #expect(!format.fileExtension.isEmpty)
            #expect(DiagramFormat(fileExtension: format.fileExtension) == format)
        }
    }
}

@Suite struct DiagnosticTests {
    @Test func summaryIncludesTheLineWhenThereIsOne() {
        let withLine = Diagnostic(severity: .error, line: 3, message: "unknown diagram type")
        let wholeFile = Diagnostic(severity: .error, line: nil, message: "source is empty")
        #expect(withLine.summary == "Line 3: unknown diagram type")
        #expect(wholeFile.summary == "source is empty")
    }

    @Test func equalityIgnoresIdentity() {
        let a = Diagnostic(severity: .note, line: 1, message: "skipped")
        let b = Diagnostic(severity: .note, line: 1, message: "skipped")
        #expect(a == b)
        #expect(a.id != b.id)
    }

    @Test func containsErrorOnlyCountsErrors() {
        let note = Diagnostic(severity: .note, line: nil, message: "n")
        let error = Diagnostic(severity: .error, line: nil, message: "e")
        #expect(![note].containsError)
        #expect([note, error].containsError)
    }
}

@Suite struct SampleDiagramTests {
    @Test func samplesHaveUniqueNamesAndSource() {
        let names = SampleDiagrams.all.map(\.name)
        #expect(Set(names).count == names.count)
        for sample in SampleDiagrams.all {
            #expect(!sample.source.isEmpty)
        }
    }
}
