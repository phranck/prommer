import Foundation

/// A label the board carries but never shows.
///
/// The PCM2704C reads exactly ``DescriptorBlock/length`` bytes from address zero and stops,
/// so everything past that is invisible to the chip and reaches no host. This block lives
/// there. It is for the board itself: something written once that comes back on the next
/// read, such as a serial number, a batch, or a build date.
///
/// Unlike the descriptor, these bytes are stored the right way round. The mirroring exists
/// only because the audio chip clocks the ROM LSB first, and the audio chip never sees
/// these, so mirroring them would make them unreadable to every ordinary I2C tool.
struct SerialNumberBlock: Equatable, Sendable {

    // MARK: Layout

    /// The first address past what the audio chip reads.
    static let origin = DescriptorBlock.length

    /// Tells a written block apart from whatever stood in the chip before.
    ///
    /// An unprogrammed cell reads `0xFF`, and a board programmed before this field existed
    /// holds whatever its EEPROM shipped with. Without a marker both would be shown as text.
    static let marker: [UInt8] = Array("SN".utf8)

    /// How many characters the field holds. Sixteen is what the product string takes, so
    /// both fields draw the same number of places.
    static let textLength = 16

    /// Marker plus text.
    static var length: Int { marker.count + textLength }

    // MARK: Properties

    var text: String

    // MARK: Initialisers

    init(text: String = "") {
        self.text = text
    }
}

// MARK: - Encoding

extension SerialNumberBlock {

    /// The block as it sits in the EEPROM, marker first.
    ///
    /// - Returns: Exactly ``length`` bytes, to be written from ``origin``.
    /// - Throws: ``DescriptorError`` when the text is too long or not ASCII.
    func encoded() throws -> [UInt8] {
        guard text.count <= Self.textLength else {
            throw DescriptorError.stringTooLong(
                field: .serialNumber,
                limit: Self.textLength,
                actual: text.count
            )
        }
        let padded = text.padding(toLength: Self.textLength, withPad: " ", startingAt: 0)
        guard let ascii = padded.data(using: .ascii) else {
            throw DescriptorError.stringNotASCII(field: .serialNumber)
        }
        return Self.marker + Array(ascii)
    }

    /// Read a block back out of what a chip returned.
    ///
    /// - Parameter bytes: Everything read from address zero, however much of it there is.
    /// - Returns: The block, or `nil` where the marker is absent, which means nothing was
    ///   ever written there.
    static func decoded(from bytes: [UInt8]) -> SerialNumberBlock? {
        let end = origin + length
        guard bytes.count >= end else { return nil }
        guard Array(bytes[origin..<(origin + marker.count)]) == marker else { return nil }

        let textBytes = Array(bytes[(origin + marker.count)..<end])
        guard let text = String(bytes: textBytes, encoding: .ascii) else { return nil }
        return SerialNumberBlock(text: text.trimmingCharacters(in: .whitespaces))
    }
}
