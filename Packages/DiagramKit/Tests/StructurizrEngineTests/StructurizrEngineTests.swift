import DiagramCore
import Foundation
import Testing
@testable import StructurizrEngine

private let bank = """
workspace "Bank" {
    !identifiers flat
    model {
        customer = person "Customer" "Has accounts"
        group "Bank" {
            banking = softwareSystem "Internet Banking" "Lets customers see accounts" {
                web = container "Web App" "Serves pages" "Java"
                api = container "API" "JSON over HTTPS" "Java" {
                    auth = component "Sign In" "Checks passwords" "Spring"
                }
                db = container "Database" "Accounts" "Oracle" "Database"
            }
        }
        mainframe = softwareSystem "Mainframe" "Core banking" "External"
        email = softwareSystem "E-mail" "Sends mail" {
            tags "External"
        }
        unused = softwareSystem "Unused" "Nobody talks to it"

        customer -> web "Visits" "HTTPS"
        web -> api "Calls"
        api -> db "Reads from"
        auth -> mainframe "Checks with"
        banking -> email "Sends mail using"
        email -> customer "Sends mail to"
    }
    views {
        systemLandscape "Landscape" { include * }
        systemContext banking "Context" {
            include *
            autoLayout lr
        }
        container banking {
            title "Inside the bank"
        }
        styles {
            element "Person" { shape person }
        }
    }
}
"""

@Suite struct StructurizrParserTests {
    @Test func readsElementsWithTheirOwners() {
        let workspace = StructurizrParser.parse(bank).workspace
        #expect(workspace.name == "Bank")
        #expect(workspace.elements.map(\.id) == [
            "customer", "banking", "web", "api", "auth", "db", "mainframe", "email", "unused",
        ])
        #expect(workspace.element("banking")?.parent == nil, "a group does not own its children")
        #expect(workspace.element("api")?.parent == "banking")
        #expect(workspace.element("auth")?.parent == "api")
        #expect(workspace.topLevel(of: "auth")?.id == "banking")
        #expect(workspace.container(of: "auth")?.id == "api")
        #expect(workspace.container(of: "banking") == nil)
    }

    @Test func readsDescriptionsTechnologyAndTags() {
        let workspace = StructurizrParser.parse(bank).workspace
        #expect(workspace.element("customer")?.description == "Has accounts")
        #expect(workspace.element("web")?.technology == "Java")
        #expect(workspace.element("db")?.isDatabase == true)
        #expect(workspace.element("mainframe")?.isExternal == true, "tags as a positional argument")
        #expect(workspace.element("email")?.isExternal == true, "tags in the element's block")
        #expect(workspace.element("banking")?.isExternal == false)
    }

    @Test func readsRelationshipsAndViews() {
        let workspace = StructurizrParser.parse(bank).workspace
        #expect(workspace.relationships.count == 6)
        #expect(workspace.relationships.first?.technology == "HTTPS")
        #expect(workspace.views.map(\.kind) == [.systemLandscape, .systemContext, .container])
        #expect(workspace.views.map(\.key) == ["Landscape", "Context", nil])
        #expect(workspace.views[2].title == "Inside the bank")
    }

    @Test func aCleanWorkspaceOnlyNotesWhatItSkipped() {
        let diagnostics = StructurizrParser.parse(bank).diagnostics
        #expect(!diagnostics.containsError)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("Styles") == true)
    }

    @Test func commentsAreIgnored() {
        let source = """
        // leading comment
        workspace {
            /* a block
               comment */
            model {
                a = person "A" // trailing
                # hash comment
                b = softwareSystem "B" /* inline */ "Desc"
                a -> b "Uses http://example.com"
            }
        }
        """
        let parsed = StructurizrParser.parse(source)
        #expect(!parsed.diagnostics.containsError)
        #expect(parsed.workspace.elements.count == 2)
        #expect(parsed.workspace.element("b")?.description == "Desc")
        #expect(parsed.workspace.relationships.first?.description == "Uses http://example.com")
    }

    @Test func oneLineBlocksAndImplicitSources() {
        let source = """
        workspace {
            model {
                a = person "A" { tags "External" }
                s = softwareSystem "S" {
                    -> a "Notifies"
                }
            }
        }
        """
        let parsed = StructurizrParser.parse(source)
        #expect(!parsed.diagnostics.containsError)
        #expect(parsed.workspace.element("a")?.isExternal == true)
        #expect(parsed.workspace.relationships == [
            C4Relationship(source: "s", destination: "a", description: "Notifies", technology: nil, line: 5),
        ])
    }

    @Test func aModelWithoutViewsGetsALandscape() {
        let parsed = StructurizrParser.parse("workspace {\n model {\n a = person \"A\"\n }\n}")
        #expect(parsed.workspace.views.map(\.kind) == [.systemLandscape])
        #expect(parsed.diagnostics.map(\.severity) == [.note])
    }

    @Test(arguments: [
        ("model {\n}", 1 as Int?, "workspace"),
        ("workspace {\n model {\n a = person \"A\"\n", 4, "Missing '}'"),
        ("workspace {\n}\n}", 3, "Unexpected '}'"),
        ("workspace {\n model {\n a = person \"A\"\n a -> ghost \"Uses\"\n }\n}", 4, "ghost"),
        ("workspace {\n model {\n a = person \"A\"\n a = person \"B\"\n }\n}", 4, "already used"),
        ("workspace {\n model {\n c = container \"C\"\n }\n}", 3, "inside a softwareSystem"),
        ("workspace {\n model {\n a = person\n }\n}", 3, "needs a name"),
        ("workspace {\n model {\n a = person \"A\"\n }\n views {\n systemContext a {\n }\n }\n}", 6, "softwareSystem"),
        ("workspace {\n model {\n a = person \"A\"\n }\n views {\n container nope {\n }\n }\n}", 6, "nope"),
    ])
    func reportsErrorsOnTheRightLine(source: String, line: Int?, fragment: String) {
        let errors = StructurizrParser.parse(source).diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains(fragment) && $0.line == line },
                "wanted '\(fragment)' on line \(String(describing: line)), got \(errors.map(\.summary))")
    }

    @Test func halfTypedSourceNeverCrashes() {
        // Every prefix of a real workspace is something the editor will show
        // the parser while the user is typing.
        for end in bank.indices {
            _ = StructurizrParser.parse(String(bank[..<end]))
        }
    }
}

