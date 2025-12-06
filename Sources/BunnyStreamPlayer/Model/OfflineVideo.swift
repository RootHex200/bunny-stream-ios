import Foundation
import AVFoundation

/// Represents a video that has been downloaded for offline playback
public struct OfflineVideo: Codable {
  /// Unique cache key for this video
  public let cacheKey: String
  
  /// Video ID from Bunny Stream
  public let videoId: String
  
  /// Library ID
  public let libraryId: Int
  
  /// Local file path where the video is stored
  public let localPath: String
  
  /// Date when the video was downloaded
  public let downloadDate: Date
  
  /// Size of the downloaded video in bytes
  public let fileSize: Int64
  
  /// Video metadata
  public let metadata: VideoMetadata
  
  public struct VideoMetadata: Codable {
    public let title: String?
    public let thumbnailUrl: String?
    public let duration: Double
    public let width: CGFloat
    public let height: CGFloat
    
    public init(title: String?, thumbnailUrl: String?, duration: Double, width: CGFloat, height: CGFloat) {
      self.title = title
      self.thumbnailUrl = thumbnailUrl
      self.duration = duration
      self.width = width
      self.height = height
    }
  }
  
  public init(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    localPath: String,
    downloadDate: Date,
    fileSize: Int64,
    metadata: VideoMetadata
  ) {
    self.cacheKey = cacheKey
    self.videoId = videoId
    self.libraryId = libraryId
    self.localPath = localPath
    self.downloadDate = downloadDate
    self.fileSize = fileSize
    self.metadata = metadata
  }
}

/// Status of a video download
public enum DownloadStatus: String, Codable {
  case notStarted
  case downloading
  case paused
  case completed
  case failed
  case cancelled
}

/// Progress information for a downloading video
public struct DownloadProgress {
  public let cacheKey: String
  public let status: DownloadStatus
  public let progress: Double // 0.0 to 1.0
  public let downloadedSize: Int64
  public let totalSize: Int64
  public let error: Error?
  
  public init(
    cacheKey: String,
    status: DownloadStatus,
    progress: Double,
    downloadedSize: Int64,
    totalSize: Int64,
    error: Error? = nil
  ) {
    self.cacheKey = cacheKey
    self.status = status
    self.progress = progress
    self.downloadedSize = downloadedSize
    self.totalSize = totalSize
    self.error = error
  }
}

