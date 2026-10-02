import Foundation

/// The M24C02 on the Sound Box, reached through an ``MCP2221`` on J1.
///
/// The board's audio chip must be unpowered whilst this runs. It drives its ROM clock as
/// a push-pull output rather than an open collector and never releases the line, so for
/// as long as it has power no other master reaches the EEPROM. Unplugging USB is the
/// whole point of J1: pin 2 feeds the 3.3 V rail, which supplies the EEPROM, its two
/// pull-ups and nothing else.
@MainActor
struct EEPROM {

    // MARK: Properties

    /// Seven-bit address with E0, E1 and E2 tied to ground. The PCM2704C looks for its
    /// ROM at 0xA0, which is this value shifted left by one.
    nonisolated static let address: UInt8 = 0x50

    /// A write that crosses a page boundary wraps around inside the page instead of
    /// carrying into the next one, so every write is split on this grid.
    static let pageSize = 16

    /// Maximum write cycle of the M24C02. The part does not answer at all whilst a page
    /// is being burnt, so a write that follows too closely is simply lost.
    static let writeCycle = Duration.milliseconds(6)

    /// The eight addresses a 24-series part can take, with E0, E1 and E2 deciding which.
    /// A part larger than 2 kbit answers at several of them, which is how its size shows.
    nonisolated static let addressRange: ClosedRange<UInt8> = 0x50...0x57

    /// How many bytes the M24C02 holds, which is also where its address counter wraps.
    nonisolated static let capacity = 256

    private let adapter: MCP2221

    // MARK: Initialisers

    init(adapter: MCP2221) {
        self.adapter = adapter
    }
}

// MARK: - Transfers

extension EEPROM {

    /// Store bytes from address zero, one page at a time.
    ///
    /// - Parameters:
    ///   - payload: The bytes exactly as they should sit in the chip.
    ///   - progress: Called after each page with a fraction between zero and one.
    func write(_ payload: [UInt8], progress: @Sendable (Double) -> Void = { _ in }) async throws {
        for start in stride(from: 0, to: payload.count, by: Self.pageSize) {
            let page = Array(payload[start..<min(start + Self.pageSize, payload.count)])
            try await adapter.write(address: Self.address, payload: [UInt8(start)] + page)
            try await Task.sleep(for: Self.writeCycle)
            progress(Double(min(start + Self.pageSize, payload.count)) / Double(payload.count))
        }
    }

    /// Read bytes back from address zero.
    ///
    /// The address pointer is set by writing the address on its own, which the M24C02
    /// treats as a dummy write and leaves its internal counter there.
    ///
    /// - Parameter count: How many bytes to read.
    /// - Returns: The bytes as they sit in the chip, without any bit mirroring.
    func read(count: Int) async throws -> [UInt8] {
        try await adapter.write(address: Self.address, payload: [0x00])

        var collected: [UInt8] = []
        while collected.count < count {
            let chunk = min(MCP2221.maximumPayload, count - collected.count)
            collected += try await adapter.read(address: Self.address, count: chunk)
        }
        return Array(collected.prefix(count))
    }

    /// Write the payload and read it back, failing when the two disagree.
    ///
    /// - Parameters:
    ///   - payload: The bytes to store.
    ///   - progress: Called as the write proceeds.
    /// - Throws: ``MCP2221Error/verificationFailed(expected:read:)`` when the read-back
    ///   differs, carrying both sides so the window can show them.
    func writeAndVerify(
        _ payload: [UInt8],
        progress: @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try await write(payload, progress: progress)
        let readBack = try await read(count: payload.count)
        guard readBack == payload else {
            throw MCP2221Error.verificationFailed(expected: payload, read: readBack)
        }
    }
}

// MARK: - Identification

extension EEPROM {

    /// Work out what is on the bus, writing nothing.
    ///
    /// Two measurements, because a 24-series part carries no identification register. The
    /// address scan gives the size, since a part larger than 2 kbit takes several addresses.
    /// The wrap-around read then separates a 2 kbit part from a larger one that happens to
    /// take a single address and wants two address bytes, which the audio chip cannot read.
    ///
    /// - Returns: What both measurements found, including the case where they found nothing.
    func identify() async throws -> EEPROMIdentity {
        var answering: [UInt8] = []
        for candidate in Self.addressRange where await acknowledges(candidate) {
            answering.append(candidate)
        }

        guard answering.contains(Self.address) else {
            return EEPROMIdentity(answeringAddresses: answering, addressing: .undetermined)
        }
        return EEPROMIdentity(
            answeringAddresses: answering,
            addressing: try await measureAddressing()
        )
    }
}

// MARK: - Private

private extension EEPROM {

    /// How many bytes past the wrap point are compared against the start.
    ///
    /// One report's worth, which is enough to be sure and costs one exchange.
    static var comparisonLength: Int { MCP2221.maximumPayload }

    /// Whether anything answers at an address, leaving the bus usable either way.
    ///
    /// A part that does not answer leaves the engine holding a failed transfer, so the bus
    /// is set up again before the next address is tried.
    func acknowledges(_ candidate: UInt8) async -> Bool {
        do {
            _ = try await adapter.read(address: candidate, count: 1)
            return true
        } catch {
            try? await adapter.prepareBus()
            return false
        }
    }

    /// Read past the wrap point and see whether the counter came back to the start.
    ///
    /// The address pointer is set once and the counter runs on by itself, so reading
    /// `256 + n` bytes shows what the part does at its own boundary.
    func measureAddressing() async throws -> EEPROMIdentity.Addressing {
        let bytes = try await read(count: Self.capacity + Self.comparisonLength)
        guard bytes.count == Self.capacity + Self.comparisonLength else {
            return .undetermined
        }

        let start = Array(bytes[0..<Self.comparisonLength])
        let afterWrap = Array(bytes[Self.capacity...])

        guard Set(start).count > 1 else { return .undetermined }
        return start == afterWrap ? .singleByte : .notSingleByte
    }
}
