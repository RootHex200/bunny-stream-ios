import Foundation

/// Remembers the play configuration the player just resolved, so a download of
/// the same video does not have to ask Bunny for it a second time.
///
/// The second ask is where token-authenticated libraries break. `/play`
/// returns an already-authorized `videoPlaylistUrl`, so a successful playback
/// has *already* produced everything a download needs. Re-resolving it means
/// re-signing it, and a token minted for playback has usually lapsed — or was
/// never threaded through to the download call at all — by the time the user
/// taps download. The result is a 401 on a video that is visibly playing.
///
/// In memory only. This is a short-lived hand-off between two calls seconds
/// apart, not a persistence layer; `VideoCacheManager`'s metadata store owns
/// the durable copy once the download starts. Mirrors the Android SDK's
/// `BunnyPlayConfigCache`.
final class BunnyPlayConfigCache {

  static let shared = BunnyPlayConfigCache()

  /// How long a resolved config is worth reusing.
  ///
  /// The playlist URL `/play` hands back is itself time-limited by the CDN, so
  /// an old entry buys a 401 at resolve time in exchange for a 403 midway
  /// through the download — a worse trade. Past this, re-resolve.
  private static let maxAge: TimeInterval = 5 * 60

  /// Bounded so a long browsing session cannot grow this without limit.
  private static let maxEntries = 16

  struct Entry {
    let config: VideoConfigResponse
    /// The pair this config was resolved under, for callers that must re-resolve.
    let token: String?
    let expires: Int?
    let referer: String?
    let resolvedAt: Date
  }

  private let lock = NSLock()
  private var entries: [String: Entry] = [:]
  /// Insertion order, oldest first, so eviction drops the least recent.
  private var order: [String] = []

  private init() {}

  func put(
    libraryId: Int,
    videoId: String,
    config: VideoConfigResponse,
    token: String?,
    expires: Int?,
    referer: String?,
    now: Date = Date()
  ) {
    let key = Self.key(libraryId: libraryId, videoId: videoId)

    lock.lock()
    defer { lock.unlock() }

    // A blank token is not a token. Sent as `?token=`, it reads to Bunny as a
    // failed signature check rather than an unauthenticated request.
    entries[key] = Entry(
      config: config,
      token: token?.trimmed.nonEmpty,
      expires: expires.flatMap { $0 > 0 ? $0 : nil },
      referer: referer?.trimmed.nonEmpty,
      resolvedAt: now
    )

    order.removeAll { $0 == key }
    order.append(key)

    while order.count > Self.maxEntries {
      entries.removeValue(forKey: order.removeFirst())
    }
  }

  /// The cached config, or `nil` when absent or too old to trust.
  func get(libraryId: Int, videoId: String, now: Date = Date()) -> Entry? {
    let key = Self.key(libraryId: libraryId, videoId: videoId)

    lock.lock()
    defer { lock.unlock() }

    guard let entry = entries[key] else { return nil }

    if now.timeIntervalSince(entry.resolvedAt) > Self.maxAge {
      entries.removeValue(forKey: key)
      order.removeAll { $0 == key }
      return nil
    }
    return entry
  }

  /// Dropped on logout, where holding a signed playlist URL would outlive the
  /// session it was authorized for.
  func clear() {
    lock.lock()
    defer { lock.unlock() }
    entries.removeAll()
    order.removeAll()
  }

  private static func key(libraryId: Int, videoId: String) -> String {
    "\(libraryId)/\(videoId)"
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nonEmpty: String? { isEmpty ? nil : self }
}
