import Foundation

extension MediaPlayer {
  /// Creates a `MediaPlayer` instance configured with the specified video and FairPlay details.
  ///
  /// This factory method attempts to create a URL using the given `videoId` and `cdn`. If successful, it initializes
  /// a `FairPlayStreamHandler` with the `videoId` and `libraryId`, sets up the `MediaPlayer`, and associates the `FairPlayStreamHandler`
  /// with the `MediaPlayer`. If any step of the process fails, it returns `nil`.
  ///
  /// - Parameters:
  ///   - video: A `Video` for the video to be played.
  ///
  /// - Returns: A `MediaPlayer` instance.
  ///
  /// Example Usage:
  /// ```
  /// let player = MediaPlayer.make(video: video)
  /// ```
  static func make(video: Video) -> MediaPlayer {
    print("[MediaPlayer] Creating player for video GUID: \(video.guid)")
    print("[MediaPlayer] Playlist URL: \(video.playlistUrl ?? "nil")")
    
    guard let playlistUrlString = video.playlistUrl, !playlistUrlString.isEmpty else {
      print("[MediaPlayer] ERROR: Playlist URL is nil or empty!")
      // Create a dummy URL to prevent crash, but this will fail to play
      let url = URL(string: "https://invalid.url")!
      let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId)
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
      let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId)
      let subtitlesProvider = MediaPlayerSubtitlesProvider(video: video)
      return MediaPlayer(
        url: url,
        fairPlayHandler: fairPlayHandler,
        subtitlesProvider: subtitlesProvider
      )
    }
    
    print("[MediaPlayer] Valid URL created: \(url.absoluteString)")
    let fairPlayHandler = FairPlayStreamHandler(videoId: video.guid, libraryId: video.libraryId)
    let subtitlesProvider = MediaPlayerSubtitlesProvider(video: video)
    let mediaPlayer = MediaPlayer(
      url: url,
      fairPlayHandler: fairPlayHandler,
      subtitlesProvider: subtitlesProvider
    )
    
    Task { try? await subtitlesProvider.loadSubtitles() }
    
    return mediaPlayer
  }
}
