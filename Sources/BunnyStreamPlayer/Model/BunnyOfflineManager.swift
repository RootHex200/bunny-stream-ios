import Foundation
import Combine

/// Public API for managing offline video downloads and playback
public class BunnyOfflineManager {
  
  /// Shared instance
  public static let shared = BunnyOfflineManager()
  
  private let cacheManager = VideoCacheManager.shared
  
  private init() {}
  
  // MARK: - Download Management
  
  /// Download a video for offline playback
  ///
  /// - Parameters:
  ///   - cacheKey: Unique identifier for this cached video (provided by frontend)
  ///   - videoId: Bunny Stream video ID
  ///   - libraryId: Library ID
  ///   - token: Embed view token, when the library has token authentication
  ///     enabled. Must be paired with `expires`; the token is
  ///     `SHA256(securityKey + videoId + expires)`, so Bunny cannot verify one
  ///     without the other.
  ///   - expires: UNIX time **in seconds** the token was signed for.
  ///   - referer: Referer sent with the play-config call, the playlist and
  ///     every segment. Defaults to the embed referer Bunny itself uses; pass
  ///     the library's allowed referrer when "Block direct URL access" is
  ///     enabled with a custom allow-list.
  ///   - completion: Callback with success status and, on failure, a
  ///     ``BunnyDownloadError`` saying which of those went wrong.
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.downloadVideo(
  ///   cacheKey: "my_video_1",
  ///   videoId: "abc123",
  ///   libraryId: 12345,
  ///   token: token,
  ///   expires: expires,
  ///   referer: "https://myapp.example.com"
  /// ) { success, error in
  ///   if !success { print(error?.localizedDescription ?? "") }
  /// }
  /// ```
  public func downloadVideo(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    token: String? = nil,
    expires: Int? = nil,
    referer: String? = nil,
    title: String? = nil,
    wifiOnly: Bool = true,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    // Selects which background session this download starts on. In-flight
    // downloads stay on the session that owns them.
    cacheManager.setWifiOnly(wifiOnly)

    // A video the player just resolved needs no second `/play` call: the
    // response it already holds carries an authorized playlist URL. Taking it
    // skips the re-signing step entirely, which is the whole reason a playing
    // video could still fail to download.
    let cached = BunnyPlayConfigCache.shared.get(libraryId: libraryId, videoId: videoId)
    if let cached = cached, !cached.config.videoPlaylistUrl.isEmpty {
      print("[BunnyOfflineManager] Reusing the play config the player resolved for \(videoId)")
      let (success, error) = startDownload(
        cacheKey: cacheKey,
        videoId: videoId,
        libraryId: libraryId,
        config: cached.config,
        title: title,
        referer: referer ?? cached.referer
      )
      deliver(success, error, to: completion)
      return
    }

    // Nothing reusable, so this one has to be signed after all. A config
    // cached without a playlist URL still remembers the pair that resolved it,
    // which beats treating the video as unauthenticated.
    let auth = Self.normalizeTokenAuth(
      videoId: videoId,
      token: token ?? cached?.token,
      expires: expires ?? cached?.expires
    )

    let authToken: String?
    let authExpires: Int?
    switch auth {
    case .invalid(let reason):
      print("[BunnyOfflineManager] Refusing download of \(videoId): \(reason)")
      deliver(false, BunnyDownloadError.unauthorized(reason: reason), to: completion)
      return
    case .none:
      authToken = nil
      authExpires = nil
    case .signed(let signedToken, let signedExpires):
      authToken = signedToken
      authExpires = signedExpires
    }

    Task {
      do {
        // Load video configuration to get playlist URL
        let videoConfigLoader = VideoPlayerConfigLoader()
        let config = try await videoConfigLoader.load(
          libraryId: libraryId,
          videoId: videoId,
          token: authToken,
          expires: authExpires,
          referer: referer
        )

        let (success, error) = self.startDownload(
          cacheKey: cacheKey,
          videoId: videoId,
          libraryId: libraryId,
          config: config,
          title: title,
          referer: referer
        )
        await MainActor.run { completion(success, error) }
      } catch {
        let downloadError = Self.classifyResolveFailure(
          error,
          videoId: videoId,
          libraryId: libraryId,
          token: authToken,
          expires: authExpires
        )
        await MainActor.run { completion(false, downloadError) }
      }
    }
  }

  /// Hands a resolved play config to the cache manager.
  ///
  /// - Returns: Whether the download was accepted, and why it was not.
  private func startDownload(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    config: VideoConfigResponse,
    title: String?,
    referer: String?
  ) -> (Bool, Error?) {
    // Bunny can mark a video DRM-protected. Offline FairPlay needs persistent
    // content keys, which this path deliberately does not implement, so refuse
    // rather than spend the bytes on something that cannot be played back.
    // Matches the Android SDK, which refuses the same case.
    if config.enableDRM {
      print("[BunnyOfflineManager] Refusing download of DRM-protected video \(videoId)")
      return (false, BunnyDownloadError.unauthorized(
        reason: "This video is DRM-protected. Offline download of FairPlay content is not supported."
      ))
    }

    guard !config.videoPlaylistUrl.isEmpty else {
      return (false, BunnyDownloadError.notFound)
    }

    let metadata = OfflineVideo.VideoMetadata(
      title: title,
      thumbnailUrl: config.thumbnailUrl,
      duration: config.video.length,
      width: CGFloat(config.video.width),
      height: CGFloat(config.video.height)
    )

    let started = cacheManager.downloadVideo(
      cacheKey: cacheKey,
      videoId: videoId,
      libraryId: libraryId,
      playlistUrl: config.videoPlaylistUrl,
      metadata: metadata,
      referer: referer
    )

    if started { return (true, nil) }

    // The cache manager also declines when the video is already here or
    // already running. Reporting those as failures made a second tap look
    // broken, so they read as the no-ops they are.
    if cacheManager.isCached(cacheKey: cacheKey) {
      return (true, nil)
    }
    if let progress = cacheManager.getDownloadProgress(cacheKey: cacheKey),
       progress.status == .downloading || progress.status == .paused {
      return (true, nil)
    }
    return (false, BunnyDownloadError.unknown(underlying: nil))
  }

  /// Always on the main queue, and never before `downloadVideo` has returned —
  /// a completion that fires synchronously is a trap for callers that set
  /// state around the call.
  private func deliver(
    _ success: Bool,
    _ error: Error?,
    to completion: @escaping (Bool, Error?) -> Void
  ) {
    DispatchQueue.main.async { completion(success, error) }
  }

  /// Outcome of checking a caller-supplied `token`/`expires` pair.
  private enum TokenAuth {
    /// No token auth requested; the library had better not require it.
    case none
    case signed(token: String, expires: Int)
    case invalid(reason: String)
  }

  /// Anything past this is a millisecond timestamp: as seconds it lands in the
  /// year 5138, which nobody is signing a lesson for.
  private static let millisThreshold = 100_000_000_000

  /// Checks the token pair before spending a round trip on it.
  ///
  /// Bunny answers 401 for every malformed variant — no `expires`, a
  /// millisecond `expires`, an elapsed `expires` — so without this the caller
  /// gets one indistinguishable failure for four different mistakes.
  private static func normalizeTokenAuth(
    videoId: String,
    token: String?,
    expires: Int?,
    now: Int = Int(Date().timeIntervalSince1970)
  ) -> TokenAuth {
    // A blank token is not a token. Sent as `?token=`, it reads to Bunny as a
    // failed signature check rather than an unauthenticated request.
    let cleanToken = token?.trimmed.nonEmpty
    let rawExpires = expires.flatMap { $0 > 0 ? $0 : nil }

    guard let cleanToken = cleanToken else {
      guard let rawExpires = rawExpires else { return .none }
      return .invalid(reason: """
        expires=\(rawExpires) was supplied without a token; Bunny validates the \
        pair together and refuses half of it.
        """)
    }

    guard let rawExpires = rawExpires else {
      return .invalid(reason: """
        A token was supplied without expires. The token is \
        SHA256(securityKey + videoId + expires), so Bunny cannot check it without \
        the same expires it was signed with.
        """)
    }

    // A caller that passed a millisecond timestamp straight through is making
    // a fixable mistake, not an unrecoverable one.
    var expiresSeconds = rawExpires
    if rawExpires >= millisThreshold {
      expiresSeconds = rawExpires / 1000
      print("""
        [BunnyOfflineManager] expires=\(rawExpires) for \(videoId) looks like \
        milliseconds; Bunny wants seconds. Using \(expiresSeconds).
        """)
    }

    guard expiresSeconds > now else {
      return .invalid(reason: """
        The token expired at \(expiresSeconds) (now \(now)). Downloads are started \
        long after playback began, so a token minted for playback has often lapsed \
        by the time the download runs — sign a fresh one.
        """)
    }

    return .signed(token: cleanToken, expires: expiresSeconds)
  }

  /// Turns a play-config failure into something the app can show, and logs the
  /// diagnosis for the case that actually happens.
  private static func classifyResolveFailure(
    _ error: Error,
    videoId: String,
    libraryId: Int,
    token: String?,
    expires: Int?
  ) -> BunnyDownloadError {
    let downloadError: BunnyDownloadError
    switch error as? VideoPlayerError {
    case .unauthorized:
      downloadError = .unauthorized(reason: BunnyDownloadError.unauthorizedHint)
    case .notFound:
      downloadError = .notFound
    default:
      downloadError = BunnyDownloadError.classify(error)
    }

    if case .unauthorized = downloadError {
      let tokenHint = token.map { String($0.prefix(8)) + "…" } ?? "<none>"
      print("""
        [BunnyOfflineManager] Play config for \(videoId) in library \(libraryId) was \
        refused. token=\(tokenHint) expires=\(expires.map(String.init) ?? "<none>"). \
        A token that plays but will not download is almost always signed for a \
        different videoId/expires than the one sent here, or signed with a different \
        library's security key.
        """)
    } else {
      print("[BunnyOfflineManager] Failed to resolve play config for \(videoId): \(error)")
    }

    return downloadError
  }
  
  /// Check if a video is downloaded and available for offline playback
  ///
  /// - Parameter cacheKey: Cache key to check
  /// - Returns: True if video is cached and ready for offline playback
  ///
  /// Example:
  /// ```swift
  /// if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: "my_video_1") {
  ///   // Play from cache
  /// }
  /// ```
  public func isVideoDownloaded(cacheKey: String) -> Bool {
    return cacheManager.isCached(cacheKey: cacheKey)
  }
  
  /// Get download progress for a video
  ///
  /// - Parameter cacheKey: Cache key
  /// - Returns: Download progress information if download is active
  ///
  /// Example:
  /// ```swift
  /// if let progress = BunnyOfflineManager.shared.getDownloadProgress(cacheKey: "my_video_1") {
  ///   print("Progress: \(progress.progress * 100)%")
  /// }
  /// ```
  public func getDownloadProgress(cacheKey: String) -> DownloadProgress? {
    return cacheManager.getDownloadProgress(cacheKey: cacheKey)
  }
  
  /// Subscribe to download progress updates
  ///
  /// - Returns: Publisher that emits download progress updates
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.downloadProgressPublisher
  ///   .sink { progress in
  ///     print("Video: \(progress.cacheKey), Progress: \(progress.progress * 100)%")
  ///   }
  ///   .store(in: &cancellables)
  /// ```
  public var downloadProgressPublisher: PassthroughSubject<DownloadProgress, Never> {
    return cacheManager.progressPublisher
  }
  
  /// Pause an active download
  ///
  /// - Parameter cacheKey: Cache key
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.pauseDownload(cacheKey: "my_video_1")
  /// ```
  public func pauseDownload(cacheKey: String) {
    cacheManager.pauseDownload(cacheKey: cacheKey)
  }
  
  /// Resume a paused download
  ///
  /// - Parameter cacheKey: Cache key
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.resumeDownload(cacheKey: "my_video_1")
  /// ```
  public func resumeDownload(cacheKey: String) {
    cacheManager.resumeDownload(cacheKey: cacheKey)
  }
  
  /// Cancel an active download
  ///
  /// - Parameter cacheKey: Cache key
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.cancelDownload(cacheKey: "my_video_1")
  /// ```
  public func cancelDownload(cacheKey: String) {
    cacheManager.cancelDownload(cacheKey: cacheKey)
  }
  
  /// Delete a downloaded video
  ///
  /// - Parameter cacheKey: Cache key to delete
  /// - Returns: True if deletion was successful
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.deleteVideo(cacheKey: "my_video_1")
  /// ```
  @discardableResult
  public func deleteVideo(cacheKey: String) -> Bool {
    return cacheManager.deleteCachedVideo(cacheKey: cacheKey)
  }
  
  // MARK: - Cache Management
  
  /// Get all downloaded videos
  ///
  /// - Returns: Array of all cached videos with their metadata
  ///
  /// Example:
  /// ```swift
  /// let downloads = BunnyOfflineManager.shared.getAllDownloadedVideos()
  /// for video in downloads {
  ///   print("Video: \(video.cacheKey), Size: \(video.fileSize)")
  /// }
  /// ```
  public func getAllDownloadedVideos() -> [OfflineVideo] {
    return cacheManager.getAllCachedVideos()
  }
  
  /// Get information about a specific downloaded video
  ///
  /// - Parameter cacheKey: Cache key
  /// - Returns: Offline video information if available
  ///
  /// Example:
  /// ```swift
  /// if let video = BunnyOfflineManager.shared.getVideoInfo(cacheKey: "my_video_1") {
  ///   print("Duration: \(video.metadata.duration)")
  /// }
  /// ```
  public func getVideoInfo(cacheKey: String) -> OfflineVideo? {
    return cacheManager.getOfflineVideo(cacheKey: cacheKey)
  }
  
  /// Get total size of all downloaded videos in bytes
  ///
  /// - Returns: Total cache size in bytes
  ///
  /// Example:
  /// ```swift
  /// let totalSize = BunnyOfflineManager.shared.getTotalCacheSize()
  /// let sizeInMB = Double(totalSize) / (1024 * 1024)
  /// print("Total cache: \(sizeInMB) MB")
  /// ```
  public func getTotalCacheSize() -> Int64 {
    return cacheManager.getTotalCacheSize()
  }
  
  /// Clear all downloaded videos
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.clearAllDownloads()
  /// ```
  public func clearAllDownloads() {
    cacheManager.clearAllCache()
    // Holding a signed playlist URL past a wipe would let the next session
    // start a download against the previous one's authorization.
    BunnyPlayConfigCache.shared.clear()
  }

  /// Forgets the play configurations resolved during this session.
  ///
  /// Call on logout. The cached entries carry an authorized playlist URL and
  /// the token pair it was resolved with, neither of which should outlive the
  /// session that produced them.
  public func clearPlayConfigCache() {
    BunnyPlayConfigCache.shared.clear()
  }

  /// Selects which background session new downloads start on.
  ///
  /// A background session's cellular flag is fixed at creation, so the
  /// preference selects between two sessions rather than mutating one.
  public func setWifiOnly(_ enabled: Bool) {
    cacheManager.setWifiOnly(enabled)
  }
}

