import AppKit
import SwiftUI

extension Color {

    /// The colour a hex dump is set in, so bytes read as machine output rather than prose.
    ///
    /// It carries two values: a deep green on a light window, where phosphor green would
    /// vanish, and the bright one in the dark, where it belongs.
    static let terminalGreen = Color("TerminalGreen")

    /// The fill every card sits on, a shade darker than the window behind it in both
    /// appearances.
    ///
    /// Black at two strengths rather than one, because the two backgrounds start far apart.
    /// The light one is near white, so a few percent already reads as a step down. The dark
    /// one is close to `#1E1E1E`, where those same few percent would move it by one value out
    /// of 255. Black rather than a fixed colour so that the card darkens whatever the window
    /// material happens to be showing through from behind.
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(white: 0, alpha: isDark ? 0.35 : 0.035)
    })

    /// The four bars of the LAYERED mark, in the order they run from top to bottom.
    ///
    /// Taken from `logo.svg`, where they sit either side of the wordmark, which is what the
    /// window title does with them too.
    static let layeredStripes: [Color] = [
        Color(red: 198 / 255, green: 70 / 255, blue: 22 / 255),
        Color(red: 251 / 255, green: 172 / 255, blue: 62 / 255),
        Color(red: 117 / 255, green: 140 / 255, blue: 52 / 255),
        Color(red: 43 / 255, green: 116 / 255, blue: 136 / 255)
    ]
}
