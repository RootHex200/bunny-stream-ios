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
          print("[FontManager] Font registration failed for \(url.lastPathComponent): \(error)")
        }
      }
    }
    
    fontsRegistered = true
  }
}
