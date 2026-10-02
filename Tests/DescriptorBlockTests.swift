import Testing
@testable import Prommer

/// The descriptor block is the one part of this app that can be wrong silently: a board
/// with a shifted block enumerates and simply reports nonsense. These tests pin the
/// layout against SBFS036B rather than against what the code happens to do.
struct DescriptorBlockTests {

    @Test("The block is exactly 57 bytes")
    func blockLength() throws {
        let block = try DescriptorBlock().encoded()
        #expect(block.count == DescriptorBlock.length)
    }

    @Test("The identifiers sit at the front, low byte first")
    func identifierOrder() throws {
        let block = try DescriptorBlock(vendorID: 0x08BB, productID: 0x2704).encoded()
        #expect(Array(block[0..<4]) == [0xBB, 0x08, 0x04, 0x27])
    }

    @Test("A product identifier of one's own survives the whole chain")
    func ownProductIdentifier() throws {
        // The identifier belongs to the board, not to the chip on it, so a second product
        // picks its own number and everything behind it has to shift by nothing at all.
        let block = DescriptorBlock(productID: 0xBEEF)
        let plain = try block.encoded()
        #expect(Array(plain[2..<4]) == [0xEF, 0xBE])
        #expect(plain.count == DescriptorBlock.length)

        let payload = try EEPROMImage(descriptor: block, serialNumber: SerialNumberBlock()).payload
        #expect(Array(payload[2..<4]) == [UInt8(0xEF).bitsReversed, UInt8(0xBE).bitsReversed])
    }

    @Test("Short strings are padded with spaces, not terminated")
    func stringPadding() throws {
        let block = try DescriptorBlock(productString: "NeXT").encoded()
        let field = Array(block[4..<20])
        #expect(field.count == 16)
        #expect(String(bytes: field, encoding: .ascii) == "NeXT            ")
    }

    @Test("The vendor string occupies its full 32 bytes")
    func vendorField() throws {
        let block = try DescriptorBlock(vendorString: "LAYERED.work").encoded()
        let field = Array(block[20..<52])
        let expected = "LAYERED.work".padding(toLength: 32, withPad: " ", startingAt: 0)
        #expect(String(bytes: field, encoding: .ascii) == expected)
    }

    @Test("Power attributes and maximum current follow the strings")
    func powerFields() throws {
        let block = try DescriptorBlock().encoded()
        #expect(block[52] == 0x80)
        #expect(block[53] == 0xFA)
        #expect(Int(block[53]) * 2 == 500)
    }

    @Test("The auxiliary HID usage closes the block")
    func auxiliaryUsage() throws {
        let block = try DescriptorBlock().encoded()
        #expect(Array(block[54..<57]) == [0x0A, 0x93, 0x01])
    }

    @Test("A string longer than its field is refused")
    func overlongString() {
        let block = DescriptorBlock(productString: "This name is far too long")
        #expect(throws: DescriptorError.self) {
            try block.encoded()
        }
    }

    @Test("Anything outside ASCII is refused")
    func nonASCII() {
        let block = DescriptorBlock(productString: "Grüße")
        #expect(throws: DescriptorError.self) {
            try block.encoded()
        }
    }

    @Test("Every byte of the descriptor reaches the EEPROM mirrored")
    func mirroring() throws {
        let block = DescriptorBlock()
        let plain = try block.encoded()
        let payload = Array(try EEPROMImage(descriptor: block, serialNumber: SerialNumberBlock()).payload.prefix(DescriptorBlock.length))

        #expect(payload.count == plain.count)
        // A protocol capture of a working board shows the vendor ID 0x08BB stored as the
        // two bytes 0xDD and 0x10, which is exactly 0xBB and 0x08 mirrored. That capture
        // comes from outside this project, so it checks the mirroring rule itself rather
        // than only checking the code against itself.
        #expect(Array(payload[0..<2]) == [0xDD, 0x10])
        #expect(payload.map(\.bitsReversed) == plain)
    }

    @Test("The dump shows stored bytes beside the characters the chip reads")
    func dumpColumns() throws {
        let image = try EEPROMImage(
            descriptor: DescriptorBlock(productString: "NeXT"),
            serialNumber: SerialNumberBlock()
        )
        let dump = HexDump.string(for: image.page, characters: image.readablePage)
        let firstLine = dump.split(separator: "\n")[0]

        // The hex column shows what sits in the memory, which is mirrored.
        #expect(firstLine.hasPrefix("00  DD 10"))
        // The character column shows the same bytes as the chip receives them.
        #expect(firstLine.hasSuffix("...'NeXT        "))
    }

    @Test("Mirroring a byte twice returns the original")
    func mirroringIsAnInvolution() {
        for value in UInt8.min...UInt8.max {
            #expect(value.bitsReversed.bitsReversed == value)
        }
    }

    @Test("A space mirrors to 0x04, which is what pads the string fields")
    func spaceMirrors() {
        #expect(UInt8(0x20).bitsReversed == 0x04)
    }
}
