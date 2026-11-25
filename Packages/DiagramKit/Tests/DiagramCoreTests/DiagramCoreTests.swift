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

@Suite struct FormatDetectionTests {
    @Test func aWorkspaceIsStructurizrWhateverTheFallback() {
        #expect(DiagramFormat.detecting("workspace {\n}", fallback: .mermaid) == .structurizr)
        #expect(DiagramFormat.detecting("// c\n\n  Workspace \"X\" {", fallback: .mermaid) == .structurizr)
    }

    @Test func anythingElseIsMermaid() {
        #expect(DiagramFormat.detecting("flowchart TD\n A --> B", fallback: .structurizr) == .mermaid)
        #expect(DiagramFormat.detecting("%% note\nworkspaces --> x", fallback: .mermaid) == .mermaid)
    }

    @Test func emptySourceKeepsTheFallback() {
        #expect(DiagramFormat.detecting("", fallback: .structurizr) == .structurizr)
        #expect(DiagramFormat.detecting("\n// only a comment\n", fallback: .mermaid) == .mermaid)
    }
}

@Suite struct DiagramLibraryTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chartz-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Team"), withIntermediateDirectories: true)
        return folder
    }

    @Test func findsDiagramFilesInSubfoldersAndSortsByName() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try "flowchart TD\n A --> B".write(to: folder.appendingPathComponent("Diagram 10.mmd"), atomically: true, encoding: .utf8)
        try "flowchart TD\n A --> B".write(to: folder.appendingPathComponent("Diagram 2.MERMAID"), atomically: true, encoding: .utf8)
        try "workspace {\n}".write(to: folder.appendingPathComponent("Team/Bank.dsl"), atomically: true, encoding: .utf8)
        try "notes".write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try "flowchart TD".write(to: folder.appendingPathComponent(".hidden.mmd"), atomically: true, encoding: .utf8)
        try "   \n".write(to: folder.appendingPathComponent("Empty.mmd"), atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0xFD]).write(to: folder.appendingPathComponent("Binary.mmd"))

        let items = DiagramLibrary.items(inDirectory: folder)
        // Natural order: "Diagram 2" before "Diagram 10".
        #expect(items.map(\.name) == ["Bank", "Diagram 2", "Diagram 10"])
        #expect(items.map(\.format) == [.structurizr, .mermaid, .mermaid])
        #expect(items.allSatisfy { $0.modified != nil })
        #expect(Set(items.map(\.id)).count == 3)
    }

    @Test func theTextBeatsTheExtension() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Mislabelled.mmd")
        try "workspace {\n}".write(to: url, atomically: true, encoding: .utf8)
        #expect(DiagramLibrary.item(at: url)?.format == .structurizr)
    }

    @Test func aMissingFolderIsJustEmpty() {
        #expect(DiagramLibrary.items(inDirectory: URL(fileURLWithPath: "/nonexistent/chartz")).isEmpty)
    }

    @Test func samplesHaveStableDistinctIDs() {
        let ids = DiagramLibrary.sampleItems.map(\.id)
        #expect(Set(ids).count == SampleDiagrams.all.count)
        #expect(ids.allSatisfy { $0.hasPrefix("sample:") })
    }
}

@Suite struct PresentationDeckTests {
    private func item(_ name: String) -> LibraryDiagram {
        LibraryDiagram(id: name, name: name, format: .mermaid, source: "flowchart TD")
    }

    @Test func stepsWrapRoundInBothDirections() {
        var deck = PresentationDeck(items: [item("a"), item("b"), item("c")])
        deck.step(by: -1)
        #expect(deck.current?.id == "c")
        deck.step(by: 1)
        #expect(deck.current?.id == "a")
        #expect(deck.position == "1 of 3")
    }

    @Test func changingDiagramGoesBackToItsFirstView() {
        var deck = PresentationDeck(items: [item("a"), item("b")])
        deck.stepView(by: 1, count: 3)
        deck.stepView(by: 5, count: 3)
        #expect(deck.viewIndex == 2, "views stop at the end instead of wrapping")
        deck.stepView(by: -9, count: 3)
        #expect(deck.viewIndex == 0)
        deck.stepView(by: 1, count: 3)
        deck.step(by: 1)
        #expect(deck.viewIndex == 0)
        deck.stepView(by: 1, count: 3)
        deck.select("b")
        #expect(deck.viewIndex == 1, "selecting the diagram already showing keeps the view")
        deck.stepView(by: 1, count: 0)
        #expect(deck.viewIndex == 0)
    }

    @Test func aRefreshKeepsTheAudienceOnTheSameDiagram() {
        var deck = PresentationDeck(items: [item("a"), item("b"), item("c")])
        deck.select("c")
        deck.replaceItems([item("new"), item("c"), item("a")])
        #expect(deck.current?.id == "c")
        // The diagram on screen was deleted elsewhere: stay in range.
        deck.replaceItems([item("x")])
        #expect(deck.current?.id == "x")
        deck.replaceItems([])
        #expect(deck.current == nil)
        #expect(deck.position == nil)
        deck.step(by: 1)
        #expect(deck.current == nil)
    }

    @Test func selectingAnUnknownDiagramChangesNothing() {
        var deck = PresentationDeck(items: [item("a"), item("b")])
        deck.select("b")
        deck.select("ghost")
        #expect(deck.current?.id == "b")
    }
}
