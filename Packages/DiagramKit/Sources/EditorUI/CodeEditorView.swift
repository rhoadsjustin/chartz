#if !os(tvOS)
import DiagramCore
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// The source pane: a TextKit text view with syntax colouring, a line-number
/// gutter and indent-preserving Return.
///
/// `UITextView` on iPhone, iPad and Vision Pro; `NSTextView` on the Mac. Both
/// share `CodeStyle` and the UI-free rules in `DiagramCore`.
struct CodeEditorView: View {
    @Binding var text: String
    let format: DiagramFormat
    /// Problems to flag in the gutter.
    let diagnostics: [Diagnostic]

    var body: some View {
        PlatformCodeEditor(text: $text, format: format, marks: LineMarks(diagnostics))
            .accessibilityLabel("Diagram source")
    }
}

/// Which lines the gutter should flag, and how loudly.
struct LineMarks: Equatable {
    /// 1-based line number to "is an error" (false means a note).
    private(set) var lines: [Int: Bool] = [:]

    init(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics {
            guard let line = diagnostic.line else { continue }
            lines[line] = (lines[line] ?? false) || diagnostic.severity == .error
        }
    }
}

// MARK: - Shared styling

enum CodeStyle {
    static var font: PlatformFont {
        #if canImport(UIKit)
        // Follow the user's text size; the body style is 17pt at the default.
        let size = UIFont.preferredFont(forTextStyle: .body).pointSize - 2
        return .monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        return .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        #endif
    }

    static var gutterFont: PlatformFont {
        .monospacedDigitSystemFont(ofSize: font.pointSize - 3, weight: .regular)
    }

    static var text: PlatformColor {
        #if canImport(UIKit)
        return .label
        #else
        return .labelColor
        #endif
    }

    static var secondaryText: PlatformColor {
        #if canImport(UIKit)
        return .secondaryLabel
        #else
        return .secondaryLabelColor
        #endif
    }

    static func color(for kind: SourceToken.Kind) -> PlatformColor {
        switch kind {
        case .comment: return secondaryText
        case .string: return .systemRed
        case .keyword: return .systemPurple
        case .arrow: return .systemTeal
        }
    }

    static func gutterColor(isError: Bool?) -> PlatformColor {
        switch isError {
        case true?: return .systemRed
        case false?: return .systemOrange
        case nil: return secondaryText
        }
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: text, .paragraphStyle: paragraphStyle]
    }

    /// Code reads left to right and hugs the gutter, even when the interface
    /// around it is right-to-left. "Natural" alignment would follow the
    /// interface and push every line to the far edge.
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.baseWritingDirection = .leftToRight
        return style
    }()

    /// Recolours all of `storage`. Attributes only: the characters, the
    /// selection and the undo stack are untouched.
    static func highlight(_ storage: NSTextStorage, format: DiagramFormat) {
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: whole)
        for token in SourceHighlighter.tokens(in: storage.string, format: format) {
            storage.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
        }
        storage.endEditing()
    }

    /// Width that fits the widest line number, so the gutter does not jump on
    /// every keystroke: it only grows at 100, 1000, ... lines.
    static func gutterWidth(lineCount: Int) -> CGFloat {
        let digits = max(2, String(max(lineCount, 1)).count)
        let sample = String(repeating: "8", count: digits) as NSString
        return ceil(sample.size(withAttributes: [.font: gutterFont]).width) + 16
    }
}

