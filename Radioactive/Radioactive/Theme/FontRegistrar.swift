import CoreText
import Foundation

/// Registers bundled fonts at launch so `Font.custom("VT323", …)` resolves.
/// Runtime registration avoids any Info.plist `UIAppFonts` plumbing and lets
/// us detect availability for a clean fallback.
enum FontRegistrar {
    private(set) static var vt323Available = false

    static func registerAll() {
        register("VT323-Regular", as: "VT323") { vt323Available = $0 }
    }

    private static func register(_ resource: String, as family: String, _ done: (Bool) -> Void) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else {
            done(false); return
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // If the family is already present (e.g. hot reload) treat as success.
        done(ok || error == nil)
    }
}
