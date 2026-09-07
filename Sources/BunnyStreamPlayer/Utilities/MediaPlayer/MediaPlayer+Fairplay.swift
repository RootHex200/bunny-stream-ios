import Foundation
import AVFoundation

extension MediaPlayer {
  /// Creates a `MediaPlayer` instance configured with the specified video and FairPlay details.
  ///
  /// This factory method attempts to create a URL using the given `videoId` and `cdn`. If successful, it initializes
  /// a `FairPlayStreamHandler` with the `videoId` and `libraryId`, sets up the `MediaPlayer`, and associates the `FairPlayStreamHandler`
  /// with the `MediaPlayer`. If any step of the process fails, it returns `nil`.
  ///
  /// - Parameters:
  ///   - video: A `Video` for the video to be played.
  ///   - cacheKey: Optional cache key for storing/retrieving offline video
  ///   - referer: Optional Referer for the playlist, segments and licence.
  ///     Defaults to the embed referer Bunny itself uses.
  ///
  /// - Returns: A `MediaPlayer` instance.
  ///
  /// Example Usage:
  /// ```
  /// let player = MediaPlayer.make(video: video)
  /// let offlinePlayer = MediaPlayer.make(video: video, cacheKey: "my_video")
  /// ```
  static func make(video: Video, cacheKey: String? = nil, referer: String? = nil) -> MediaPlayer {
    print("[MediaPlayer] Creating player for video GUID: \(video.guid)")
    print("[MediaPlayer] Playlist URL: \(video.playlistUrl ?? "nil")")
    
    // Check if we have a cache key and the video is cached
    if let cacheKey = cacheKey, let cachedURL = VideoCacheManager.shared.getCachedVideoURL(cacheKey: cacheKey) {
      print("[MediaPlayer] Loading from cache with key: \(cacheKey)")
      return makeOffline(url: cachedURL)
    }
    
    guard let playlistUrlString = video.playlistUrl, !playlistUrlString.isEmpty else {
      print("[MediaPlayer] ERROR: Playlist URL is nil or empty!")
      // Create a dummy URL to prevent crash, but this will fail to play
      let url = URL(string: "https://invalid.url")!
      let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId, referer: referer)
      let subtitlesProvider = MediaPlayerSubtitlesProvider(video: video)
      return MediaPlayer(
        url: url,
        fairPlayHandler: fairPlayHandler,
        subtitlesProvider: subtitlesProvider
      )
    }
    
    guard let url = URL(string: playlistUrlString) else {
      print("[MediaPlayer] ERROR: Invalid playlist URL format: \(playlistUrlString)")
      // Create a dummy URL to prevent crash, but this will fail to play
      let url = URL(string: "https://invalid.url")!
      let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId, referer: referer)
      let subtitlesProvider = MediaPlayerSubtitlesProvider(video: video)
      return MediaPlayer(
        url: url,
        fairPlayHandler: fairPlayHandler,
        subtitlesProvider: subtitlesProvider
      )
    }
    
    print("[MediaPlayer] Valid URL created: \(url.absoluteString)")
    let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId, referer: referer)
    let subtitlesProvider = MediaPlayerSubtitlesProvider(video: video)
    let mediaPlayer = MediaPlayer(
      url: url,
      fairPlayHandler: fairPlayHandler,
      subtitlesProvider: subtitlesProvider
    )
    
    Task { try? await subtitlesProvider.loadSubtitles() }
    
    return mediaPlayer
  }
  
  /// Creates a `MediaPlayer` instance for offline playback from a local URL
  ///
  /// This factory method creates a media player that can play locally cached HLS videos.
  /// It uses the local file URL directly without FairPlay DRM handling.
  ///
  /// - Parameters:
  ///   - url: Local file URL of the cached video
  ///
  /// - Returns: A `MediaPlayer` instance configured for offline playback
  ///
  /// Example Usage:
  /// ```
  /// let localURL = URL(fileURLWithPath: "/path/to/cached/video.m3u8")
  /// let player = MediaPlayer.makeOffline(url: localURL)
  /// ```
  static func makeOffline(url: URL) -> MediaPlayer {
    print("[MediaPlayer] Creating offline player for URL: \(url.path)")
    
    // For offline playback, we can use the URL directly
    // AVPlayer handles local HLS playlists
    let asset = AVURLAsset(url: url)
    let playerItem = AVPlayerItem(asset: asset)
    let mediaPlayer = MediaPlayer(playerItem: playerItem)
    
    print("[MediaPlayer] Offline player created successfully")
    return mediaPlayer
  }
}
