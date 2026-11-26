# Vendored MermaidKit

This is our copy of [MermaidKit](https://github.com/2389-research/MermaidKit),
taken from upstream commit `8556a1b80a1f624d35a4c6e13dcb7a5d427f65c3`
(30 Oct 2026). MIT licensed; see `LICENSE` in this folder, which must stay.

We own this code now and change it freely. It is not a submodule.

## What was kept

`Package.swift`, `Sources/`, `Tests/`, `Fixtures/`, `README.md`,
`CHANGELOG.md`, `LICENSE`.

Left out: the Android, Flutter and Windows bindings, docs, assets, scratchpad,
tools, scripts and CI config. Some tests may refer to files that were left
out; delete or fix those tests as they come up.

## Changes from upstream

- `Package.swift`: added `.tvOS(.v17)` to `platforms`. Builds for the tvOS
  simulator; not yet run there.
- `Sources/MermaidRender/MermaidRenderer+Vector.swift` (new file): public
  `VectorDiagram` and `MermaidRenderer.vectorDiagram(source:theme:spacing:)`.
  Exposes the internal layout-and-draw plan the raster and PDF paths already
  share, so the app can redraw at any zoom level. No upstream file was edited.
- **C4 boundary frames.** Upstream flattened boundaries.
  - `MermaidParser+C4.swift`: `C4Diagram.Boundary`, `C4Diagram.boundaries`,
    `Element.boundary`; the parser tracks open `…Boundary(…) {` / `Node(…) {`
    blocks instead of skipping them.
  - `DiagramLayoutC4.swift`: `C4Layout.Frame` and `C4Layout.frames`; a block
    of columns per outermost boundary, extra row spacing for frame captions.
    The no-boundary path is unchanged.
  - `DiagramRenderer+C4.swift`, `RenderScene+C4.swift`: draw the frames.
  - `DiagramScene+C4.swift`: frames are container nodes for the linter.
- **Flowchart node styling.** Upstream read and discarded it.
  - `FlowchartStyle.swift` (new): `Flowchart.NodeStyle`, CSS colour parsing.
  - `MermaidModels.swift`: `Flowchart.Node.styleClasses`,
    `Flowchart.nodeStyles`.
  - `MermaidParser.swift`: `classDef`, `class`, `:::` and `style` are
    collected and resolved into `nodeStyles`. `linkStyle` is still ignored.
  - `DiagramLayout.swift`, `DiagramLayoutFlowchart.swift`,
    `GridQuantizer.swift`: `FlowchartLayout.nodeStyles` carried alongside the
    geometry.
  - `DiagramRenderer+Flowchart.swift`, `RenderScene+Flowchart.swift`,
    `DiagramRenderer+GraphShared.swift`: apply it when drawing nodes.
- `Tests/MermaidLayoutTests/ChartzAdditionsTests.swift` (new): tests for the
  two additions above.
- `Tests/MermaidLayoutTests/CaptionPlacementEquivalenceTests.swift`: the
  oracle cases in upstream's `tools/` folder (not vendored) are now optional.

Add a line here for every change, so pulling in an upstream fix later is a
matter of reading this list.
