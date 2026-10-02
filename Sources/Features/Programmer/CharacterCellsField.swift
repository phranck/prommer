import AppKit
import Combine
import SwiftUI

/// A text field that gives every character a place of its own, the way a paper transfer
/// form does: one shallow trough per place, filled from the left.
///
/// The point is that the remaining room is visible rather than counted. The field holds a
/// fixed number of characters because the descriptor block gives it a fixed number of
/// bytes, and a name one character too long would shift every field behind it.
///
/// It draws and edits the text itself. A `TextField` cannot do this: it lays its glyphs
/// out by its own rules and aligns the whole run inside whatever space it is given, so the
/// characters drift away from a grid drawn behind them. Everything a person expects of a
/// text field is therefore built here: a caret, a selection, the arrow keys with and
/// without Shift, deleting in both directions, and the clipboard.
struct CharacterCellsField: View {

    // MARK: Properties

    /// What the field is called. It stands above the places, because a row of 32 of them
    /// beside a label would push the window wider than it needs to be.
    let label: LocalizedStringKey

    /// The SF Symbol beside the label.
    let symbol: String

    /// How many characters the field holds.
    let capacity: Int

    /// What the field accepts. The descriptor's strings take anything the chip can
    /// transmit; an identifier takes hexadecimal only.
    var allowed: Allowed = .asciiPrintable

    /// Something unchangeable in front of the places, such as the `0x` of a hex number.
    var prefix: String?

    @Binding var text: String

    @FocusState private var isFocused: Bool

    /// Where typing happens. Between 0 and the length of the text.
    @State private var caret = 0

    /// Where the current selection started. Equal to ``caret`` when nothing is selected.
    @State private var anchor = 0

    @State private var caretVisible = true
    @State private var isDragging = false

    private let blink = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .symbolRenderingMode(.hierarchical)

