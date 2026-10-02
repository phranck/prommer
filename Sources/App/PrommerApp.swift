import SwiftUI

/// Writes the USB identity of a NeXT Sound Box mini into the EEPROM on its board.
///
/// The board is reached through an Adafruit MCP2221A breakout on J1, which also supplies
/// the 3.3 V the EEPROM needs. The Sound Box itself stays unplugged from USB throughout.
@main
struct PrommerApp: App {

    // MARK: Properties

    @State private var model = ProgrammerModel()

    // MARK: Initialisers

    init() {
        BundledFont.register()
    }

    // MARK: Body

    var body: some Scene {
        WindowGroup {
            ProgrammerView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
