import CoreText
import Foundation
import SwiftUI

/// The face the window title is set in, shipped inside the app.
///
/// It is registered at launch rather than declared in the Info.plist, because Xcode
/// generates that file and has no build setting for `ATSApplicationFontsPath`. A failed
/// registration leaves the title in the system face, which is why nothing here throws.
///
/// The file is [Monoton](https://fonts.google.com/specimen/Monoton) by Vernon Adams, under
/// the SIL Open Font License 1.1. `Monoton-OFL.txt` ships beside it, which is what that
/// licence asks for.
enum BundledFont {

    // MARK: Properties

    /// What `Font.custom` and `NSFont(name:)` ask for, taken from the file's name table.
    static let title = "Monoton-Regular"

    // MARK: Registration

    /// Hands the bundled face to Core Text for this process.
    ///
    /// The app calls this before its first window appears, because a face asked for by name
    /// before it is registered falls back to the system one and stays there.
    static func register() {
        guard let url = Bundle.main.url(forResource: title, withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
