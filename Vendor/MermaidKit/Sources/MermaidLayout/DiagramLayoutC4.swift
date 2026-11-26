import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry for a C4 diagram: elements as uniform-width labelled boxes placed
/// in a simple relationship-layered grid, with orthogonally-routed labelled
/// arrows between them that thread the empty channels between rows (and a side
/// gutter lane for multi-row hops) so no arrow crosses an unrelated box. People
/// carry a small drawn "head" (the renderer adds it above the box top). Pure
/// geometry — the renderer only draws.
public struct C4Layout: Sendable {
    /// One C4 element box.
    public struct Box: Sendable {
        public let frame: CGRect
        /// e.g. «Person», «External System», «Container».
        public let stereotype: String
        /// Bold title, word-wrapped to the box width.
        public let titleLines: [String]
        /// Technology tag + description, word-wrapped.
        public let detailLines: [String]
        public let isPerson: Bool
        public let external: Bool
        public let colorIndex: Int
    }

    /// A labelled relationship arrow.
    public struct Edge: Sendable {
        /// Orthogonal routed polyline, endpoint to endpoint (>= 2 points). The
        /// route threads the empty channels between rows (and, for edges that
        /// span more than one row, a clear lane in the side gutter) so it never
        /// crosses a non-endpoint box.
        public let points: [CGPoint]
        public let label: String?
        /// Where the label is drawn — a point on the route that lies in a clear
        /// channel band, so it doesn't sit on a box.
        public let labelPoint: CGPoint
        /// First route point, kept for callers that want the endpoints.
        public var from: CGPoint { points.first ?? .zero }
        /// Last route point (the arrowhead end).
        public var to: CGPoint { points.last ?? .zero }
    }

    /// The frame of a boundary (or deployment node): a dashed rectangle round
    /// the boxes declared inside it, captioned in its bottom-left corner.
    /// (Chartz addition.)
    public struct Frame: Sendable {
        public let rect: CGRect
        /// e.g. "Internet Banking  «System Boundary»".
        public let caption: String
        /// Where the caption is centred; it is laid out left-aligned inside
        /// the frame, but both renderers place text by its centre.
        public let captionCenter: CGPoint
        /// 0 for an outermost frame, 1 for one nested inside it, and so on.
        public let depth: Int
    }

    public let size: CGSize
    public let title: String?
    public let boxes: [Box]
    public let edges: [Edge]
    /// Outermost first, so drawing in order puts inner frames on top.
    public let frames: [Frame]

    public init(size: CGSize, title: String?, boxes: [Box], edges: [Edge], frames: [Frame] = []) {
        self.size = size
        self.title = title
        self.boxes = boxes
        self.edges = edges
        self.frames = frames
    }
}

extension DiagramLayoutEngine {

    /// The line pitches of a C4 box's stacked text — the 9.5pt stereotype, the
    /// 12pt title lines, the 10pt detail lines — 13, 16 and 13 at the default
    /// size, grown with the text. The layout sizes boxes with them and both
    /// renderers place the lines by them.
    package static func c4LinePitches(_ measure: DiagramTextMeasurer)
        -> (stereotype: CGFloat, title: CGFloat, detail: CGFloat) {
        (grown(13, fontSize: 9.5, measure), grown(16, fontSize: 12, measure), grown(13, fontSize: 10, measure))
    }

    /// Lays out a C4 diagram: elements as uniform-width boxes in
    /// relationship-layered, horizontally centered rows; arrows thread the
    /// empty channels between rows (multi-row hops via side-gutter lanes) and
    /// same-channel labels fan out vertically. Pure geometry — the renderer
    /// only draws.
    public static func layout(_ diagram: C4Diagram, measure: DiagramTextMeasurer) -> C4Layout {
        // Long labels cost height (#70). The canvas caps at 3999pt, so if the
        // whole chart wouldn't fit at the generous line caps, lay it out again
        // at tighter ones, down to 2 title / 3 detail lines — every cut still
        // ends in "…" — rather than let the canvas clip whole rows. The last
        // caps are the ones the layout always had (technology included), so
        // the result is never taller than it was before #70.
        let caps: [(title: Int, detail: Int)] = [(4, 12), (3, 6), (2, 3)]
        for cap in caps {
            let (layout, height) = layout(diagram, measure: measure, titleCap: cap.title, detailCap: cap.detail)
            if height <= 3999 || cap == caps.last! { return layout }
        }
        preconditionFailure("unreachable: the last cap always returns")
    }

