import Foundation

extension Bundle {

    /// The name the app carries for itself.
    ///
    /// The window shows its own name, and a name written into the view would be a second
    /// place to change it. `CFBundleDisplayName` is what a person sees in Finder and may
    /// rename, so it wins where it is set, and `CFBundleName` is what every build produces.
    var appName: String {
        if let displayName = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           displayName.isEmpty == false {
            return displayName
        }
        if let name = object(forInfoDictionaryKey: "CFBundleName") as? String,
           name.isEmpty == false {
            return name
        }
        return ProcessInfo.processInfo.processName
    }
}