            // Aligned at the bottom, so the prefix sits on the same line as the characters
            // in their troughs.
            HStack(alignment: .bottom, spacing: 2) {
                if let prefix {
                    Text(prefix)
                        .font(.system(size: Metrics.standard.fontSize, design: .monospaced))
                        .foregroundStyle(Color.terminalGreen.opacity(Metrics.standard.textDimming))
                        .padding(.bottom, 3)
                }

                cells
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Input

extension CharacterCellsField {

    /// Which characters a field takes.
    enum Allowed {
        /// Everything the audio chip can transmit, which is printable ASCII.
        case asciiPrintable
        /// The sixteen hexadecimal digits, raised to upper case as they are typed.
        case hexDigits

        func accept(_ character: Character) -> Character? {
            switch self {
            case .asciiPrintable:
                guard let ascii = character.asciiValue, (0x20..<0x7F).contains(ascii) else { return nil }
                return character
            case .hexDigits:
                guard character.isHexDigit else { return nil }
                return Character(character.uppercased())
            }
        }
    }
}

// MARK: - Geometry

extension CharacterCellsField {

    /// The sizes the field is drawn from, kept together so the cell and the field cannot
    /// disagree about them.
    struct Metrics {
        let fontSize: CGFloat
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let troughDepth: CGFloat

        /// How far the text is taken back from the colour the hex dump uses.
        var textDimming: Double = 0.78

        /// How much room stays below the baseline.
        ///
        /// Taken from the font rather than picked, because the trough is drawn at the
        /// baseline and whatever hangs below it, the tail of a g or a y, needs somewhere to
        /// go inside the cell.
        var descenderRoom: CGFloat {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            return (-font.descender).rounded(.up)
        }

        /// Where the trough floor sits, measured up from the bottom of the cell.
        ///
        /// The half point keeps the line on a single row of pixels instead of spreading it
        /// over two.
        var troughInset: CGFloat { descenderRoom + 0.5 }

        /// Where the baseline sits, measured up from the bottom of the cell.
        ///
        /// Both numbers come from the same place, which is what puts the characters in the
        /// troughs rather than above them. The gap keeps the glyphs from touching the line
        /// they stand on, the way handwriting clears a ruled one.
        var baselineInset: CGFloat { troughInset + 2 }

        static let standard = Metrics(fontSize: 17, cellWidth: 17, cellHeight: 30, troughDepth: 7)
    }
}

// MARK: - Private

private extension CharacterCellsField {

    var selection: Range<Int> {
        min(anchor, caret)..<max(anchor, caret)
    }

    var hasSelection: Bool {
        anchor != caret
    }

    var cells: some View {
        GeometryReader { geometry in
            let places = max(capacity, Int(geometry.size.width / Metrics.standard.cellWidth))
            HStack(spacing: 0) {
                ForEach(0..<places, id: \.self) { index in
                    CharacterCellView(
                        character: character(at: index),
                        isUsable: index < capacity,
                        isSelected: selection.contains(index) && isFocused,
                        showsCaret: isFocused && caret == index && !hasSelection && caretVisible,
                        metrics: Metrics.standard
                    )
                }
            }
        }
        .frame(height: Metrics.standard.cellHeight)
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isFocused = true
                    if !isDragging {
                        isDragging = true
                        anchor = index(atHorizontal: value.startLocation.x)
                    }
                    caret = index(atHorizontal: value.location.x)
                    caretVisible = true
                }
                .onEnded { _ in isDragging = false }
        )
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                caret = min(caret, text.count)
                anchor = caret
                caretVisible = true
            }
        }
        .onReceive(blink) { _ in
            caretVisible.toggle()
        }
        .onAppear {
            caret = text.count
            anchor = caret
        }
    }

    func character(at index: Int) -> Character? {
        guard index < text.count else { return nil }
        return text[text.index(text.startIndex, offsetBy: index)]
    }

    func index(atHorizontal position: CGFloat) -> Int {
        let place = Int((position / Metrics.standard.cellWidth).rounded())
        return max(0, min(text.count, place))
    }

    // MARK: Keys

    /// Everything the field does with a key.
    ///
    /// Anything it does not claim is handed back, so Tab still moves on and the window's
    /// own shortcuts keep working.
    func handle(_ press: KeyPress) -> KeyPress.Result {
        caretVisible = true

        if press.modifiers.contains(.command) {
            return handleCommand(press)
        }

        // Backspace and forward delete arrive as control characters. Matching on those as
        // well as on the key is deliberate: the key alone has been unreliable here.
        if press.characters == "\u{7F}" || press.characters == "\u{8}" || press.key == .delete {
            deleteBackwards()
            return .handled
        }
        if press.characters == "\u{F728}" || press.key == .deleteForward {
            deleteForwards()
            return .handled
        }

        let extending = press.modifiers.contains(.shift)

        switch press.key {
        case .leftArrow:
            move(to: press.modifiers.contains(.option) ? wordStart() : max(0, caret - 1), extending: extending)
            return .handled
        case .rightArrow:
            move(to: press.modifiers.contains(.option) ? wordEnd() : min(text.count, caret + 1), extending: extending)
            return .handled
        case .upArrow, .home:
            move(to: 0, extending: extending)
            return .handled
        case .downArrow, .end:
            move(to: text.count, extending: extending)
            return .handled
        case .tab, .return, .escape:
            return .ignored
        default:
            return insert(press.characters)
        }
    }

    func handleCommand(_ press: KeyPress) -> KeyPress.Result {
        switch press.characters {
        case "a":
            anchor = 0
            caret = text.count
            return .handled
        case "c":
            copySelection()
            return .handled
        case "x":
            copySelection()
            deleteSelection()
            return .handled
        case "v":
            guard let pasted = NSPasteboard.general.string(forType: .string) else { return .handled }
            return insert(pasted)
        case "\u{7F}", "\u{8}":
            // Command and backspace clears the line, as it does in a text field.
            text = ""
            caret = 0
            anchor = 0
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Editing

    func move(to position: Int, extending: Bool) {
        caret = position
        if !extending {
            anchor = position
        }
    }

    func wordStart() -> Int {
        var position = caret
        while position > 0, character(at: position - 1) == " " { position -= 1 }
        while position > 0, character(at: position - 1) != " " { position -= 1 }
        return position
    }

    func wordEnd() -> Int {
        var position = caret
        while position < text.count, character(at: position) == " " { position += 1 }
        while position < text.count, character(at: position) != " " { position += 1 }
        return position
    }

    func insert(_ entered: String) -> KeyPress.Result {
        let accepted = String(entered.compactMap(allowed.accept))
        guard !accepted.isEmpty else { return .ignored }

        deleteSelection()

        let room = capacity - text.count
        guard room > 0 else { return .handled }

        let fitting = String(accepted.prefix(room))
        text.insert(contentsOf: fitting, at: text.index(text.startIndex, offsetBy: caret))
        caret += fitting.count
        anchor = caret
        return .handled
    }

    func deleteBackwards() {
        if hasSelection {
            deleteSelection()
            return
        }
        guard caret > 0 else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: caret - 1))
        caret -= 1
        anchor = caret
    }

    func deleteForwards() {
        if hasSelection {
            deleteSelection()
            return
        }
        guard caret < text.count else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: caret))
        anchor = caret
    }

    func deleteSelection() {
        guard hasSelection else { return }
        let range = selection
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        text.removeSubrange(lower..<upper)
        caret = range.lowerBound
        anchor = caret
    }

    func copySelection() {
        let range = hasSelection ? selection : 0..<text.count
        guard !range.isEmpty else { return }
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(text[lower..<upper]), forType: .string)
    }
}

