import CoreGraphics
import DiagramCore
import Testing
@testable import MermaidEngine

@Suite struct MermaidEngineTests {
    let engine = MermaidDiagramEngine()

    @Test(arguments: SampleDiagrams.all.filter { $0.format == .mermaid })
    func everyTemplateRendersCleanly(_ sample: SampleDiagram) {
        #expect(engine.diagnose(sample.source).isEmpty, "\(sample.name) has diagnostics")
        let diagram = engine.render(sample.source, options: RenderOptions())
        #expect(diagram != nil, "\(sample.name) did not render")
        #expect((diagram?.size.width ?? 0) > 0)
    }

    @Test func drawingPutsInkOnTheCanvas() throws {
        let diagram = try #require(engine.render(SampleDiagrams.flowchart.source, options: RenderOptions()))
        let width = Int(diagram.size.width.rounded(.up)), height = Int(diagram.size.height.rounded(.up))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Bitmap contexts are y-up; the engine draws y-down.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        diagram.draw(in: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var painted = 0
        for index in stride(from: 3, to: width * height * 4, by: 4) where pixels[index] != 0 {
            painted += 1
        }
        // The background is left clear, so anything opaque is diagram ink.
        #expect(painted > 500)
        #expect(painted < width * height)
    }

    @Test func unparseableSourceDoesNotRender() {
        #expect(engine.render("this is not a diagram", options: RenderOptions()) == nil)
    }

    @Test(arguments: ExportKind.allCases)
    func exportsEveryKind(_ kind: ExportKind) throws {
        let data = try #require(engine.export(SampleDiagrams.flowchart.source, as: kind, options: RenderOptions()))
        switch kind {
        case .png: #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        case .pdf: #expect(data.starts(with: Array("%PDF".utf8)))
        case .svg: #expect(String(decoding: data, as: UTF8.self).contains("<svg"))
        }
    }
}