/// Walks the visible line fragments of a TextKit 1 layout and reports where
/// each source line starts. Shared by the iOS gutter and the Mac ruler.
enum LineNumberLayout {
    /// - Parameters:
    ///   - visible: The visible rectangle, in text-container coordinates.
    ///   - body: Called with a 1-based line number and that line's first
    ///     fragment rectangle, in text-container coordinates.
    static func enumerate(
        layoutManager: NSLayoutManager,
        container: NSTextContainer,
        visible: CGRect,
        body: (Int, CGRect) -> Void
    ) {
        guard let text = layoutManager.textStorage?.string as NSString? else { return }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let firstCharacter = layoutManager.characterIndexForGlyph(at: glyphs.location)
        // Line number of the first visible fragment: one more than the
        // number of newlines above it.
        var line = 1
        let above = NSRange(location: 0, length: min(firstCharacter, text.length))
        line += text.substring(with: above).components(separatedBy: "\n").count - 1
        var starts: [(Int, CGRect)] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            let characters = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil)
            let startsLine = characters.location == 0
                || text.character(at: characters.location - 1) == 0x0A
            if startsLine { starts.append((line, rect)) }
            let end = NSMaxRange(characters)
            if end > 0, end <= text.length, text.character(at: end - 1) == 0x0A { line += 1 }
        }
        for (number, rect) in starts { body(number, rect) }
        // The empty line after a trailing newline (or an empty document) has
        // no glyphs; TextKit reports it separately.
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0, extra.intersects(visible) || text.length == 0 {
            let total = (text as String).components(separatedBy: "\n").count
            body(total, extra)
        }
    }

    static func draw(_ line: Int, at y: CGFloat, height: CGFloat, width: CGFloat, marks: LineMarks) {
        let label = String(line) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CodeStyle.gutterFont,
            .foregroundColor: CodeStyle.gutterColor(isError: marks.lines[line]),
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: CGPoint(x: width - size.width - 8, y: y + (height - size.height) / 2),
            withAttributes: attributes)
    }
}

// MARK: - iPhone, iPad, Vision Pro

#if canImport(UIKit)
private struct PlatformCodeEditor: UIViewRepresentable {
    @Binding var text: String
    let format: DiagramFormat
    let marks: LineMarks

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> CodeTextView {
        let view = CodeTextView()
        view.delegate = context.coordinator
        view.text = text
        CodeStyle.highlight(view.textStorage, format: format)
        view.typingAttributes = CodeStyle.baseAttributes
        return view
    }

    func updateUIView(_ view: CodeTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            // The document changed underneath us (a template, undo at the
            // document level, a file reload). Keep the caret roughly in place.
            let selection = view.selectedRange
            view.text = text
            CodeStyle.highlight(view.textStorage, format: format)
            view.typingAttributes = CodeStyle.baseAttributes
            let length = (text as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        view.marks = marks
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlatformCodeEditor
        private var isIndenting = false

        init(_ parent: PlatformCodeEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            // Leave multi-stage input (Japanese, Chinese, dictation) alone
            // until it commits; recolouring mid-composition cancels it.
            if textView.markedTextRange == nil {
                CodeStyle.highlight(textView.textStorage, format: parent.format)
                textView.typingAttributes = CodeStyle.baseAttributes
            }
            (textView as? CodeTextView)?.refreshGutter()
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            guard text == "\n", !isIndenting else { return true }
            let insertion = SourceEditing.newline(in: textView.text, at: range.location)
            guard insertion != "\n" else { return true }
            isIndenting = true
            defer { isIndenting = false }
            textView.selectedRange = range
            textView.insertText(insertion)
            return false
        }
    }
}

/// `UITextView` on TextKit 1, with a line-number gutter pinned to its left edge.
final class CodeTextView: UITextView {
    private let storage = NSTextStorage()
    private let gutter = GutterView()

    var marks = LineMarks([]) {
        didSet { if marks != oldValue { gutter.setNeedsDisplay() } }
    }

    init() {
        // An explicit layout manager keeps the view on TextKit 1, which is
        // what the gutter reads line positions from.
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)

        font = CodeStyle.font
        textColor = CodeStyle.text
        backgroundColor = .clear
        alwaysBounceVertical = true
        #if os(iOS)
        keyboardDismissMode = .interactive
        #endif
        // Source code, not prose: "--" must stay two hyphens and quotes straight.
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        // Code reads left to right even in a right-to-left interface.
        semanticContentAttribute = .forceLeftToRight
        textAlignment = .left

