import Foundation
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

@Suite struct SourceHighlighterTests {
    private func kinds(_ source: String, _ format: DiagramFormat = .mermaid) -> [String: SourceToken.Kind] {
        var result: [String: SourceToken.Kind] = [:]
        for token in SourceHighlighter.tokens(in: source, format: format) {
            result[(source as NSString).substring(with: token.range)] = token.kind
        }
        return result
    }

    @Test func findsKeywordsArrowsAndStrings() {
        let found = kinds("flowchart TD\n    A[\"Start here\"] --> B\n    B -.-> C")
        #expect(found["flowchart"] == .keyword)
        #expect(found["TD"] == .keyword)
        #expect(found["\"Start here\""] == .string)
        #expect(found["-->"] == .arrow)
        #expect(found["-.->"] == .arrow)
    }

    @Test func commentsSwallowWhatIsInsideThem() {
        let tokens = SourceHighlighter.tokens(in: "%% graph --> end\nA --> B", format: .mermaid)
        #expect(tokens.count == 2)
        #expect(tokens.first?.kind == .comment)
        #expect(tokens.last?.kind == .arrow)
    }

    @Test func longestKeywordWins() {
        #expect(kinds("stateDiagram-v2")["stateDiagram-v2"] == .keyword)
    }

    @Test func keywordsInsideIdentifiersAreLeftAlone() {
        #expect(kinds("backend --> frontend").keys.sorted() == ["-->"])
    }

    @Test func tokensNeverOverlapAndStayInOrder() {
        let source = SampleDiagrams.all.map(\.source).joined(separator: "\n")
        var cursor = 0
        for token in SourceHighlighter.tokens(in: source, format: .mermaid) {
            #expect(token.range.location >= cursor)
            cursor = NSMaxRange(token.range)
        }
        #expect(cursor <= (source as NSString).length)
    }

    @Test func structurizrHasItsOwnRules() {
        let found = kinds("workspace {\n  // note\n  a -> b \"Uses\"\n}", .structurizr)
        #expect(found["workspace"] == .keyword)
        #expect(found["// note"] == .comment)
        #expect(found["->"] == .arrow)
        #expect(found["\"Uses\""] == .string)
    }
}

@Suite struct SourceEditingTests {
    @Test func returnKeepsTheIndentOfTheCurrentLine() {
        let text = "flowchart TD\n    A --> B"
        #expect(SourceEditing.newline(in: text, at: (text as NSString).length) == "\n    ")
        #expect(SourceEditing.newline(in: text, at: 5) == "\n")
    }

    @Test func returnInsideTheIndentOnlyKeepsWhatIsBeforeTheCaret() {
        #expect(SourceEditing.newline(in: "        A", at: 2) == "\n  ")
    }

    @Test func returnCopesWithEmptyAndOutOfRangeInput() {
        #expect(SourceEditing.newline(in: "", at: 0) == "\n")
        #expect(SourceEditing.newline(in: "\tA", at: 99) == "\n\t")
    }
}
