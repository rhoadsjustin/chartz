import Foundation

// Chartz addition (not upstream): see VENDORED.md.
//
// Upstream reads `classDef`, `class`, `:::` and `style` and throws them away,
// so every node looks the same. This file gives them somewhere to go: a small
// per-node style the layout carries through to both renderers.

extension Flowchart {
    /// What `classDef` / `style` can change about one node. Every field is
    /// optional: nil means "whatever the theme does".
    public struct NodeStyle: Hashable, Sendable {
        public var fill: DiagramColor?
        public var stroke: DiagramColor?
        /// Label colour (`color:` in Mermaid).
        public var text: DiagramColor?
        /// `stroke-width`, in points.
        public var strokeWidth: Double?
        /// True when `stroke-dasharray` is set to anything but `none` / `0`.
        public var dashed: Bool?

        public init(fill: DiagramColor? = nil, stroke: DiagramColor? = nil, text: DiagramColor? = nil,
                    strokeWidth: Double? = nil, dashed: Bool? = nil) {
            self.fill = fill
            self.stroke = stroke
            self.text = text
            self.strokeWidth = strokeWidth
            self.dashed = dashed
        }

        public var isEmpty: Bool { self == NodeStyle() }

        /// This style with `other` laid over it: `other` wins where it says
        /// something. Mermaid applies `classDef default`, then classes, then
        /// `style`, in that order.
        public func merging(_ other: NodeStyle) -> NodeStyle {
            NodeStyle(fill: other.fill ?? fill, stroke: other.stroke ?? stroke, text: other.text ?? text,
                      strokeWidth: other.strokeWidth ?? strokeWidth, dashed: other.dashed ?? dashed)
        }

        /// The colour to draw the label in: the declared one, or, when only a
        /// fill was given, black or white, whichever reads better on it.
        /// Without this a pale fill under a dark theme's pale text (or the
        /// reverse) is unreadable.
        public func labelColor(default ink: DiagramColor) -> DiagramColor {
            if let text { return text }
            guard let fill, fill.alpha > 0.5 else { return ink }
            // Relative luminance, sRGB coefficients.
            let luminance = 0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue
            return luminance > 0.55 ? DiagramColor(hex: 0x1A1A1A) : DiagramColor(hex: 0xFFFFFF)
        }

        /// Reads a Mermaid style list: `fill:#f9f,stroke:#333,stroke-width:2px`.
        /// Properties it does not know, and values it cannot read, are skipped.
        public init(css: String) {
            self.init()
            for declaration in Self.split(css) {
                guard let colon = declaration.firstIndex(of: ":") else { continue }
                let key = declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = declaration[declaration.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                switch key {
                case "fill", "background", "background-color":
                    fill = DiagramColor(css: value) ?? fill
                case "stroke", "border-color":
                    stroke = DiagramColor(css: value) ?? stroke
                case "color":
                    text = DiagramColor(css: value) ?? text
                case "stroke-width":
                    let number = value.lowercased().replacingOccurrences(of: "px", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let width = Double(number), width >= 0 { strokeWidth = min(width, 12) }
                case "stroke-dasharray":
                    let lowered = value.lowercased()
                    dashed = !(lowered == "none" || lowered == "0" || lowered.isEmpty)
                default:
                    break
                }
            }
        }

        /// Splits on commas and semicolons, but not inside `rgb(…)`.
        private static func split(_ css: String) -> [String] {
            var parts: [String] = []
            var current = ""
            var depth = 0
            for character in css {
                if character == "(" { depth += 1 }
                if character == ")" { depth = max(0, depth - 1) }
                if (character == "," || character == ";"), depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            }
            parts.append(current)
            return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }
}

extension DiagramColor {
    /// A CSS colour as Mermaid styles write it: `#rgb`, `#rgba`, `#rrggbb`,
    /// `#rrggbbaa`, `rgb(r, g, b)`, `rgba(r, g, b, a)`, or one of the common
    /// colour names. Nil for anything else.
    public init?(css: String) {
        let value = css.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            var digits = String(value.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            if digits.count == 3 || digits.count == 4 {
                digits = digits.map { "\($0)\($0)" }.joined()
            }
            self.init(hexString: digits)
            return
        }
        if value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"),
           open < close {
            let numbers = value[value.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard numbers.count == 3 || numbers.count == 4 else { return nil }
            func channel(_ text: String) -> Double? {
                if text.hasSuffix("%") { return Double(text.dropLast()).map { $0 / 100 } }
                return Double(text).map { $0 / 255 }
            }
            guard let red = channel(numbers[0]), let green = channel(numbers[1]),
                  let blue = channel(numbers[2]) else { return nil }
            var alpha = 1.0
            if numbers.count == 4 {
                let text = numbers[3]
                guard let parsed = text.hasSuffix("%") ? Double(text.dropLast()).map({ $0 / 100 }) : Double(text)
                else { return nil }
                alpha = parsed
            }
            self.init(red: red, green: green, blue: blue, alpha: alpha)
            return
        }
        if value == "transparent" || value == "none" {
            self.init(red: 0, green: 0, blue: 0, alpha: 0)
            return
        }
        guard let hex = Self.named[value] else { return nil }
        self.init(hex: hex)
    }

    /// The CSS names people actually type into diagrams.
    private static let named: [String: UInt32] = [
        "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000,
        "blue": 0x0000FF, "yellow": 0xFFFF00, "orange": 0xFFA500, "purple": 0x800080,
        "pink": 0xFFC0CB, "brown": 0xA52A2A, "gray": 0x808080, "grey": 0x808080,
        "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF, "fuchsia": 0xFF00FF,
        "lime": 0x00FF00, "navy": 0x000080, "teal": 0x008080, "olive": 0x808000,
        "maroon": 0x800000, "silver": 0xC0C0C0, "gold": 0xFFD700, "indigo": 0x4B0082,
        "violet": 0xEE82EE, "coral": 0xFF7F50, "salmon": 0xFA8072, "khaki": 0xF0E68C,
        "crimson": 0xDC143C, "tomato": 0xFF6347, "skyblue": 0x87CEEB, "steelblue": 0x4682B4,
        "lightblue": 0xADD8E6, "lightgreen": 0x90EE90, "lightgray": 0xD3D3D3,
        "lightgrey": 0xD3D3D3, "lightyellow": 0xFFFFE0, "lightpink": 0xFFB6C1,
        "darkblue": 0x00008B, "darkgreen": 0x006400, "darkred": 0x8B0000,
        "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9, "darkorange": 0xFF8C00,
    ]
}