        gutter.textView = self
        addSubview(gutter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lineCount = (text as NSString).components(separatedBy: "\n").count
        let width = CodeStyle.gutterWidth(lineCount: lineCount)
        let inset = UIEdgeInsets(top: 10, left: width + 4, bottom: 10, right: 8)
        if textContainerInset != inset { textContainerInset = inset }
        // Scrolling moves `bounds`; following it keeps the gutter in place
        // without a backing store as tall as the document.
        gutter.frame = CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        gutter.setNeedsDisplay()
    }

    func refreshGutter() {
        setNeedsLayout()
        gutter.setNeedsDisplay()
    }

    private final class GutterView: UIView {
        weak var textView: CodeTextView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            isUserInteractionEnabled = false
            contentMode = .redraw
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func draw(_ rect: CGRect) {
            guard let textView else { return }
            let inset = textView.textContainerInset
            let offset = textView.contentOffset.y
            let visible = CGRect(
                x: 0, y: offset - inset.top,
                width: textView.textContainer.size.width, height: bounds.height)
            LineNumberLayout.enumerate(
                layoutManager: textView.layoutManager,
                container: textView.textContainer,
                visible: visible
            ) { line, fragment in
                LineNumberLayout.draw(
                    line, at: fragment.minY + inset.top - offset, height: fragment.height,
                    width: bounds.width, marks: textView.marks)
            }
        }
    }
}

// MARK: - Mac

#elseif canImport(AppKit)
private struct PlatformCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let format: DiagramFormat
    let marks: LineMarks

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        context.coordinator.storage.addLayoutManager(layoutManager)

        let textView = CodeNSTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.font = CodeStyle.font
        textView.textColor = CodeStyle.text
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // Source code, not prose.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.baseWritingDirection = .leftToRight
        textView.string = text
        CodeStyle.highlight(context.coordinator.storage, format: format)
        textView.typingAttributes = CodeStyle.baseAttributes

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        let ruler = LineNumberRuler(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.ruler = ruler
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            CodeStyle.highlight(coordinator.storage, format: format)
            textView.typingAttributes = CodeStyle.baseAttributes
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        coordinator.ruler?.marks = marks
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlatformCodeEditor
        /// The text view does not own its storage when it is built from a
        /// text container, so this keeps it alive.
        let storage = NSTextStorage()
        var ruler: LineNumberRuler?

        init(_ parent: PlatformCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if !textView.hasMarkedText() {
                CodeStyle.highlight(storage, format: parent.format)
                textView.typingAttributes = CodeStyle.baseAttributes
            }
            ruler?.refresh()
        }
    }
}

/// `NSTextView` with indent-preserving Return and a soft Tab.
final class CodeNSTextView: NSTextView {
    override func insertNewline(_ sender: Any?) {
        let range = selectedRange()
        insertText(SourceEditing.newline(in: string, at: range.location), replacementRange: range)
    }

    override func insertTab(_ sender: Any?) {
        insertText(SourceEditing.indentUnit, replacementRange: selectedRange())
    }
}

/// Line numbers down the left edge of the Mac editor.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    var marks = LineMarks([]) {
        didSet { if marks != oldValue { needsDisplay = true } }
    }

    // Match the text view, so line positions convert without a flip.
    override var isFlipped: Bool { true }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        // Since macOS 14 views draw outside their bounds unless told not to,
        // which lets the text show through the ruler.
        clipsToBounds = true
        refresh()
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidScroll),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func contentDidScroll(_ notification: Notification) {
        needsDisplay = true
    }

    func refresh() {
        let lineCount = (textView?.string ?? "").components(separatedBy: "\n").count
        let width = CodeStyle.gutterWidth(lineCount: lineCount)
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    // Skip the stock ruler background so the gutter matches the code pane.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        LineNumberLayout.enumerate(
            layoutManager: layoutManager, container: container, visible: visible
        ) { line, fragment in
            let y = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: textView).y
            LineNumberLayout.draw(
                line, at: y, height: fragment.height, width: ruleThickness, marks: marks)
        }
    }
}
#endif
#endif
