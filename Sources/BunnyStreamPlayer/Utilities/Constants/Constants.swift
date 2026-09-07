import Foundation

enum Constants {
  static var videoCoreBaseUrlString: String = "https://video-core-api.bunnycdn.com"

  /// What the official Bunny embed sends, and what a library with "Block
  /// direct URL access" enabled expects to see.
  ///
  /// Every request the SDK makes for media — the `/play` config, the HLS
  /// playlist, each segment, the FairPlay licence, the thumbnails — carries
  /// this unless the caller supplies a referer of their own. A request that
  /// omits it is answered with 403 by a hardened library.
  static let defaultReferer: String = "https://iframe.mediadelivery.net/"
}
