import SwiftUI

/// The fields a person may change, and the two that are fixed.
///
/// The sections are built here rather than taken from a `Form`, because a grouped form
/// insets its own content and the rest of the window does not, which left the panels and
/// the hex dump at two different widths.
struct DescriptorFormView: View {

    // MARK: Properties

    @Binding var descriptor: DescriptorBlock
    @Binding var serialNumber: SerialNumberBlock

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PanelView {
                CharacterCellsField(
                    label: "Product name",
                    symbol: "tag",
                    capacity: DescriptorBlock.productStringLength,
                    text: $descriptor.productString
                )

                CharacterCellsField(
                    label: "Manufacturer",
                    symbol: "building.2",
                    capacity: DescriptorBlock.vendorStringLength,
                    text: $descriptor.vendorString
                )
            }

            HStack(alignment: .top, spacing: 16) {
                PanelView(fillsHeight: true) {
                    ProductIDFieldView(value: $descriptor.productID)

                    Text("Leave this as it is. It is the number a host reads beside the vendor, and the Sound Settings show the product name above rather than this. Give a second board its own only when a program has to tell the two apart.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PanelView(fillsHeight: true) {
                    CharacterCellsField(
                        label: "Serial number",
                        symbol: "barcode",
                        capacity: SerialNumberBlock.textLength,
                        text: $serialNumber.text
                    )

                    Text("Yours alone. It is stored past what the audio chip reads, so no host ever sees it, and reading the board brings it back.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            PanelView {
                Label {
                    LabeledContent("Power") {
                        Text("Bus-powered, up to 500 mA")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bolt")
                        .symbolRenderingMode(.hierarchical)
                }

                Text("This has to match how the board is wired, so it is fixed. The audio chip misbehaves when the descriptor claims something the board does not do.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The product identifier, entered as four hexadecimal digits.
///
/// It uses the same field as the two names above, so the window has one way of taking
/// text rather than two. The digits are kept apart from the value whilst typing: a
/// half-finished entry stays on screen, and only a readable one reaches the block.
private struct ProductIDFieldView: View {

    // MARK: Properties

    @Binding var value: UInt16

    @State private var digits = ""

    // MARK: Body

    var body: some View {
        CharacterCellsField(
            label: "Product ID",
            symbol: "number",
            capacity: 4,
            allowed: .hexDigits,
            prefix: "0x",
            text: $digits
        )
        .onAppear { digits = Self.format(value) }
        .onChange(of: digits) { _, entered in
            if let parsed = UInt16(entered, radix: 16) {
                value = parsed
            }
        }
    }

    // MARK: Conversion

    private static func format(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }
}

/// A section of the window: full width, rounded, set a shade below the background.
///
/// Every panel is built the same way so that the window has one measure rather than
/// several, which is what a grouped form quietly broke. That extends to the fill, which is
/// the same in all of them: a panel that differs in colour claims a rank it does not have.
struct PanelView<Content: View>: View {

    // MARK: Properties

    /// Whether the panel fills the height it is offered.
    ///
    /// Two panels beside each other hold texts of different lengths, and without this the
    /// shorter one would stop short of the other and the row would look unfinished.
    var fillsHeight = false

    @ViewBuilder let content: Content

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(ProgrammerView.Layout.panelPadding)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .background(Color.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