/// The trough one character stands in: a floor on the baseline with a tine at each end.
///
/// A shape rather than a `Canvas`, because a shape is a view like any other and renders
/// wherever one does, including into an image.
private struct TroughShape: Shape {

    // MARK: Properties

    let depth: CGFloat

    /// How far the floor sits above the bottom of the cell. The half point in it keeps the
    /// line on one row of pixels rather than spreading it over two.
    let floorInset: CGFloat

    // MARK: Shape

    func path(in rect: CGRect) -> Path {
        let floor = rect.maxY - floorInset
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.5, y: floor - depth))
        path.addLine(to: CGPoint(x: rect.minX + 0.5, y: floor))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: floor))
        path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: floor - depth))
        return path
    }
}

/// One character place: the glyph if there is one, and the trough underneath.
///
/// A place beyond what the field holds is drawn faintly. It shows where the row ends
/// without pretending that something could be typed there.
private struct CharacterCellView: View {

    // MARK: Properties

    let character: Character?
    let isUsable: Bool
    let isSelected: Bool
    let showsCaret: Bool
    let metrics: CharacterCellsField.Metrics

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(
                        width: metrics.cellWidth,
                        height: metrics.fontSize + metrics.descenderRoom + 2
                    )
                    .padding(.bottom, 0.5)
            }

            TroughShape(depth: metrics.troughDepth, floorInset: metrics.troughInset)
                .stroke(Color.secondary.opacity(isUsable ? 1 : 0.3), lineWidth: 1)

            if let character {
                Text(String(character))
                    .font(.system(size: metrics.fontSize, design: .monospaced))
                    .foregroundStyle(Color.terminalGreen.opacity(metrics.textDimming))
                    .frame(width: metrics.cellWidth)
                    // The baseline rather than the frame decides where the glyph goes, so it
                    // stands on the trough floor the way writing stands on a ruled line.
                    .alignmentGuide(.bottom) { $0[.firstTextBaseline] + metrics.baselineInset }
            }

            if showsCaret {
                Rectangle()
                    .fill(Color.terminalGreen.opacity(metrics.textDimming))
                    .frame(width: 2, height: metrics.fontSize + 2)
                    .padding(.bottom, metrics.baselineInset)
            }
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
    }
}
