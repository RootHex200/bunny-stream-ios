import AVFoundation
import SwiftUI
import Kingfisher

// Global configuration for Kingfisher headers
private func configureGlobalKingfisherHeaders() {
  var headers = KingfisherManager.shared.downloader.sessionConfiguration.httpAdditionalHeaders ?? [:]
  headers["Referer"] = "https://iframe.mediadelivery.net/"
  KingfisherManager.shared.downloader.sessionConfiguration.httpAdditionalHeaders = headers
}

// Configure headers when module loads
private let _globalKingfisherConfig: Void = configureGlobalKingfisherHeaders()

/// A SwiftUI view that provides an integrated video player experience
/// using BunnyStream.
///
/// `BunnyStreamPlayer` handles video loading, configuration, and playback.
/// It supports customizable themes and icons, as well as automatic
/// error handling and retry mechanisms.
public struct BunnyStreamPlayer: View {

  /// The video configuration loader.
  let videoPlayerConfigLoader = VideoPlayerConfigLoader()
  /// The access key for authentication. Can be `nil` for public videos.
  var accessKey: String?
  /// The heatmap data loader. Will be `nil` if no `accessKey` is provided.
  var heatmapLoader: HeatmapLoader?
  /// The unique ID of the video to be played.
  let videoId: String
  /// The ID of the video library.
  let libraryId: Int
  /// The authentication token for accessing protected videos. Can be `nil` for public videos.
  var token: String?
  /// The expiration timestamp for the token. Can be `nil` for public videos.
  var expires: Int?
  /// The referer value for API calls. If `nil`, uses default "https://iframe.mediadelivery.net/".
  var referer: String?
  /// The cache key for offline playback. If provided, will attempt to play from cache.
  var cacheKey: String?

  /// The loading state of the video player.
  @State private var loadingState: VideoLoadingState = .loading
  @State private var isViewActive: Bool = false
  /// The media player instance.
  @State var player: MediaPlayer?
  /// The theme configuration for the video player.
  @State var theme: VideoPlayerTheme = .defaultTheme
  /// The video player configuration.
  @State var videoConfig = VideoPlayerConfig()
  /// The set of custom player icons.
  internal var playerIcons: PlayerIcons?
  /// Callback fired once the underlying AVPlayer is created and assigned.
  /// Hosts (e.g. plugin bridges) can use this to capture a reference for explicit
  /// lifecycle control (pause, replace item, etc.) without waiting for SwiftUI's
  /// onDisappear — which can fire late or not at all when this view is hosted
  /// inside a UIHostingController inside a Flutter platform view.
  public var onPlayerReady: ((AVPlayer) -> Void)?

  /// The different states of video loading.
  enum VideoLoadingState {
    /// Indicates that the video is currently loading.
    case loading
    /// Indicates that the video has loaded successfully with its metadata.
    case loaded(MediaPlayer, Video, Heatmap)
    /// Indicates that video loading has failed.
    case failed
    /// Indicates that loading has failed due to a specific error.
    case loaderFailed(VideoPlayerError)
  }

  /// Initializes a new instance of the `BunnyStreamPlayer`.
  ///
  /// This initializer sets up the video player with the necessary configurations
  /// such as access key, video ID, library ID. Optionally, custom player
  /// icons can be provided. If no accessKey is provided, only Public videos will be playable.
  ///
  /// - Parameters:
  ///   - accessKey: The access key for authentication. Can be `nil` for public videos.
  ///   - videoId: The unique ID of the video to be played.
  ///   - libraryId: The ID of the video library.
  ///   - token: The authentication token for accessing protected videos. Can be `nil` for public videos.
  ///   - expires: The expiration timestamp for the token. Can be `nil` for public videos.
  ///   - referer: The referer value for API calls. If `nil`, uses default "https://iframe.mediadelivery.net/".
  ///   - cacheKey: The cache key for offline playback. If provided and video is cached, will play from cache.
  ///   - playerIcons: Optional custom icons for the video player.
  ///
  /// ### Usage Examples:
  /// 
  /// **For public videos:**
  /// ```swift
  /// BunnyStreamPlayer(accessKey: nil,
  ///                  videoId: "your_video_id",
  ///                  libraryId: 123)
  /// ```
  /// 
  /// **For protected videos with token:**
  /// ```swift
  /// BunnyStreamPlayer(accessKey: "your_access_key",
  ///                  videoId: "your_video_id", 
  ///                  libraryId: 123,
  ///                  token: "your_token",
  ///                  expires: 1234567890)
  /// ```
  /// 
  /// **For videos with custom referer:**
  /// ```swift
  /// BunnyStreamPlayer(accessKey: "your_access_key",
  ///                  videoId: "your_video_id", 
  ///                  libraryId: 123,
  ///                  referer: "https://yourdomain.com")
  /// ```
  /// 
  /// **For offline playback with cache key:**
  /// ```swift
  /// BunnyStreamPlayer(accessKey: nil,
  ///                  videoId: "your_video_id", 
  ///                  libraryId: 123,
  ///                  cacheKey: "my_cached_video")
  /// ```
  public init(
    accessKey: String?,
    videoId: String,
    libraryId: Int,
    token: String? = nil,
    expires: Int? = nil,
    referer: String? = nil,
    cacheKey: String? = nil,
    playerIcons: PlayerIcons? = nil,
    onPlayerReady: ((AVPlayer) -> Void)? = nil
  ) {
    self.accessKey = accessKey
    self.videoId = videoId
    self.libraryId = libraryId
    self.token = token
    self.expires = expires
    self.referer = referer
    self.cacheKey = cacheKey
    self.onPlayerReady = onPlayerReady
    if let accessKey {
      self.heatmapLoader = HeatmapLoader(bunnyStreamAPI: .init(accessKey: accessKey, referer: referer))
    }
    if let playerIcons {
      self.playerIcons = playerIcons
      self.theme.images = playerIcons
    }
    FontManager.registerFonts()

    // Configure Kingfisher to use Referer header for CDN bypass
    configureKingfisherHeaders()
  }

