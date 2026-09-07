import AVFoundation
import Foundation

/// Why a download could not be started, or why one failed.
///
/// The cases mirror the Android SDK's `BunnyDownloadError` one for one, so a
/// cross-platform bridge can map ``code`` without forking per platform.
/// `localizedDescription` carries the detail that makes the failure
/// actionable — "your token expired" and "your storage is full" call for very
/// different responses from the app, and a single opaque error collapses them.
public enum BunnyDownloadError: LocalizedError {
  /// The CDN or the API refused the request. Carries the reason, which is
  /// usually a token/`expires` problem or a `Referer` the library does not
  /// allow.
  case unauthorized(reason: String)

  /// The video, or its play configuration, does not exist.
  case notFound

  /// The transfer could not reach Bunny.
  case network(underlying: Error?)

  /// The device ran out of room for the download.
  case storageFull

  case unknown(underlying: Error?)

  /// Coarse code, spelled exactly as the Android SDK spells it.
  public var code: String {
    switch self {
    case .unauthorized: return "UNAUTHORIZED"
    case .notFound: return "NOT_FOUND"
    case .network: return "NETWORK"
    case .storageFull: return "STORAGE_FULL"
    case .unknown: return "UNKNOWN"
    }
  }

  public var errorDescription: String? {
    switch self {
    case .unauthorized(let reason):
      return reason
    case .notFound:
      return "The video could not be found, or its play configuration is unavailable."
    case .network(let underlying):
      return underlying.map { "Network error: \($0.localizedDescription)" }
        ?? "The download could not reach Bunny. Check the connection."
    case .storageFull:
      return "There is not enough free space on the device to finish this download."
    case .unknown(let underlying):
      return underlying.map { "Download failed: \($0.localizedDescription)" }
        ?? "The download failed for an unknown reason."
    }
  }

  /// Maps a transfer failure onto something the app can act on.
  ///
  /// `AVAssetDownloadURLSession` reports an HTTP refusal as an
  /// `AVFoundationErrorDomain` media error rather than a status code, so the
  /// underlying `NSError` has to be unwrapped before a 403 is recognisable as
  /// one. Without this, a library with "Block direct URL access" enabled fails
  /// downloads with a message about a corrupt media file, which sends whoever
  /// reads it looking in entirely the wrong place.
  static func classify(_ error: Error) -> BunnyDownloadError {
    let nsError = error as NSError
    var chain: [NSError] = [nsError]
    var cursor = nsError
    while let underlying = cursor.userInfo[NSUnderlyingErrorKey] as? NSError {
      chain.append(underlying)
      cursor = underlying
    }

    for link in chain {
      switch link.domain {
      case NSURLErrorDomain:
        switch link.code {
        case NSURLErrorUserAuthenticationRequired, NSURLErrorNoPermissionsToReadFile:
          return .unauthorized(reason: unauthorizedHint)
        case NSURLErrorFileDoesNotExist, NSURLErrorBadURL, NSURLErrorUnsupportedURL:
          return .notFound
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff:
          return .network(underlying: error)
        default:
          break
        }
      case NSPOSIXErrorDomain where link.code == Int(ENOSPC):
        return .storageFull
      case NSCocoaErrorDomain where link.code == NSFileWriteOutOfSpaceError:
        return .storageFull
      case AVFoundationErrorDomain:
        // -12660 is the media services' rendition of HTTP 403, and the two
        // neighbours are the 401/404 equivalents. AVFoundation exposes no
        // symbol for them.
        switch link.code {
        case -12660, -12661:
          return .unauthorized(reason: unauthorizedHint)
        case -12666, -12034:
          return .notFound
        default:
          break
        }
      default:
        break
      }
    }

    let message = chain.map { $0.localizedDescription.lowercased() }.joined(separator: " ")
    if message.contains("no space") || message.contains("disk full") {
      return .storageFull
    }
    if message.contains("403") || message.contains("401") || message.contains("unauthor") {
      return .unauthorized(reason: unauthorizedHint)
    }
    if message.contains("404") || message.contains("not found") {
      return .notFound
    }
    return .unknown(underlying: error)
  }

  /// What a 401/403 on a download almost always means, spelled out.
  static let unauthorizedHint = """
    Bunny refused the download. With "Block direct URL access" enabled the CDN \
    only answers requests whose Referer is on the library's allow-list, and with \
    Embed View Token Authentication enabled it also needs a token/expires pair \
    signed for this exact video. Pass the same referer you play with, and a token \
    that has not expired.
    """
}
