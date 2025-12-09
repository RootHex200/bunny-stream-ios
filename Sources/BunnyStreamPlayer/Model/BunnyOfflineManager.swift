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
  ///   - token: Optional authentication token
  ///   - expires: Optional token expiration
  ///   - referer: Optional referer header value
  ///   - completion: Callback with success status and optional error
  ///
  /// Example:
  /// ```swift
  /// BunnyOfflineManager.shared.downloadVideo(
  ///   cacheKey: "my_video_1",
  ///   videoId: "abc123",
  ///   libraryId: 12345
  /// ) { success, error in
  ///   if success {
  ///     print("Download started")
  ///   }
  /// }
  /// ```
  public func downloadVideo(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    token: String? = nil,
    expires: Int? = nil,
    referer: String? = nil,
    completion: @escaping (Bool, Error?) -> Void
  ) {
    Task {
      do {
        // Load video configuration to get playlist URL
        let videoConfigLoader = VideoPlayerConfigLoader()
        let config = try await videoConfigLoader.load(
          libraryId: libraryId,
          videoId: videoId,
          token: token,
          expires: expires,
          referer: referer
        )
        
        // Create metadata
        let metadata = OfflineVideo.VideoMetadata(
          title: nil,
          thumbnailUrl: config.thumbnailUrl,
          duration: config.video.length,
          width: CGFloat(config.video.width),
          height: CGFloat(config.video.height)
        )
        
        // Start download
        let success = cacheManager.downloadVideo(
          cacheKey: cacheKey,
          videoId: videoId,
          libraryId: libraryId,
          playlistUrl: config.videoPlaylistUrl,
          metadata: metadata
        )
        
        await MainActor.run {
          completion(success, nil)
        }
      } catch {
        await MainActor.run {
          completion(false, error)
        }
      }
    }
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
  }
}

