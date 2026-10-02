import Foundation
import Observation

/// Everything the window shows and everything it can start.
///
/// The model owns the descriptor the user is editing, the adapter's state and the record
/// of the last run. It talks to the hardware through ``MCP2221`` and ``EEPROM`` and keeps
/// the window free of any knowledge about reports or page sizes.
@MainActor
@Observable
final class ProgrammerModel {

    // MARK: Properties

    /// What the user is about to write.
    var descriptor = DescriptorBlock()

    /// The label stored past the descriptor, which the audio chip never reads.
    var serialNumber = SerialNumberBlock()

    /// Reports the adapter's presence on its own, so nothing has to be refreshed.
    let adapterWatcher = AdapterWatcher()

    /// What the programmer is doing at the moment.
    private(set) var activity: Activity = .idle

    /// The outcome of the last run, kept until the next one starts.
    private(set) var lastResult: Result?

    /// What the chip on the bus turned out to be, once it has been looked at.
    private(set) var identity: EEPROMIdentity?

    /// The chip as it was last read, which fills the part of the page nothing writes.
    private(set) var chipContents: [UInt8] = []

    /// The image as it would sit in the EEPROM, or the reason it cannot be built.
    var image: Swift.Result<EEPROMImage, DescriptorError> {
        do {
            return .success(try EEPROMImage(
                descriptor: descriptor,
                serialNumber: serialNumber,
                existing: chipContents
            ))
        } catch let error as DescriptorError {
            return .failure(error)
        } catch {
            return .failure(.wrongBlockLength(0))
        }
    }

    /// Whether the write button should do anything.
    var canWrite: Bool {
        if case .idle = activity, adapterAttached, case .success = image {
            return true
        }
        return false
    }

    /// Whether an adapter is plugged in at this moment.
    var adapterAttached: Bool { adapterWatcher.isAttached }

    // MARK: Initialisers

    init() {}
}

// MARK: - Types

extension ProgrammerModel {

    /// What the programmer is doing, which decides what the window offers.
    ///
    /// The step is a case rather than a sentence, so the wording stays in the window and
    /// the model needs no opinion about which language the person reads.
    enum Activity: Equatable {
        case idle
        case working(step: Step, fraction: Double)
    }

    /// The three stretches of a run that are worth naming whilst they happen.
    enum Step: Equatable {
        case openingAdapter
        case writing
        case reading
    }

    /// How a run ended.
    enum Result: Equatable {
        case written
        case read
        case failed(String)
    }
}

// MARK: - Actions

extension ProgrammerModel {

    /// Start watching for the adapter. The window calls this once.
    func startWatchingAdapter() {
        adapterWatcher.start()
    }

    /// Write the descriptor and the serial number to the board and read them back.
    func write() async {
        guard case let .success(image) = image else { return }

        activity = .working(step: .openingAdapter, fraction: 0)
        lastResult = nil
        do {
            let adapter = try MCP2221()
            try await adapter.prepareBus()
            let eeprom = EEPROM(adapter: adapter)

            activity = .working(step: .writing, fraction: 0)
            try await eeprom.writeAndVerify(image.payload) { [weak self] fraction in
                Task { @MainActor in
                    self?.activity = .working(step: .writing, fraction: fraction)
                }
            }
            lastResult = .written
            identity = try? await eeprom.identify()
            try? await load(from: eeprom)
        } catch {
            lastResult = .failed(error.localizedDescription)
        }
        activity = .idle
    }

    /// Read the whole chip without changing anything, and take what it holds into the
    /// window.
    ///
    /// Everything the board already carries replaces what was typed, so a board can be read,
    /// adjusted and written again without retyping it. An unprogrammed chip leaves the
    /// window as it was, because it has nothing to say.
    func readBack() async {
        activity = .working(step: .reading, fraction: 0)
        lastResult = nil
        do {
            let adapter = try MCP2221()
            try await adapter.prepareBus()
            let eeprom = EEPROM(adapter: adapter)

            try await load(from: eeprom)
            lastResult = .read
            identity = try? await eeprom.identify()
        } catch {
            lastResult = .failed(error.localizedDescription)
        }
        activity = .idle
    }

    /// Look at what is on the bus, quietly.
    ///
    /// Runs when the adapter arrives. It only reads, and a failure leaves the window with
    /// nothing to say about the chip rather than with a complaint, because at that moment
    /// the board may simply not be connected yet.
    func inspectChip() async {
        guard adapterAttached, activity == .idle else { return }
        guard let adapter = try? MCP2221() else { return }
        try? await adapter.prepareBus()

        let eeprom = EEPROM(adapter: adapter)
        identity = try? await eeprom.identify()
        try? await load(from: eeprom)
    }

    /// Forget what was read, because the chip it came from is no longer reachable.
    func forgetChip() {
        identity = nil
        chipContents = []
    }
}

// MARK: - Private

private extension ProgrammerModel {

    /// Read the whole page and take whatever it holds into the window.
    func load(from eeprom: EEPROM) async throws {
        let bytes = try await eeprom.read(count: EEPROM.capacity)
        chipContents = bytes

        let readable = EEPROMImage.readable(from: bytes)
        if let stored = DescriptorBlock.decoded(from: readable) {
            descriptor = stored
        }
        if let stored = SerialNumberBlock.decoded(from: readable) {
            serialNumber = stored
        }
    }
}