  /// The main body of the `BunnyStreamPlayer`.
  public var body: some View {
    VStack(alignment: .center) {
      switch loadingState {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .loaded(let mediaPlayer, let video, let heatmap):
        BunnyStreamPlayerContainerView(player: mediaPlayer, video: video, heatmap: heatmap)
          .environment(\.videoPlayerTheme, theme)
          .environment(\.videoPlayerConfig, videoConfig)
          .onAppear {
            setupAudioSession()
            mediaPlayer.play()
          }
      case .failed:
        reloadButton()
      case .loaderFailed(let error):
        errorView(for: error)
      }
    }
    .onAppear {
      isViewActive = true
    }
    .task {
      await loadVideo()
    }
    .onDisappear {
      isViewActive = false
      teardownPlayer()
    }
  }

  /// Stops playback and releases the underlying AVPlayer item so audio buffers
  /// and decoders are freed immediately. Safe to call multiple times.
  private func teardownPlayer() {
    guard let p = player else { return }
    p.stop()
    p.replaceCurrentItem(with: nil)
    player = nil
  }

  /// Loads the video and its configuration asynchronously.
  @MainActor
  func loadVideo() async {
    if let cacheKey = cacheKey {
      if await loadFromCache(cacheKey: cacheKey) { return }
    }

    loadingState = .loading
    do {
      let videoConfigResponse = try await videoPlayerConfigLoader.load(libraryId: libraryId, videoId: videoId, token: token, expires: expires, referer: referer)

      guard isViewActive else { return }

      var video = Video(response: videoConfigResponse)
      let heatmap = try? await heatmapLoader?.loadHeatmap(videoId: videoId, libraryId: libraryId)
      VideoPlayerConfig(response: videoConfigResponse).map { self.videoConfig = $0 }

      let player = MediaPlayer.make(video: video, cacheKey: cacheKey)
      self.player = player
      onPlayerReady?(player)
      video.adjustLength(player.duration)

      self.theme = VideoPlayerTheme(config: videoConfigResponse) ?? theme
      if let playerIcons { self.theme.images = playerIcons }

      guard isViewActive else {
        teardownPlayer()
        return
      }

      loadingState = .loaded(player, video, heatmap ?? Heatmap(data: [:]))
    } catch let error as VideoPlayerError {
      guard isViewActive else { return }
      loadingState = .loaderFailed(error)
    } catch {
      guard isViewActive else { return }
      loadingState = .failed
    }
  }
  
  /// Attempts to load video from cache
  @MainActor
  private func loadFromCache(cacheKey: String) async -> Bool {
    guard let cachedVideoURL = VideoCacheManager.shared.getCachedVideoURL(cacheKey: cacheKey) else {
      return false
    }

    guard let offlineVideo = VideoCacheManager.shared.getOfflineVideo(cacheKey: cacheKey) else {
      return false
    }

    var video = Video(
      guid: offlineVideo.videoId,
      chaptersList: nil,
      moments: [],
      thumbnailCount: 0,
      width: offlineVideo.metadata.width,
      height: offlineVideo.metadata.height,
      length: offlineVideo.metadata.duration,
      captions: [],
      libraryId: offlineVideo.libraryId,
      resolutions: [Video.Resolution.auto],
      seekPath: nil,
      playlistUrl: cachedVideoURL.absoluteString
    )
    
    let player = MediaPlayer.makeOffline(url: cachedVideoURL)
    self.player = player
    onPlayerReady?(player)
    video.adjustLength(player.duration)

    guard isViewActive else {
      teardownPlayer()
      return false
    }
    loadingState = .loaded(player, video, Heatmap(data: [:]))
    
    return true
  }

  /// Returns a reload button view for retrying video loading.
  private func reloadButton() -> some View {
    Button {
      Task { await loadVideo() }
    } label: {
      theme.images.reload
        .resizable()
        .scaledToFill()
        .frame(width: 40, height: 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Returns an error view based on the specific `VideoPlayerError` encountered.
  private func errorView(for error: VideoPlayerError) -> some View {
    VStack(spacing: 8) {
      switch error {
      case .notFound:
        theme.images.videoNotFound
          .resizable()
          .scaledToFill()
          .frame(width: 40, height: 40)
        Text(Lingua.Player.videoNotFound)
          .font(theme.font.size(11))
      case .audioError:
        Text(Lingua.Error.audioError)
          .font(theme.font.size(13))
        reloadButton()
      default:
        reloadButton()
      }
    }
  }

  /// Configures the audio session for video playback.
  private func setupAudioSession() {
#if os(iOS)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
      try session.setActive(true)
    } catch {
      player?.stop()
      loadingState = .loaderFailed(.audioError)
    }
#endif
  }
  
  /// Configures Kingfisher to use Referer header for CDN bypass.
  private func configureKingfisherHeaders() {
    // Configure Kingfisher to use Referer header for all image requests
    var headers = KingfisherManager.shared.downloader.sessionConfiguration.httpAdditionalHeaders ?? [:]
    let refererValue = referer ?? "https://iframe.mediadelivery.net/"
    headers["Referer"] = refererValue
    KingfisherManager.shared.downloader.sessionConfiguration.httpAdditionalHeaders = headers
    
    // Also configure the default downloader
    let downloader = KingfisherManager.shared.downloader
    var config = downloader.sessionConfiguration
    config.httpAdditionalHeaders = headers
    downloader.sessionConfiguration = config
    
  }
}
