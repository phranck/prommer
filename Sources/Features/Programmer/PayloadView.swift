import AppKit
import SwiftUI

/// The bytes as they will sit in the EEPROM, or why they cannot be built.
struct PayloadView: View {

    // MARK: Properties

    let image: Swift.Result<EEPROMImage, DescriptorError>
    let identity: EEPROMIdentity?

    // MARK: Body

    var body: some View {
        PanelView {
            Label("EEPROM content", systemImage: "memorychip")
                .symbolRenderingMode(.hierarchical)
                .font(.headline)

            switch image {
            case let .success(image):
                HexDumpView(bytes: image.page, characters: image.readablePage)
                Text("The whole chip. The first \(image.payload.count) bytes are what gets written, and the rest is what the board already carries. The hex column is what sits in the EEPROM, mirrored for the audio chip up to the serial number; the text column is the same bytes as they are meant to be read.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case let .failure(error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }

            if let identity {
                Label(
                    identity.summary,
                    systemImage: identity.isPresent ? "checkmark.seal" : "questionmark.circle"
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The bytes as hexadecimal, set as large as the card is wide.
///
/// A dump is a table, so it is sized by its longest line rather than by a type scale: the
/// point size follows from the width a panel offers divided by the characters a line
/// holds. The width is a constant rather than a measurement, because measuring the space
/// a text is about to fill and then sizing that text to the result is a loop.
private struct HexDumpView: View {

    // MARK: Properties

    /// The bytes as they sit in the chip, which is what the hex column shows.
    let bytes: [UInt8?]

    /// The same bytes turned the right way round, which is what the text column shows.
    let characters: [UInt8?]

    /// Offset, sixteen hexadecimal pairs with a wider gap after the eighth, and sixteen
    /// readable characters.
    private static let charactersPerLine: CGFloat = 71

    /// How wide one character of the monospaced system font is per point of size.
    ///
    /// Taken from the font rather than assumed, because the whole calculation rests on it.
    private static let advanceRatio: CGFloat = {
        let reference: CGFloat = 100
        let font = NSFont.monospacedSystemFont(ofSize: reference, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width / reference
    }()

    private static let fontSize: CGFloat = {
        let advance = ProgrammerView.Layout.panelContentWidth / charactersPerLine
        return (advance / advanceRatio).rounded(.down)
    }()

    // MARK: Body

    var body: some View {
        Text(HexDump.string(for: bytes, characters: characters))
            .font(.system(size: Self.fontSize, design: .monospaced))
            .foregroundStyle(Color.terminalGreen)
            .textSelection(.enabled)
            .fixedSize()
    }
}