@Suite struct C4LoweringTests {
    private let workspace = StructurizrParser.parse(bank).workspace

    private func scene(_ index: Int) -> C4Lowering.Scene {
        C4Lowering.scene(for: workspace.views[index], in: workspace)
    }

    @Test func landscapeShowsEveryPersonAndSystem() {
        let scene = scene(0)
        #expect(scene.outside.map(\.id) == ["customer", "banking", "mainframe", "email", "unused"])
        #expect(scene.inside.isEmpty)
    }

    @Test func contextShowsTheSystemAndItsNeighbours() {
        let scene = scene(1)
        #expect(scene.outside.map(\.id) == ["customer", "banking", "mainframe", "email"])
        // Container-level relationships are lifted to the system; ones wholly
        // inside it disappear.
        let pairs = scene.relations.map { "\($0.source)>\($0.destination)" }
        #expect(pairs == ["customer>banking", "banking>mainframe", "banking>email", "email>customer"])
    }

    @Test func containerViewPutsContainersInsideAndNeighboursOutside() {
        let scene = scene(2)
        #expect(scene.inside.map(\.id) == ["web", "api", "db"])
        #expect(scene.outside.map(\.id) == ["customer", "mainframe"])
        let pairs = scene.relations.map { "\($0.source)>\($0.destination)" }
        // The component's relationship is drawn from its container; the
        // system-level "banking -> email" has no container end, so it is not
        // in this view, and neither is e-mail.
        #expect(pairs == ["customer>web", "web>api", "api>db", "api>mainframe"])
    }

    @Test func includeAndExcludeNarrowAView() {
        var view = workspace.views[1]
        view.excludes = ["mainframe"]
        #expect(C4Lowering.scene(for: view, in: workspace).outside.map(\.id) == ["customer", "banking", "email"])
        view.excludes = []
        view.includes = ["customer"]
        let scene = C4Lowering.scene(for: view, in: workspace)
        #expect(scene.outside.map(\.id) == ["customer", "banking"])
        #expect(scene.relations.count == 1)
    }

