import Foundation

/// What goes into the chip, and the whole chip as the window shows it.
///
/// The two halves of what is written are stored differently. The descriptor is mirrored,
/// because the audio chip clocks the ROM LSB first; the serial number is not, because the
/// audio chip never reads it. Carrying both views together is what keeps that from having
/// to be worked out again at every place the bytes are shown.
struct EEPROMImage: Equatable, Sendable {

    // MARK: Properties

    /// The bytes to write, from address zero. Only as many as actually change, because an
    /// EEPROM has a finite number of write cycles and the rest of the page holds nothing.
    let payload: [UInt8]

    /// The whole chip as it stands in the hex column, `nil` where nothing is known yet.
    ///
    /// Past the payload this is whatever the chip last read back, and until a board has
    /// been read there is nothing to put there.
    let page: [UInt8?]

    /// The same page turned the right way round, which is what the text column shows.
    let readablePage: [UInt8?]

    // MARK: Initialisers

    /// Assemble the image from what the audio chip reads, what only a person reads, and
    /// what already stood on the chip.
    ///
    /// - Parameters:
    ///   - descriptor: The seven fields the PCM2704C overrides.
    ///   - serialNumber: The label stored past them.
    ///   - existing: The chip as it was last read, which fills the rest of the page.
    /// - Throws: ``DescriptorError`` from either block.
    init(
        descriptor: DescriptorBlock,
        serialNumber: SerialNumberBlock,
        existing: [UInt8] = []
    ) throws {
        let written = try descriptor.encoded().map(\.bitsReversed) + serialNumber.encoded()
        let whole: [UInt8?] = (0..<EEPROM.capacity).map { offset in
            if offset < written.count { return written[offset] }
            return offset < existing.count ? existing[offset] : nil
        }

        payload = written
        page = whole
        readablePage = Self.readable(from: whole)
    }
}

// MARK: - Decoding

extension EEPROMImage {

    /// Turn bytes that came out of a chip the right way round.
    ///
    /// Where the mirroring stops is stated here and nowhere else, so a dump of what was just
    /// read and a dump of what is about to be written cannot disagree about it.
    ///
    /// - Parameter stored: Bytes as they sit in the chip, counted from address zero.
    /// - Returns: The same count of bytes, as a reader should see them.
    static func readable(from stored: [UInt8?]) -> [UInt8?] {
        stored.enumerated().map { offset, byte in
            guard let byte else { return nil }
            return offset < SerialNumberBlock.origin ? byte.bitsReversed : byte
        }
    }

    /// The same, for bytes that are all known.
    static func readable(from stored: [UInt8]) -> [UInt8] {
        readable(from: stored.map(Optional.some)).compactMap { $0 }
    }
}