    private static func layout(_ diagram: C4Diagram, measure: DiagramTextMeasurer,
                               titleCap: Int, detailCap: Int) -> (C4Layout, height: CGFloat) {
        let margin: CGFloat = 16
        let titleHeight: CGFloat = diagram.title == nil ? 0 : Self.titleHeight(24, measure)
        // Boxes widen with the text, so a label wraps to the same lines at any
        // text size.
        let boxWidth: CGFloat = grown(176, fontSize: nodeFontSize, measure)
        let pad: CGFloat = 10
        let textWidth = boxWidth - pad * 2
        let pitches = c4LinePitches(measure)
        let stereoH = pitches.stereotype
        let titleGap: CGFloat = 3
        let titleLineH = pitches.title
        let detailLineH = pitches.detail
        let hGap: CGFloat = 26
        // Room for arrows, stacked labels, a person's head.
        let vGap: CGFloat = grown(62, fontSize: labelFontSize, measure)
        let maxCols = 6

        // Greedy word-wrap to `textWidth`. Invariant: the lines, joined by
        // single spaces, are exactly the text's words in order — none is
        // dropped — and every line fits `textWidth` unless it is a single word
        // wider than the box. Boxes are a uniform width but each grows to its
        // own line count (rows top-align on their tallest box), so a long label
        // costs height, not words (#70). Past `maxLines` (generous: no real
        // label reaches it, but one can't grow a box past the 3999pt canvas)
        // the last kept line ends in "…", so a cut is marked, never silent.
        func wrap(_ text: String, fontSize: Double, maxLines: Int) -> [String] {
            let words = text.split(separator: " ").map(String.init)
            var lines: [String] = []
            var current = ""
            for word in words {
                let candidate = current.isEmpty ? word : current + " " + word
                if current.isEmpty || measure(candidate, fontSize).width <= textWidth {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                    // A line past the cap only marks the cut; nothing after it
                    // can change what's kept, so stop measuring.
                    if lines.count == maxLines { break }
                }
            }
            if !current.isEmpty { lines.append(current) }
            guard lines.count > maxLines else { return lines }
            var last = lines[maxLines - 1].split(separator: " ").map(String.init)
            while last.count > 1, measure(last.joined(separator: " ") + "…", fontSize).width > textWidth {
                last.removeLast()
            }
            // A lone word that fits but leaves no room for "…" gives up letters.
            var kept = last.joined(separator: " ")
            while kept.count > 1, measure(kept + "…", fontSize).width > textWidth { kept.removeLast() }
            return lines.prefix(maxLines - 1) + [kept + "…"]
        }

        func stereotype(_ e: C4Diagram.Element) -> String {
            let base: String
            switch e.kind {
            case .person: base = "Person"
            case .system: base = "System"
            case .container: base = "Container"
            case .component: base = "Component"
            }
            return "\u{00AB}\(e.external ? "External " : "")\(base)\u{00BB}"
        }

        func colorIndex(_ e: C4Diagram.Element) -> Int {
            switch e.kind {
            case .person: return 0
            case .system: return 1
            case .container: return 2
            case .component: return 3
            }
        }

        // Per-element content + measured height.
        struct Content {
            let stereotype: String
            let titleLines: [String]
            let detailLines: [String]
            let isPerson: Bool
            let external: Bool
            let colorIndex: Int
            let height: CGFloat
        }

        let contents: [Content] = diagram.elements.map { e in
            let titleLines = wrap(e.label, fontSize: nodeFontSize, maxLines: titleCap)
            var details: [String] = []
            if let tech = e.technology, !tech.isEmpty { details.append("[\(tech)]") }
            if let d = e.descr, !d.isEmpty {
                // The technology line counts toward the cap, as it always has.
                details += wrap(d, fontSize: labelFontSize, maxLines: max(1, detailCap - details.count))
            }
            let titleCount = max(titleLines.count, 1)
            let height = pad + stereoH + titleGap + CGFloat(titleCount) * titleLineH
                + (details.isEmpty ? 0 : 4 + CGFloat(details.count) * detailLineH) + pad
            return Content(
                stereotype: stereotype(e),
                titleLines: titleLines.isEmpty ? [e.label] : titleLines,
                detailLines: details,
                isPerson: e.kind == .person,
                external: e.external,
                colorIndex: colorIndex(e),
                height: height
            )
        }

        let aliasIndex = Dictionary(diagram.elements.enumerated().map { ($1.alias, $0) },
                                    uniquingKeysWith: { a, _ in a })
        let n = diagram.elements.count

        // Relationship layering: longest-path from sources over the
        // relationships left once DFS back edges are dropped, as flowcharts
        // drop them, so only a cycle sends an arrow back up (#102). The cap is
        // a guard; with no cycle left it never binds.
        var adjacency: [(Int, Int)] = []
        for r in diagram.relations {
            guard let f = aliasIndex[r.from], let t = aliasIndex[r.to], f != t else { continue }
            adjacency.append((f, t))
        }
        let back = backEdgeIndices(ids: (0..<n).map(String.init),
                                   edges: adjacency.map { (String($0.0), String($0.1)) })
        adjacency = adjacency.enumerated().filter { !back.contains($0.offset) }.map(\.element)
        var layer = [Int](repeating: 0, count: n)
        for _ in 0..<max(n, 1) {
            var changed = false
            for (f, t) in adjacency where layer[t] < layer[f] + 1 && layer[f] + 1 <= n {
                layer[t] = layer[f] + 1
                changed = true
            }
            if !changed { break }
        }

        // Group element indices by layer (appearance order within a layer),
        // then split oversized layers into chunks so no visual row overflows.
        let maxLayer = layer.max() ?? 0
        var visualRows: [[Int]] = []
        for l in 0...maxLayer {
            let inLayer = (0..<n).filter { layer[$0] == l }
            guard !inLayer.isEmpty else { continue }
            var i = 0
            while i < inLayer.count {
                visualRows.append(Array(inLayer[i..<min(i + maxCols, inLayer.count)]))
                i += maxCols
            }
        }
        if visualRows.isEmpty { visualRows = [Array(0..<n)] }

        // ── Boundaries (Chartz addition) ────────────────────────────────────
        // A frame can only be drawn if its boxes sit together with nothing
        // else among them. Rows are relationship layers, so that does not
        // happen by itself. Each outermost boundary therefore gets a "block":
        // a fixed span of columns it owns in every row it reaches. Boxes
        // outside any boundary go to the left or right of the blocks in those
        // rows. With no boundaries none of this runs and the layout is
        // exactly what it was.
        let boundaryParent = Dictionary(diagram.boundaries.map { ($0.alias, $0.parent) },
                                        uniquingKeysWith: { a, _ in a })
        // Innermost-to-outermost chain of boundary aliases for an element.
        func chain(_ index: Int) -> [String] {
            var result: [String] = []
            var current = diagram.elements[index].boundary
            while let alias = current, boundaryParent[alias] != nil, !result.contains(alias) {
                result.append(alias)
                current = boundaryParent[alias] ?? nil
            }
            return result
        }
        let chains = (0..<n).map(chain)
        // Outermost boundaries that hold something, in order of first use.
        var blocks: [String] = []
        for index in 0..<n {
            if let top = chains[index].last, !blocks.contains(top) { blocks.append(top) }
        }
        let framePadX: CGFloat = 16

        struct BlockPlan {
            var firstRow = Int.max
            var lastRow = Int.min
            var columns = 1
            /// How many frames nest inside this one at the deepest point.
            var nesting = 0
            var minX: CGFloat = 0
            var width: CGFloat = 0
        }
        var blockPlans = [String: BlockPlan]()
        for (rowIndex, row) in visualRows.enumerated() {
            for block in blocks {
                let members = row.filter { chains[$0].last == block }
                guard !members.isEmpty else { continue }
                var plan = blockPlans[block] ?? BlockPlan()
                plan.firstRow = min(plan.firstRow, rowIndex)
                plan.lastRow = max(plan.lastRow, rowIndex)
                plan.columns = max(plan.columns, members.count)
                plan.nesting = max(plan.nesting, (members.map { chains[$0].count }.max() ?? 1) - 1)
                blockPlans[block] = plan
            }
        }
        /// Rows a block spans keep to the block columns; the rest centre freely.
        func isConstrained(_ rowIndex: Int) -> Bool {
            blockPlans.values.contains { $0.firstRow <= rowIndex && rowIndex <= $0.lastRow }
        }
        // In a constrained row, outsiders split to either side of the blocks.
        func outsiders(_ row: [Int]) -> (left: [Int], right: [Int]) {
            let free = row.filter { chains[$0].isEmpty }
            let leftCount = free.count / 2
            return (Array(free.prefix(leftCount)), Array(free.dropFirst(leftCount)))
        }
        func span(_ columns: Int) -> CGFloat {
            columns <= 0 ? 0 : CGFloat(columns) * boxWidth + CGFloat(columns - 1) * hGap
        }
        var leftColumns = 0, rightColumns = 0
        for (rowIndex, row) in visualRows.enumerated() where isConstrained(rowIndex) {
            let sides = outsiders(row)
            leftColumns = max(leftColumns, sides.left.count)
            rightColumns = max(rightColumns, sides.right.count)
        }
        // Block geometry, relative to the start of the content strip.
        var contentWidth: CGFloat = leftColumns > 0 ? span(leftColumns) + hGap : 0
        for block in blocks {
            guard var plan = blockPlans[block] else { continue }
            // Each level of nesting needs its own margin inside the frame.
            plan.width = span(plan.columns) + 2 * (framePadX + CGFloat(plan.nesting) * 10)
            plan.minX = contentWidth
            contentWidth += plan.width + hGap
            blockPlans[block] = plan
        }
        if !blocks.isEmpty { contentWidth -= hGap }
        if rightColumns > 0 { contentWidth += hGap + span(rightColumns) }

        let widestCols = visualRows.enumerated()
            .filter { !isConstrained($0.offset) }.map(\.element.count).max() ?? 1
        let canvasWidth = max(220,
            margin * 2 + CGFloat(widestCols) * boxWidth + CGFloat(widestCols - 1) * hGap,
            blocks.isEmpty ? 0 : margin * 2 + contentWidth,
            diagram.title.map { measure($0, titleFontSize).width + margin * 2 } ?? 0)
        let contentOrigin = (canvasWidth - contentWidth) / 2

        // Extra room above the first and below the last row of a block, for
        // the frame line and its caption, so neither lands on the arrow labels
        // that live in the middle of each channel.
        let captionHeight = grown(14, fontSize: 10.5, measure)
        func frameTopPad(_ nesting: Int) -> CGFloat { 18 + CGFloat(nesting) * 8 }
        func frameBottomPad(_ nesting: Int) -> CGFloat { 10 + (captionHeight + 4) * CGFloat(nesting + 1) }
        var extraAbove = [CGFloat](repeating: 0, count: visualRows.count)
        var extraBelow = [CGFloat](repeating: 0, count: visualRows.count)
        // Every boundary, nested ones included: a nested frame can end in the
        // middle of its parent's rows and needs the room there too.
        for boundary in diagram.boundaries {
            let rows = visualRows.indices.filter { rowIndex in
                visualRows[rowIndex].contains { chains[$0].contains(boundary.alias) }
            }
            guard let firstRow = rows.first, let lastRow = rows.last else { continue }
            let below = visualRows.joined()
                .compactMap { chains[$0].firstIndex(of: boundary.alias) }.max() ?? 0
            extraAbove[firstRow] = max(extraAbove[firstRow], CGFloat(below) * 8)
            extraBelow[lastRow] = max(extraBelow[lastRow], frameBottomPad(below) - 8)
        }

        // Place boxes row by row, each row centered horizontally, top-aligned
        // within the row's tallest box. Record each element's visual row so the
        // edge router knows which channels to thread.
        var frames = [CGRect](repeating: .zero, count: n)
        var rowOf = [Int](repeating: 0, count: n)
        var y = margin + titleHeight + 12       // +12: headroom for people in row 0
        var lastExtraBelow: CGFloat = 0
        for (rowIndex, row) in visualRows.enumerated() {
            y += extraAbove[rowIndex]
            let rowHeight = row.map { contents[$0].height }.max() ?? 0
            func place(_ indices: [Int], from start: CGFloat) {
                var x = start
                for idx in indices {
                    frames[idx] = CGRect(x: x, y: y, width: boxWidth, height: contents[idx].height)
                    rowOf[idx] = rowIndex
                    x += boxWidth + hGap
                }
            }
            if isConstrained(rowIndex) {
                let sides = outsiders(row)
                // Left outsiders hug the blocks; right ones start after them.
                let leftZone = leftColumns > 0 ? span(leftColumns) + hGap : 0
                place(sides.left, from: contentOrigin + leftZone - hGap - span(sides.left.count))
                place(sides.right, from: contentOrigin + contentWidth - span(rightColumns))
                for block in blocks {
                    guard let plan = blockPlans[block] else { continue }
                    // Keep nested groups together inside the block.
                    let members = row.filter { chains[$0].last == block }
                        .enumerated()
                        .sorted { a, b in
                            let ka = chains[a.element].reversed().joined(separator: "/")
                            let kb = chains[b.element].reversed().joined(separator: "/")
                            return ka == kb ? a.offset < b.offset : ka < kb
                        }
                        .map(\.element)
                    place(members, from: contentOrigin + plan.minX + (plan.width - span(members.count)) / 2)
                }
            } else {
                place(row, from: (canvasWidth - span(row.count)) / 2)
            }
            lastExtraBelow = extraBelow[rowIndex]
            y += rowHeight + vGap + extraBelow[rowIndex]
        }
        let canvasHeight = y - vGap + margin - lastExtraBelow
            + (lastExtraBelow > 0 ? lastExtraBelow + 8 : 0)

        // A validated route (see below) for every relation whose endpoints
        // exist and differ, computed against the *pre-shift* frames.
        struct Plan {
            let f: Int, t: Int
            let rf: Int, rt: Int
            let label: String?
        }
        var plans: [Plan] = []
        for r in diagram.relations {
            guard let f = aliasIndex[r.from], let t = aliasIndex[r.to], f != t else { continue }
            let text = r.technology.map { r.label.isEmpty ? "[\($0)]" : "\(r.label) [\($0)]" } ?? r.label
            plans.append(Plan(f: f, t: t, rf: rowOf[f], rt: rowOf[t],
                              label: text.isEmpty ? nil : text))
        }

        // Multi-row edges hop through a vertical lane in a side gutter. Assign
        // each such edge to the left or right gutter (whichever its endpoints
        // sit nearer) and give it a distinct lane index there, so lanes never
        // collapse onto each other.
        let laneSpacing: CGFloat = 16
        let centerPre = canvasWidth / 2
        var laneIsLeft = [Bool](repeating: true, count: plans.count)
        var laneIdx = [Int](repeating: 0, count: plans.count)
        var leftLanes = 0, rightLanes = 0
        for (i, p) in plans.enumerated() where abs(p.rf - p.rt) >= 2 {
            let mid = (frames[p.f].midX + frames[p.t].midX) / 2
            let isLeft = mid < centerPre
            laneIsLeft[i] = isLeft
            if isLeft { laneIdx[i] = leftLanes; leftLanes += 1 }
            else { laneIdx[i] = rightLanes; rightLanes += 1 }
        }
        let leftReserve: CGFloat = leftLanes > 0 ? laneSpacing * CGFloat(leftLanes) + 12 : 0
        let rightReserve: CGFloat = rightLanes > 0 ? laneSpacing * CGFloat(rightLanes) + 12 : 0

        // Slide everything right to open the left gutter, then widen for both.
        if leftReserve > 0 {
            for i in 0..<n { frames[i].origin.x += leftReserve }
        }
        let finalWidth = canvasWidth + leftReserve + rightReserve

        // Per-row vertical extents (y is unaffected by the horizontal shift).
        var rowTop = [CGFloat](repeating: 0, count: visualRows.count)
        var rowBottom = [CGFloat](repeating: 0, count: visualRows.count)
        for (r, row) in visualRows.enumerated() {
            rowTop[r] = row.map { frames[$0].minY }.min() ?? 0
            rowBottom[r] = row.map { frames[$0].maxY }.max() ?? 0
        }
        // Midline of the empty channel just below row `r` (== just above r+1).
        func channelBelow(_ r: Int) -> CGFloat {
            r + 1 < visualRows.count ? (rowBottom[r] + rowTop[r + 1]) / 2
                                     : rowBottom[r] + vGap / 2
        }
        func channelAbove(_ r: Int) -> CGFloat {
            r - 1 >= 0 ? (rowBottom[r - 1] + rowTop[r]) / 2
                       : rowTop[r] - vGap / 2
        }
        func laneX(isLeft: Bool, _ idx: Int) -> CGFloat {
            isLeft ? 10 + laneSpacing * CGFloat(idx)
                   : finalWidth - 10 - laneSpacing * CGFloat(idx)
        }

        let boxes: [C4Layout.Box] = (0..<n).map { i in
            let c = contents[i]
            return C4Layout.Box(
                frame: frames[i],
                stereotype: c.stereotype,
                titleLines: c.titleLines,
                detailLines: c.detailLines,
                isPerson: c.isPerson,
                external: c.external,
                colorIndex: c.colorIndex
            )
        }

        // Orthogonal edge routing. Every horizontal run lives in an empty
        // channel between rows (or a side lane), every vertical run stays in a
        // box's own column or a clear gutter lane — so a route only ever touches
        // its two endpoint boxes.
        struct Route { let points: [CGPoint]; let label: String?; var labelPoint: CGPoint }
        var routes: [Route] = []
        for (i, p) in plans.enumerated() {
            let sf = frames[p.f], tf = frames[p.t]
            let points: [CGPoint]
            let labelPoint: CGPoint

            if p.rf == p.rt {
                // Same row: dip into the channel below (or above, on the last row).
                if p.rf + 1 < visualRows.count {
                    let ch = channelBelow(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                } else {
                    let ch = channelAbove(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                }
            } else if abs(p.rf - p.rt) == 1 {
                // Adjacent rows: a single channel step between them.
                if p.rt > p.rf {
                    let ch = channelBelow(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                } else {
                    let ch = channelAbove(p.rf)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: ch),
                              CGPoint(x: tf.midX, y: ch),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (sf.midX + tf.midX) / 2, y: ch)
                }
            } else {
                // Multi-row: out to a side-gutter lane, down/up the lane, back in.
                let lx = laneX(isLeft: laneIsLeft[i], laneIdx[i])
                if p.rt > p.rf {
                    let chS = channelBelow(p.rf), chT = channelAbove(p.rt)
                    points = [CGPoint(x: sf.midX, y: sf.maxY),
                              CGPoint(x: sf.midX, y: chS),
                              CGPoint(x: lx, y: chS),
                              CGPoint(x: lx, y: chT),
                              CGPoint(x: tf.midX, y: chT),
                              CGPoint(x: tf.midX, y: tf.minY)]
                    labelPoint = CGPoint(x: (lx + tf.midX) / 2, y: chT)
                } else {
                    let chS = channelAbove(p.rf), chT = channelBelow(p.rt)
                    points = [CGPoint(x: sf.midX, y: sf.minY),
                              CGPoint(x: sf.midX, y: chS),
                              CGPoint(x: lx, y: chS),
                              CGPoint(x: lx, y: chT),
                              CGPoint(x: tf.midX, y: chT),
                              CGPoint(x: tf.midX, y: tf.maxY)]
                    labelPoint = CGPoint(x: (lx + tf.midX) / 2, y: chT)
                }
            }
            routes.append(Route(points: points, label: p.label, labelPoint: labelPoint))
        }

        // Spread labels that land in the same channel band vertically, so a
        // dense fan-in/out doesn't stack them on top of one another. The band
        // (vGap tall) has room to fan a few labels without touching a box.
        var bands: [Int: [Int]] = [:]
        for (i, r) in routes.enumerated() where r.label != nil {
            bands[Int(r.labelPoint.y.rounded()), default: []].append(i)
        }
        for (_, idxs) in bands where idxs.count > 1 {
            let ordered = idxs.sorted { routes[$0].labelPoint.x < routes[$1].labelPoint.x }
            let baseY = routes[ordered[0]].labelPoint.y
            let step = grown(15, fontSize: labelFontSize, measure)
            // Keep the whole stack inside the channel (± ~half a gap off boxes).
            let limit = vGap / 2 - 8
            let span = min(CGFloat(ordered.count - 1) * step, 2 * limit)
            let actualStep = ordered.count > 1 ? span / CGFloat(ordered.count - 1) : 0
            for (k, idx) in ordered.enumerated() {
                routes[idx].labelPoint.y = baseY - span / 2 + CGFloat(k) * actualStep
            }
        }

        // Boundary frames, from the final box positions. A frame is the
        // bounding box of its members plus padding. If that box would also
        // take in a box that is not a member (possible for a nested boundary
        // whose members straddle rows), the frame is left out rather than
        // drawn round the wrong things.
        var boundaryFrames: [C4Layout.Frame] = []
        for boundary in diagram.boundaries {
            let members = (0..<n).filter { chains[$0].contains(boundary.alias) }
            guard let first = members.first else { continue }
            // Depth from the outside in; how much nests beneath this frame.
            var depth = 0
            var up = boundary.parent
            while let alias = up, depth < 16 { depth += 1; up = boundaryParent[alias] ?? nil }
            let below = (members.map { chains[$0].firstIndex(of: boundary.alias) ?? 0 }.max() ?? 0)
            var box = members.dropFirst().reduce(frames[first]) { $0.union(frames[$1]) }
            let padX = framePadX + CGFloat(below) * 10 - 6
            box = CGRect(x: box.minX - padX, y: box.minY - frameTopPad(below),
                         width: box.width + padX * 2,
                         height: box.height + frameTopPad(below) + frameBottomPad(below))
            // Grow outward to the 4pt grid the box families align to, so a
            // frame never makes the layout less grid-aligned than it was.
            let grid: CGFloat = 4
            let snappedMinX = (box.minX / grid).rounded(.down) * grid
            let snappedMinY = (box.minY / grid).rounded(.down) * grid
            box = CGRect(x: snappedMinX, y: snappedMinY,
                         width: (box.maxX / grid).rounded(.up) * grid - snappedMinX,
                         height: (box.maxY / grid).rounded(.up) * grid - snappedMinY)
            let intruder = (0..<n).contains { !members.contains($0) && frames[$0].intersects(box) }
            guard !intruder else { continue }
            let kind = boundary.kind.isEmpty ? "Boundary"
                : (boundary.kind == "Node" ? "Node" : "\(boundary.kind) Boundary")
            // The caption sits in the bottom-left corner, where arrows leaving
            // the bottom row also pass. Give it only the room up to the first
            // arrow that crosses its line, and say less rather than be struck
            // through: drop the «kind», then shorten the name.
            let captionY = box.maxY - 6 - captionHeight / 2
            let startX = box.minX + 10
            var available = box.maxX - 10 - startX
            for route in routes {
                for (p, q) in zip(route.points, route.points.dropFirst())
                where p.x == q.x && p.x > startX
                    && min(p.y, q.y) < captionY + captionHeight / 2
                    && max(p.y, q.y) > captionY - captionHeight / 2 {
                    available = min(available, p.x - 6 - startX)
                }
            }
            var caption = "\(boundary.label)  \u{00AB}\(kind)\u{00BB}"
            if measure(caption, 10.5).width > available { caption = boundary.label }
            while caption.count > 1, measure(caption, 10.5).width > available {
                caption = String(caption.dropLast(caption.hasSuffix("…") ? 2 : 1)) + "…"
            }
            let captionWidth = measure(caption, 10.5).width
            boundaryFrames.append(C4Layout.Frame(
                rect: box, caption: caption,
                captionCenter: CGPoint(x: startX + captionWidth / 2, y: captionY),
                depth: depth))
        }
        boundaryFrames.sort { $0.depth < $1.depth }

        let edges: [C4Layout.Edge] = routes.map {
            C4Layout.Edge(points: $0.points, label: $0.label, labelPoint: $0.labelPoint)
        }

        let width = min(max(finalWidth, 1), 3999)
        let height = min(max(canvasHeight, 1), 3999)
        return (C4Layout(size: CGSize(width: width, height: height),
                         title: diagram.title, boxes: boxes, edges: edges,
                         frames: boundaryFrames), canvasHeight)
    }
}
