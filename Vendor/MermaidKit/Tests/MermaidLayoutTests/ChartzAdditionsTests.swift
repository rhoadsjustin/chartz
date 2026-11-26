import CoreGraphics
import XCTest
@testable import MermaidLayout

/// Tests for what Chartz added to the vendored renderer (see VENDORED.md):
/// C4 boundary frames and flowchart node styling.
final class ChartzAdditionsTests: XCTestCase {
    private let measure: DiagramTextMeasurer = { text, size in
        CGSize(width: CGFloat(text.count) * CGFloat(size) * 0.55, height: CGFloat(size) * 1.2)
    }

    private func c4(_ source: String) throws -> C4Diagram {
        guard case .c4(let diagram)? = MermaidParser.parse(source) else {
            XCTFail("not a C4 diagram")
            throw CancellationError()
        }
        return diagram
    }

    private func flowchart(_ source: String) throws -> Flowchart {
        guard case .flowchart(let chart)? = MermaidParser.parse(source) else {
            XCTFail("not a flowchart")
            throw CancellationError()
        }
        return chart
    }

    // MARK: - C4 boundaries

    private let bank = """
    C4Container
        Person(customer, "Customer", "Has accounts")
        System_Ext(mainframe, "Mainframe", "Core banking")
        System_Ext(email, "E-mail", "Sends mail")
        System_Boundary(bank, "Internet Banking") {
            Container(web, "Web App", "Java", "Serves pages")
            Container(api, "API", "Java", "JSON over HTTPS")
            ContainerDb(db, "Database", "Oracle", "Accounts")
        }
        Rel(customer, web, "Visits")
        Rel(web, api, "Calls")
        Rel(api, db, "Reads from")
        Rel(api, mainframe, "Checks with")
        Rel(api, email, "Sends mail using")
    """

    func testParserKeepsBoundariesAndMembership() throws {
        let diagram = try c4(bank)
        XCTAssertEqual(diagram.boundaries.map(\.alias), ["bank"])
        XCTAssertEqual(diagram.boundaries.first?.label, "Internet Banking")
        XCTAssertEqual(diagram.boundaries.first?.kind, "System")
        let inside = diagram.elements.filter { $0.boundary == "bank" }.map(\.alias)
        XCTAssertEqual(inside, ["web", "api", "db"])
        XCTAssertNil(diagram.elements.first { $0.alias == "customer" }?.boundary)
    }

    func testNestedBoundariesRecordTheirParents() throws {
        let diagram = try c4("""
        C4Container
            Enterprise_Boundary(ent, "Big Bank") {
                System(crm, "CRM", "Customers")
                System_Boundary(sb, "Banking") {
                    Container(web, "Web", "Java", "Pages")
                }
                Boundary(empty, "Nothing in here") {
                }
            }
            Person(user, "User", "Outside")
        """)
        XCTAssertEqual(diagram.boundaries.map(\.alias), ["ent", "sb"], "an empty boundary is dropped")
        XCTAssertEqual(diagram.boundaries.map(\.parent), [nil, "ent"])
        XCTAssertEqual(diagram.elements.map(\.boundary), ["ent", "sb", nil])
    }

