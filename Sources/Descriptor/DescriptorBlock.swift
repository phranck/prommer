import Foundation

/// The block of configuration bytes that the PCM2704C reads out of its EEPROM.
///
/// The chip reads the block once after every power-on reset and uses it to override
/// seven fields of its built-in USB descriptors. The fields sit back to back from
/// address `0x00` with no padding and no length prefixes, so every one of them has to
/// hit its exact size: a string one character short shifts everything behind it and the
/// chip reads the wrong field.
///
/// An unprogrammed EEPROM reads back as `0xFF` in every cell, which is why an untouched
/// board enumerates with vendor ID `0xFFFF`, product ID `0xFFFF` and a product string of
/// sixteen `0xFF` bytes.
///
/// Reference: Texas Instruments SBFS036B, sections 9.3.7 and 9.3.8.
struct DescriptorBlock: Equatable, Sendable {

    // MARK: Layout

    /// Total size of the block as SBFS036B prescribes it.
    static let length = 57

    /// Size of the product string field. The chip reads exactly this many bytes and
    /// converts them to Unicode for the host, so a terminator would reach the host as a
    /// visible character. Short strings are padded with spaces instead.
    static let productStringLength = 16

    /// Size of the vendor string field, padded the same way as the product string.
    static let vendorStringLength = 32

    /// `bmAttributes` for a bus-powered function that cannot wake the host. Bit 7 is
    /// reserved and always set, bit 6 would mean self-powered and bit 5 remote wakeup.
    /// This has to agree with PSEL, which sits at VDD on the board and selects bus power.
    static let busPoweredAttributes: UInt8 = 0x80

    /// `bMaxPower` in 2 mA units. The HOST pin sits at +5V_USB, which selects the 500 mA
    /// class, and the descriptor has to name the same figure or the chip may misbehave.
    static let maxPower500mA: UInt8 = 0xFA

    /// Usage ID of the auxiliary HID status flag in the report descriptor's three-byte
    /// form. AL A/V Capture is TI's default and the board leaves the HID pins open.
    static let auxiliaryHIDUsage: [UInt8] = [0x0A, 0x93, 0x01]

    // MARK: Defaults

    /// Texas Instruments' own vendor ID, which the chip reports with no EEPROM at all.
    /// A vendor ID of one's own has to be bought from the USB-IF.
    static let defaultVendorID: UInt16 = 0x08BB

    /// The product ID from the example in SBFS036B, which the Sound Box mini keeps.
    static let defaultProductID: UInt16 = 0x2704

    static let defaultProductString = "NeXT Sound Box"
    static let defaultVendorString = "LAYERED.work"

    // MARK: Properties

    /// Texas Instruments owns this one, and the chip reports it with no EEPROM at all.
    /// It is not a free choice: a vendor ID of one's own is bought from the USB-IF.
    let vendorID: UInt16

    /// What the host will call this product.
    ///
    /// This identifies the board, not the chip on it: the audio chip reads this value out
    /// of the EEPROM rather than carrying one of its own, so a board built around a
    /// PCM2706C works the same way. Two products that a host should tell apart need two
    /// different values here.
    var productID: UInt16

    var productString: String
    var vendorString: String

    // MARK: Initialisers

    init(
        vendorID: UInt16 = DescriptorBlock.defaultVendorID,
        productID: UInt16 = DescriptorBlock.defaultProductID,
        productString: String = DescriptorBlock.defaultProductString,
        vendorString: String = DescriptorBlock.defaultVendorString
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.productString = productString
        self.vendorString = vendorString
    }
}

// MARK: - Encoding

extension DescriptorBlock {

    /// The block in the order a reader expects it, before any mirroring for the EEPROM.
    ///
    /// The mirroring belongs to ``EEPROMImage``, which is where the serial number behind
    /// this block decides that it stops. Keeping it out of here means the block can be
    /// printed and checked by eye against the data sheet.
    ///
    /// - Returns: Exactly ``length`` bytes.
    /// - Throws: ``DescriptorError`` when a string exceeds its field or carries a
    ///   character the chip cannot transmit.
    func encoded() throws -> [UInt8] {
        let product = try Self.field(
            productString,
            width: Self.productStringLength,
            name: .productName
        )
        let vendor = try Self.field(
            vendorString,
            width: Self.vendorStringLength,
            name: .manufacturer
        )

        var block: [UInt8] = []
        block.append(contentsOf: Self.littleEndian(vendorID))
        block.append(contentsOf: Self.littleEndian(productID))
        block.append(contentsOf: product)
        block.append(contentsOf: vendor)
        block.append(Self.busPoweredAttributes)
        block.append(Self.maxPower500mA)
        block.append(contentsOf: Self.auxiliaryHIDUsage)

        guard block.count == Self.length else {
            throw DescriptorError.wrongBlockLength(block.count)
        }
        return block
    }

}

// MARK: - Decoding

extension DescriptorBlock {

    /// Read a block back out of what a chip returned.
    ///
    /// - Parameter readable: Bytes from address zero, already turned the right way round by
    ///   ``EEPROMImage/readable(from:)-(_)``.
    /// - Returns: The block, or `nil` where the chip holds no descriptor. An unprogrammed
    ///   part reads `0xFF` throughout and would otherwise come back as a vendor ID of
    ///   `0xFFFF` and two empty names, wiping what the window was holding.
    static func decoded(from readable: [UInt8]) -> DescriptorBlock? {
        guard readable.count >= length else { return nil }

        let vendorID = UInt16(readable[0]) | UInt16(readable[1]) << 8
        guard vendorID != 0xFFFF else { return nil }

        let productEnd = 4 + productStringLength
        let vendorEnd = productEnd + vendorStringLength

        return DescriptorBlock(
            vendorID: vendorID,
            productID: UInt16(readable[2]) | UInt16(readable[3]) << 8,
            productString: text(Array(readable[4..<productEnd])),
            vendorString: text(Array(readable[productEnd..<vendorEnd]))
        )
    }
}

// MARK: - Private

private extension DescriptorBlock {

    /// A fixed-width field as the text it holds, with the padding and any byte the chip
    /// cannot transmit left out.
    static func text(_ bytes: [UInt8]) -> String {
        let printable = bytes.filter { (0x20..<0x7F).contains($0) }
        return String(bytes: printable, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Render a string into a fixed-width ASCII field, padded with spaces.
    static func field(_ value: String, width: Int, name: DescriptorError.Field) throws -> [UInt8] {
        guard value.count <= width else {
            throw DescriptorError.stringTooLong(field: name, limit: width, actual: value.count)
        }
        let padded = value.padding(toLength: width, withPad: " ", startingAt: 0)
        guard let ascii = padded.data(using: .ascii) else {
            throw DescriptorError.stringNotASCII(field: name)
        }
        return Array(ascii)
    }

    static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0x00FF), UInt8(value >> 8)]
    }
}
