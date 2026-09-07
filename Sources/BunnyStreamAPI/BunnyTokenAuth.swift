import CryptoKit
import Foundation

/// A `token`/`expires` pair for a library with Embed View Token
/// Authentication turned on.
public struct BunnyPlaybackToken: Equatable {
  public let token: String
  /// UNIX time in **seconds** — Bunny rejects milliseconds.
  public let expires: Int

  public init(token: String, expires: Int) {
    self.token = token
    self.expires = expires
  }
}

/// Signs playback requests for libraries with Embed View Token Authentication
/// enabled.
///
/// With that setting on, `/library/{libraryId}/videos/{videoId}/play` answers
/// 401 to any request that does not carry a matching `token` and `expires`; an
/// AccessKey does not substitute for it. The token is
/// `SHA256_HEX(tokenSecurityKey + videoId + expires)`.
///
/// **The security key belongs on your server, not in the app bundle.** Anyone
/// who unpacks the IPA can read a key compiled into it and mint tokens for the
/// whole library, which defeats the setting you just enabled. Ship a small
/// backend endpoint that returns a ``BunnyPlaybackToken`` and hand the result
/// to `BunnyStreamPlayer(token:expires:)` /
/// `BunnyOfflineManager.downloadVideo`. This helper exists so that server can
/// share one implementation with the demo app and with local testing — not so
/// the key can travel with the client. Ports the Android SDK's
/// `BunnyTokenAuth`.
public enum BunnyTokenAuth {

  /// The token Bunny expects for `videoId` up to `expires`.
  ///
  /// - Parameter expires: UNIX time in seconds, in the future.
  public static func token(securityKey: String, videoId: String, expires: Int) -> String {
    precondition(!securityKey.isEmpty, "securityKey is required")
    precondition(!videoId.isEmpty, "videoId is required")

    let digest = SHA256.hash(data: Data("\(securityKey)\(videoId)\(expires)".utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// A token valid for the next `ttlSeconds`.
  ///
  /// `now` is injectable so a test can pin the clock; callers should leave it
  /// alone.
  public static func sign(
    securityKey: String,
    videoId: String,
    ttlSeconds: Int = 3600,
    now: Int = Int(Date().timeIntervalSince1970)
  ) -> BunnyPlaybackToken {
    precondition(ttlSeconds > 0, "ttlSeconds must be positive")

    let expires = now + ttlSeconds
    return BunnyPlaybackToken(
      token: token(securityKey: securityKey, videoId: videoId, expires: expires),
      expires: expires
    )
  }
}
