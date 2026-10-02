import Foundation

/// What the chip on the bus turned out to be, as far as reading it can tell.
///
/// A 24-series EEPROM carries no identification register, so its type cannot be asked for.
/// Two things can be measured without writing anything, and between them they catch the
/// mistake that matters: a part the audio chip cannot read.
struct EEPROMIdentity: Equatable, Sendable {

    // MARK: Types

    /// What the wrap-around measurement found.
    enum Addressing: Equatable, Sendable {
        /// The counter came back to the start after 256 bytes, so one address byte reaches
        /// every cell, which is what the PCM2704C expects.
        case singleByte

        /// The counter ran past 256 bytes. Either the part is larger than 2 kbit, or it
        /// wants two address bytes and has been answering from somewhere else throughout.
        /// The audio chip reads neither correctly.
        case notSingleByte

        /// The bytes compared were all alike, so the measurement says nothing. An
        /// unprogrammed chip reads `0xFF` everywhere and lands here.
        case undetermined
    }

    // MARK: Properties

    /// Which of the eight addresses from 0x50 acknowledged.
    let answeringAddresses: [UInt8]

    let addressing: Addressing

    /// How many bytes the part holds, as the number of answering addresses implies it.
    ///
    /// A 2 kbit part takes one address, a 4 kbit two, an 8 kbit four and a 16 kbit eight,
    /// because the family uses the low address bits as memory address bits from 4 kbit up.
    var capacity: Int { answeringAddresses.count * 256 }

    /// Whether the board's own EEPROM answered at all.
    var isPresent: Bool { answeringAddresses.contains(EEPROM.address) }

    /// One line for the window.
    var summary: String {
        guard isPresent else {
            return String(localized: "No EEPROM answering between 0x50 and 0x57.")
        }

        let place = String(localized: "\(capacity) bytes at 0x50")
        switch addressing {
        case .singleByte:
            return String(localized: "\(place), one address byte.")
        case .notSingleByte:
            return String(localized: "\(place) answering, but the address counter runs past 256. The audio chip reads only single-byte addressing.")
        case .undetermined:
            return String(localized: "\(place). The chip reads alike throughout, so its addressing cannot be told apart.")
        }
    }
}
