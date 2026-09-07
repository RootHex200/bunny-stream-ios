import SwiftUI
import CoreText

class FontManager {
  private static var fontsRegistered = false
  
  static func registerFonts() {
    guard !fontsRegistered else { return }
    
    let bundle = Bundle.module
    let fontURLs = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
    
    for url in fontURLs {
      var errorRef: Unmanaged<CFError>?
      if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef) {
        if let error = errorRef?.takeUnretainedValue() {
          // A name clash is not a failure. `arial.ttf` carries the same
          // PostScript name as the Arial iOS already ships, so CoreText
          // declines the duplicate and the family stays perfectly usable —
          // the system copy answers for it. Logging that as an error sent
          // people hunting a font bug while the real problem was elsewhere in
          // the log.
          let code = CFErrorGetCode(error)
          if code == CFIndex(CTFontManagerError.duplicatedName.rawValue)
              || code == CFIndex(CTFontManagerError.alreadyRegistered.rawValue) {
            continue
          }
          print("[FontManager] Font registration failed for \(url.lastPathComponent): \(error)")
        }
      }
    }
    
    fontsRegistered = true
  }
}