    func testFrameHoldsItsMembersAndNothingElse() throws {
        let diagram = try c4(bank)
        let layout = DiagramLayoutEngine.layout(diagram, measure: measure)
        XCTAssertEqual(layout.frames.count, 1)
        let frame = try XCTUnwrap(layout.frames.first)
        for (element, box) in zip(diagram.elements, layout.boxes) {
            if element.boundary == "bank" {
                XCTAssertTrue(frame.rect.contains(box.frame), "\(element.alias) should be inside the frame")
            } else {
                XCTAssertFalse(frame.rect.intersects(box.frame), "\(element.alias) should be outside the frame")
            }
        }
        XCTAssertTrue(frame.caption.hasPrefix("Internet Banking"))
        XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(frame.rect))
    }

    func testNoTwoBoxesOverlapWhenBoundariesMoveThings() throws {
        let layout = DiagramLayoutEngine.layout(try c4(bank), measure: measure)
        for (i, a) in layout.boxes.enumerated() {
            for b in layout.boxes.dropFirst(i + 1) {
                XCTAssertFalse(a.frame.intersects(b.frame))
            }
        }
    }

    func testSiblingBoundariesGetSeparateFrames() throws {
        let layout = DiagramLayoutEngine.layout(try c4("""
        C4Container
            Person(user, "User", "Shops")
            System_Boundary(a, "Shop") {
                Container(web, "Web", "TS", "Storefront")
                Container(cart, "Cart", "Go", "Baskets")
            }
            System_Boundary(b, "Payments") {
                Container(pay, "Pay API", "Go", "Charges cards")
            }
            Rel(user, web, "Shops")
            Rel(web, cart, "Adds to")
            Rel(cart, pay, "Checks out")
        """), measure: measure)
        XCTAssertEqual(layout.frames.count, 2)
        XCTAssertFalse(layout.frames[0].rect.intersects(layout.frames[1].rect))
    }

    func testNestedFrameSitsInsideItsParent() throws {
        let layout = DiagramLayoutEngine.layout(try c4("""
        C4Container
            Person(user, "User", "Uses it")
            Enterprise_Boundary(ent, "Big Bank") {
                System(crm, "CRM", "Customers")
                System_Boundary(sb, "Internet Banking") {
                    Container(web, "Web App", "Java", "Serves pages")
                    Container(api, "API", "Java", "JSON")
                }
            }
            Rel(user, web, "Visits")
            Rel(web, api, "Calls")
            Rel(api, crm, "Looks up")
        """), measure: measure)
        XCTAssertEqual(layout.frames.map(\.depth), [0, 1])
        XCTAssertTrue(layout.frames[0].rect.contains(layout.frames[1].rect))
    }

    func testADiagramWithoutBoundariesHasNoFrames() throws {
        let layout = DiagramLayoutEngine.layout(try c4("""
        C4Context
            Person(a, "A", "x")
            System(b, "B", "y")
            Rel(a, b, "Uses")
        """), measure: measure)
        XCTAssertTrue(layout.frames.isEmpty)
    }

    func testFramesReachTheSVGScene() throws {
        let layout = DiagramLayoutEngine.layout(try c4(bank), measure: measure)
        let ink = DiagramColor(hex: 0x111111)
        let theme = RenderTheme(ink: ink, accent: ink, canvas: DiagramColor(hex: 0xFFFFFF), hairline: ink,
                                secondaryText: ink, tertiaryText: ink, palette: [ink], prefersDark: false)
        let svg = SVGRenderer.svg(RenderScene.from(layout, theme: theme, measure: measure))
        XCTAssertTrue(svg.contains("Internet Banking"))
    }

    // MARK: - Flowchart node styling

    func testClassDefClassAndInlineClassesResolve() throws {
        let chart = try flowchart("""
        flowchart TD
            A[Start]:::hot --> B[Middle]
            B --> C[End]
            classDef hot fill:#ff0000,stroke:#330000,stroke-width:3px
            classDef cool fill:#00f
            class B,C cool
        """)
        XCTAssertEqual(chart.nodeStyles["A"]?.fill, DiagramColor(hex: 0xFF0000))
        XCTAssertEqual(chart.nodeStyles["A"]?.stroke, DiagramColor(hex: 0x330000))
        XCTAssertEqual(chart.nodeStyles["A"]?.strokeWidth, 3)
        XCTAssertEqual(chart.nodeStyles["B"]?.fill, DiagramColor(hex: 0x0000FF))
        XCTAssertEqual(chart.nodeStyles["C"]?.fill, DiagramColor(hex: 0x0000FF))
        XCTAssertEqual(chart.nodes.map(\.label), ["Start", "Middle", "End"], "styling never changes the nodes")
    }

    func testLaterLayersWin() throws {
        let chart = try flowchart("""
        flowchart TD
            A:::one --> B
            style A fill:#000000
            classDef default stroke:#111111,fill:#222222
            classDef one fill:#333333,color:white
        """)
        // default < class < style.
        XCTAssertEqual(chart.nodeStyles["A"]?.fill, DiagramColor(hex: 0x000000))
        XCTAssertEqual(chart.nodeStyles["A"]?.stroke, DiagramColor(hex: 0x111111))
        XCTAssertEqual(chart.nodeStyles["A"]?.text, DiagramColor(hex: 0xFFFFFF))
        XCTAssertEqual(chart.nodeStyles["B"]?.fill, DiagramColor(hex: 0x222222))
    }

    func testAnUnstyledChartCarriesNoStyles() throws {
        let chart = try flowchart("flowchart TD\n A --> B\n class A ghost")
        XCTAssertTrue(chart.nodeStyles.isEmpty, "a class nobody defined styles nothing")
    }

    func testStylesTravelWithTheLayout() throws {
        let chart = try flowchart("flowchart LR\n A --> B\n style B fill:#abcdef")
        let layout = DiagramLayoutEngine.layout(chart, measure: measure)
        XCTAssertEqual(layout.nodeStyles["B"]?.fill, DiagramColor(hex: 0xABCDEF))
        // Styling must not move anything.
        var plain = chart
        plain.nodeStyles = [:]
        let unstyled = DiagramLayoutEngine.layout(plain, measure: measure)
        XCTAssertEqual(layout.nodes.map(\.frame), unstyled.nodes.map(\.frame))
        XCTAssertEqual(layout.size, unstyled.size)
    }

    func testStyleListParsing() {
        let style = Flowchart.NodeStyle(css: " fill: rgb(255, 0, 128) , stroke:#abc; stroke-width: 2.5px,stroke-dasharray: 5 5, font-weight:bold, color:nonsense")
        XCTAssertEqual(style.fill, DiagramColor(red: 1, green: 0, blue: 128.0 / 255))
        XCTAssertEqual(style.stroke, DiagramColor(hex: 0xAABBCC))
        XCTAssertEqual(style.strokeWidth, 2.5)
        XCTAssertEqual(style.dashed, true)
        XCTAssertNil(style.text, "an unreadable colour is skipped, not guessed")
        XCTAssertEqual(Flowchart.NodeStyle(css: "stroke-dasharray:none").dashed, false)
        XCTAssertTrue(Flowchart.NodeStyle(css: "").isEmpty)
    }

    func testCSSColours() {
        XCTAssertEqual(DiagramColor(css: "#F00"), DiagramColor(hex: 0xFF0000))
        XCTAssertEqual(DiagramColor(css: "#ff000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(DiagramColor(css: "rgba(0, 0, 255, 0.5)"), DiagramColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        XCTAssertEqual(DiagramColor(css: " SteelBlue "), DiagramColor(hex: 0x4682B4))
        XCTAssertEqual(DiagramColor(css: "transparent")?.alpha, 0)
        XCTAssertNil(DiagramColor(css: "#12"))
        XCTAssertNil(DiagramColor(css: "#gggggg"))
        XCTAssertNil(DiagramColor(css: "rgb(1,2)"))
        XCTAssertNil(DiagramColor(css: "notacolour"))
    }

    func testLabelColourContrastsWithAFillThatHasNoTextColour() {
        let ink = DiagramColor(hex: 0xEEEEEE)
        XCTAssertEqual(Flowchart.NodeStyle(fill: DiagramColor(hex: 0xFFFFCC)).labelColor(default: ink),
                       DiagramColor(hex: 0x1A1A1A))
        XCTAssertEqual(Flowchart.NodeStyle(fill: DiagramColor(hex: 0x102040)).labelColor(default: ink),
                       DiagramColor(hex: 0xFFFFFF))
        XCTAssertEqual(Flowchart.NodeStyle(stroke: DiagramColor(hex: 0x102040)).labelColor(default: ink), ink)
        let declared = DiagramColor(hex: 0x00FF00)
        XCTAssertEqual(Flowchart.NodeStyle(fill: DiagramColor(hex: 0x000000), text: declared)
            .labelColor(default: ink), declared)
    }
}