    @Test func writesMermaidC4() throws {
        let context = try #require(C4Lowering.mermaid(for: workspace.views[1], in: workspace))
        #expect(context.hasPrefix("C4Context\n    title System Context: Internet Banking\n"))
        #expect(context.contains("Person(customer, \"Customer\", \"Has accounts\")"))
        #expect(context.contains("System(banking, \"Internet Banking\""))
        #expect(context.contains("System_Ext(mainframe, \"Mainframe\""))
        #expect(context.contains("Rel(customer, banking, \"Visits\", \"HTTPS\")"))

        let containers = try #require(C4Lowering.mermaid(for: workspace.views[2], in: workspace))
        #expect(containers.hasPrefix("C4Container\n    title Inside the bank\n"))
        #expect(containers.contains("System_Boundary(banking_boundary, \"Internet Banking\") {"))
        #expect(containers.contains("ContainerDb(db, \"Database\", \"Oracle\", \"Accounts\")"))
        #expect(containers.contains("Container(web, \"Web App\", \"Java\", \"Serves pages\")"))
    }

    @Test func textIsMadeSafeForMermaid() throws {
        let source = "workspace {\n model {\n my.sys-1 = softwareSystem \"Say \\\"hi\\\"\" \"x\"\n }\n}"
        let parsed = StructurizrParser.parse(source)
        let mermaid = try #require(C4Lowering.mermaid(for: parsed.workspace.views[0], in: parsed.workspace))
        #expect(mermaid.contains("System(my_sys_1, \"Say 'hi'\", \"x\")"))
    }

    @Test func anEmptyViewLowersToNothing() {
        let parsed = StructurizrParser.parse("workspace {\n model {\n s = softwareSystem \"S\"\n }\n views {\n container s {\n }\n }\n}")
        #expect(C4Lowering.mermaid(for: parsed.workspace.views[0], in: parsed.workspace) == nil)
    }
}

@Suite struct StructurizrEngineTests {
    private let engine = StructurizrDiagramEngine()

    @Test func listsViewsWithStableIDs() {
        #expect(engine.views(in: bank) == [
            DiagramViewInfo(id: "Landscape", name: "System Landscape: Bank"),
            DiagramViewInfo(id: "Context", name: "System Context: Internet Banking"),
            DiagramViewInfo(id: "view-3", name: "Inside the bank"),
        ])
    }

    @Test func rendersEveryViewThroughTheRealRenderer() {
        var sources = Set<String>()
        for view in engine.views(in: bank) {
            let diagram = engine.render(bank, options: RenderOptions(view: view.id))
            #expect(diagram != nil, "\(view.name) did not render")
            #expect((diagram?.size.width ?? 0) > 100)
            if let source = engine.mermaidSource(bank, view: view.id) { sources.insert(source) }
        }
        #expect(sources.count == 3, "each view should lower to different source")
    }

    @Test func anUnknownViewFallsBackToTheFirst() {
        #expect(engine.mermaidSource(bank, view: "gone") == engine.mermaidSource(bank, view: "Landscape"))
        #expect(engine.mermaidSource(bank, view: nil) == engine.mermaidSource(bank, view: "Landscape"))
    }

    @Test func brokenSourceRendersNothingAndListsNoViews() {
        let broken = "workspace {\n model {\n a -> b\n }\n}"
        #expect(engine.render(broken, options: RenderOptions()) == nil)
        #expect(engine.views(in: broken).isEmpty)
        #expect(engine.diagnose(broken).containsError)
    }

    @Test func theBuiltInSampleIsCleanAndExports() throws {
        let sample = SampleDiagrams.structurizr.source
        #expect(engine.diagnose(sample).isEmpty)
        #expect(engine.views(in: sample).map(\.id) == ["Context", "Containers"])
        let svg = try #require(engine.export(sample, as: .svg, options: RenderOptions(view: "Containers")))
        let text = String(decoding: svg, as: UTF8.self)
        #expect(text.contains("Editor UI"))
        #expect(text.contains("iCloud Drive"))
    }
}
