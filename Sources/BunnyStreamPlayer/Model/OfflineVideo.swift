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

  /// Where the downloaded package sits **relative to the app's home directory**.
  ///
  /// An absolute path cannot be persisted. iOS rebuilds the app container under
  /// a new UUID on every install and update, so a stored absolute path is dead
  /// the next time the app launches — the entry gets dropped as "missing" and
  /// the download silently disappears. Resolving against `NSHomeDirectory()` at
  /// read time is what Apple's own HLSCatalog sample does, and it additionally
  /// discards the `/.nofollow` prefix the simulator puts on download locations.
  public let relativePath: String

  /// Date when the video was downloaded
  public let downloadDate: Date

  /// Size of the downloaded video in bytes
  public let fileSize: Int64

  /// Video metadata
  public let metadata: VideoMetadata

  /// Absolute location of the downloaded package in *this* process.
  public var localURL: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativePath)
  }

  /// Absolute path of the downloaded package in *this* process.
  public var localPath: String { localURL.path }

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
    localURL: URL,
    downloadDate: Date,
    fileSize: Int64,
    metadata: VideoMetadata
  ) {
    self.cacheKey = cacheKey
    self.videoId = videoId
    self.libraryId = libraryId
    self.relativePath = Self.relativize(localURL.path)
    self.downloadDate = downloadDate
    self.fileSize = fileSize
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case cacheKey, videoId, libraryId, relativePath, localPath, downloadDate, fileSize, metadata
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cacheKey = try container.decode(String.self, forKey: .cacheKey)
    videoId = try container.decode(String.self, forKey: .videoId)
    libraryId = try container.decode(Int.self, forKey: .libraryId)
    downloadDate = try container.decode(Date.self, forKey: .downloadDate)
    fileSize = try container.decode(Int64.self, forKey: .fileSize)
    metadata = try container.decode(VideoMetadata.self, forKey: .metadata)

    if let relative = try container.decodeIfPresent(String.self, forKey: .relativePath) {
      relativePath = relative
    } else {
      // Written before locations were stored relative. The media itself is
      // still on disk at the same spot inside the current container, so
      // trimming the stale absolute path back to a relative one recovers it
      // instead of stranding the user's download.
      let legacy = try container.decodeIfPresent(String.self, forKey: .localPath) ?? ""
      relativePath = Self.relativize(legacy)
    }
  }

  /// Writes only `relativePath`; `localPath` exists in the key set purely to
  /// read entries written by older builds.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cacheKey, forKey: .cacheKey)
    try container.encode(videoId, forKey: .videoId)
    try container.encode(libraryId, forKey: .libraryId)
    try container.encode(relativePath, forKey: .relativePath)
    try container.encode(downloadDate, forKey: .downloadDate)
    try container.encode(fileSize, forKey: .fileSize)
    try container.encode(metadata, forKey: .metadata)
  }

  /// Trims an absolute download location down to a home-relative one.
  ///
  /// Handles the two ways an absolute path arrives wrong: the simulator's
  /// `/.nofollow` prefix, and a container UUID belonging to a previous install.
  /// Everything from `Library/` onward is stable across both.
  static func relativize(_ absolutePath: String) -> String {
    let separators = CharacterSet(charactersIn: "/")
    let home = NSHomeDirectory()

    if absolutePath.hasPrefix(home) {
      return String(absolutePath.dropFirst(home.count))
        .trimmingCharacters(in: separators)
    }

    // Written by a previous install, so the container UUID in the path no
    // longer matches this one (and on the simulator the path is additionally
    // prefixed with `/.nofollow`). Everything after the container root is
    // still accurate, so cut there.
    let containerMarker = "/Containers/Data/Application/"
    if let marker = absolutePath.range(of: containerMarker) {
      let afterMarker = absolutePath[marker.upperBound...]
      if let uuidEnd = afterMarker.firstIndex(of: "/") {
        return String(afterMarker[afterMarker.index(after: uuidEnd)...])
          .trimmingCharacters(in: separators)
      }
    }

    // Last resort. Searched from the end on purpose: a simulator path also
    // contains the *host* account's `/Users/<name>/Library/...`, and matching
    // that one would keep the whole dead container prefix.
    if let library = absolutePath.range(of: "/Library/", options: .backwards) {
      return String(absolutePath[library.lowerBound...])
        .trimmingCharacters(in: separators)
    }

    return absolutePath.trimmingCharacters(in: separators)
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

