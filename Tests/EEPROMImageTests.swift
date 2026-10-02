import Testing
@testable import Prommer

/// The image decides two things that fail silently when they are wrong: where the mirroring
/// stops, and what a board gets to keep when only part of it is written.
struct EEPROMImageTests {

    // MARK: Serial number

    @Test("The serial number starts where the audio chip stops reading")
    func serialNumberSitsPastTheDescriptor() {
        #expect(SerialNumberBlock.origin == DescriptorBlock.length)
    }

    @Test("The serial number is stored the right way round")
    func serialNumberIsNotMirrored() throws {
        let image = try EEPROMImage(
            descriptor: DescriptorBlock(),
            serialNumber: SerialNumberBlock(text: "SBM-0001")
        )
        let stored = Array(image.payload[SerialNumberBlock.origin...])

        #expect(Array(stored.prefix(2)) == Array("SN".utf8))
        #expect(String(bytes: stored.dropFirst(2), encoding: .ascii) == "SBM-0001        ")
    }

    @Test("A serial number survives being written and read back")
    func serialNumberRoundTrip() throws {
        let image = try EEPROMImage(
            descriptor: DescriptorBlock(),
            serialNumber: SerialNumberBlock(text: "SBM-0042")
        )
        let readable = EEPROMImage.readable(from: image.payload)

        #expect(SerialNumberBlock.decoded(from: readable)?.text == "SBM-0042")
    }

    @Test("A chip without the marker reports no serial number")
    func serialNumberNeedsItsMarker() {
        let blank = [UInt8](repeating: 0xFF, count: EEPROM.capacity)
        #expect(SerialNumberBlock.decoded(from: blank) == nil)
    }

    @Test("A serial number longer than its field is refused")
    func overlongSerialNumber() {
        let block = SerialNumberBlock(text: "SBM-00000000-0001-X")
        #expect(throws: DescriptorError.self) {
            try block.encoded()
        }
    }

    // MARK: Descriptor round trip

    @Test("The descriptor survives being written and read back")
    func descriptorRoundTrip() throws {
        let original = DescriptorBlock(
            productID: 0xBEEF,
            productString: "NeXT Sound Box",
            vendorString: "LAYERED.work"
        )
        let image = try EEPROMImage(descriptor: original, serialNumber: SerialNumberBlock())
        let readable = EEPROMImage.readable(from: image.payload)

        #expect(DescriptorBlock.decoded(from: readable) == original)
    }

    @Test("An unprogrammed chip reports no descriptor rather than an empty one")
    func blankChipHasNoDescriptor() {
        // Reading 0xFF as a descriptor would wipe whatever the window was holding, which is
        // exactly what happens on a board nobody has written yet.
        let blank = [UInt8](repeating: 0xFF, count: EEPROM.capacity)
        #expect(DescriptorBlock.decoded(from: blank) == nil)
    }

    // MARK: The page

    @Test("The page covers the whole chip, however little is written")
    func pageCoversTheChip() throws {
        let image = try EEPROMImage(descriptor: DescriptorBlock(), serialNumber: SerialNumberBlock())

        #expect(image.page.count == EEPROM.capacity)
        #expect(image.payload.count == DescriptorBlock.length + SerialNumberBlock.length)
    }

    @Test("What nobody has read stays unknown rather than becoming zero")
    func unreadBytesAreUnknown() throws {
        let image = try EEPROMImage(descriptor: DescriptorBlock(), serialNumber: SerialNumberBlock())

        #expect(image.page[image.payload.count] == nil)
        #expect(image.page[EEPROM.capacity - 1] == nil)
    }

    @Test("What the board already carries fills the rest of the page")
    func existingBytesFillThePage() throws {
        var existing = [UInt8](repeating: 0x00, count: EEPROM.capacity)
        existing[200] = 0xAB

        let image = try EEPROMImage(
            descriptor: DescriptorBlock(),
            serialNumber: SerialNumberBlock(),
            existing: existing
        )

        #expect(image.page[200] == 0xAB)
        // The first bytes come from the form, not from the chip.
        #expect(image.page[0] == image.payload[0])
    }

    @Test("An unknown byte shows as dashes rather than as a value")
    func unknownBytesInTheDump() {
        let bytes: [UInt8?] = [0x41, nil]
        let line = HexDump.string(for: bytes)

        #expect(line.hasPrefix("00  41 \(HexDump.unknown)"))
        #expect(line.hasSuffix("A "))
    }
}
