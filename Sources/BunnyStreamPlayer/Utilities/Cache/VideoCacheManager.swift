import Foundation
import AVFoundation
import Combine
import UserNotifications

/// Manager for downloading and caching HLS videos for offline playback
public class VideoCacheManager: NSObject {
  
  public static let shared = VideoCacheManager()
  
  // MARK: - Properties
  
  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private let metadataFileName = "cache_metadata.json"
  
  /// Dictionary to track active downloads
  private var activeDownloads: [String: AVAggregateAssetDownloadTask] = [:]
  
  /// Dictionary to track download locations
  private var downloadLocations: [String: URL] = [:]
  
  /// Metadata supplied at download time, held until completion.
  ///
  /// Completion used to rebuild this from the task description, discarding the
  /// title, duration and thumbnail the caller passed — which left the
  /// downloads list with placeholder rows.
  private var pendingMetadata: [String: OfflineVideo.VideoMetadata] = [:]

  /// Context info for active downloads
  private struct DownloadContext {
    let videoId: String
    let libraryId: Int
  }
  private var downloadContexts: [String: DownloadContext] = [:]
  
  /// Dictionary to track download progress
  
  /// Dictionary to track download progress
  private var downloadProgress: [String: DownloadProgress] = [:]
  
  /// Publisher for download progress updates
  public let progressPublisher = PassthroughSubject<DownloadProgress, Never>()
  
  /// Last time notification was updated for a key
  private var lastNotificationUpdateTime: [String: Date] = [:]
  
  /// Cached video metadata
  
  /// Cached video metadata
  private var cachedVideos: [String: OfflineVideo] = [:]
  
  /// Wi-Fi-only download session.
  ///
  /// Two sessions exist because `allowsCellularAccess` is fixed when a session
  /// is created and a background session's identifier cannot be reused, so a
  /// runtime-toggleable preference cannot be served by one. Each download
  /// starts on whichever session the preference selects and keeps running
  /// there, so toggling never orphans an in-flight task.
  private var wifiOnlySession: AVAssetDownloadURLSession!

  /// Cellular-allowed download session.
  private var cellularSession: AVAssetDownloadURLSession!

  /// Which session new downloads start on.
  private var wifiOnly: Bool = true
  
  // MARK: - Initialization
  
  private override init() {
    // Application Support, not Documents. Documents is exposed to the Files
    // app and iTunes the moment UIFileSharingEnabled is ever switched on, and
    // it is included in iCloud/iTunes backups. Downloaded lesson video is
    // neither the user's document nor something worth backing up.
    let supportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    cacheDirectory = supportPath.appendingPathComponent("BunnyStreamCache", isDirectory: true)

    super.init()

    createProtectedCacheDirectory()

    // Content written by an earlier build sits unprotected under Documents.
    // Delete it rather than migrate: it was written without protection, so
    // re-downloading is the honest remedy.
    purgeLegacyUnprotectedCache()

    // Setup background session
    setupBackgroundSession()

    // Load cached videos metadata
    loadCachedVideosMetadata()

    print("[VideoCacheManager] Initialized with cache directory: \(cacheDirectory.path)")
  }

  /// Creates the cache directory with data protection applied and excluded
  /// from backup.
  ///
  /// Protection class is `completeUnlessOpen` rather than `complete`: a
  /// background download writes after the screen locks, and `complete` would
  /// make those writes fail. `completeUnlessOpen` keeps the bytes encrypted at
  /// rest while allowing a file already open for writing to continue — which
  /// is exactly the background-download case, and still leaves nothing
  /// readable to a non-rooted extraction.
  private func createProtectedCacheDirectory() {
    try? fileManager.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
    )

    var directory = cacheDirectory
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? directory.setResourceValues(resourceValues)
  }

  /// Applies protection and backup exclusion to a freshly downloaded item.
  ///
  /// The directory attributes do not propagate to files AVFoundation writes
  /// into it, so each finished download is stamped individually.
  private func protect(_ url: URL) {
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUnlessOpen],
      ofItemAtPath: url.path
    )

    var target = url
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try? target.setResourceValues(resourceValues)
  }

  /// Removes the pre-protection cache from the Documents directory.
  private func purgeLegacyUnprotectedCache() {
    let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let legacy = documentsPath.appendingPathComponent("BunnyStreamCache", isDirectory: true)
    guard fileManager.fileExists(atPath: legacy.path) else { return }

    print("[VideoCacheManager] Removing legacy unprotected cache at \(legacy.path)")
    try? fileManager.removeItem(at: legacy)
  }
  
  private func setupBackgroundSession() {
    wifiOnlySession = makeSession(
      identifier: "com.bunnystream.download.wifi",
      allowsCellular: false
    )
    cellularSession = makeSession(
      identifier: "com.bunnystream.download.cellular",
      allowsCellular: true
    )

    // A background session outlives the process. Re-adopt whatever it is still
    // carrying, or a download interrupted by app termination becomes
    // unreachable — the tracking map starts empty on every launch.
    restoreInFlightDownloads()
  }

  private func makeSession(
    identifier: String,
    allowsCellular: Bool
  ) -> AVAssetDownloadURLSession {
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = allowsCellular

    return AVAssetDownloadURLSession(
      configuration: config,
      assetDownloadDelegate: self,
      delegateQueue: OperationQueue.main
    )
  }

  /// Restores tasks still running in either background session after a
  /// relaunch, so an interrupted download resumes instead of disappearing.
  private func restoreInFlightDownloads() {
    for session in [wifiOnlySession, cellularSession] {
      session?.getAllTasks { [weak self] tasks in
        guard let self = self else { return }
        for case let task as AVAggregateAssetDownloadTask in tasks {
          guard let cacheKey = task.taskDescription, !cacheKey.isEmpty else { continue }

          self.activeDownloads[cacheKey] = task
          let progress = DownloadProgress(
            cacheKey: cacheKey,
            status: .downloading,
            progress: 0,
            downloadedSize: 0,
            totalSize: 0
          )
          self.downloadProgress[cacheKey] = progress
          self.progressPublisher.send(progress)
          print("[VideoCacheManager] Re-adopted in-flight download: \(cacheKey)")
        }
      }
    }
  }

  /// Selects which session new downloads start on. In-flight downloads keep
  /// running on the session that owns them.
  public func setWifiOnly(_ enabled: Bool) {
    wifiOnly = enabled
  }
  
  // MARK: - Public Methods
  
  /// Download a video for offline playback
  /// - Parameters:
  ///   - cacheKey: Unique key to identify this cached video
  ///   - videoId: Bunny Stream video ID
  ///   - libraryId: Library ID
  ///   - playlistUrl: HLS playlist URL
  ///   - metadata: Video metadata
  /// - Returns: True if download started successfully
  @discardableResult
  public func downloadVideo(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    playlistUrl: String,
    metadata: OfflineVideo.VideoMetadata
  ) -> Bool {
    print("[VideoCacheManager] Starting download for cache key: \(cacheKey)")
    
    // Check if already downloaded
    if isCached(cacheKey: cacheKey) {
      print("[VideoCacheManager] Video already cached with key: \(cacheKey)")
      return false
    }
    
    // Check if already downloading
    if activeDownloads[cacheKey] != nil {
      print("[VideoCacheManager] Download already in progress for key: \(cacheKey)")
      return false
    }
    
    guard let url = URL(string: playlistUrl) else {
      print("[VideoCacheManager] Invalid playlist URL: \(playlistUrl)")
      return false
    }
    
    // Check for HLS
    if playlistUrl.contains(".m3u8") {
        print("[VideoCacheManager] Identified HLS stream for download: \(url.lastPathComponent)")
    }
    
    // Create download location
    let downloadLocation = cacheDirectory.appendingPathComponent(cacheKey, isDirectory: true)
    
    // Create AVURLAsset
    // For HLS, we use AVURLAsset which handles m3u8 playlists natively
    let asset = AVURLAsset(url: url)
    
    // Get preferred media selection
    let preferredMediaSelection = asset.preferredMediaSelection
    
    // Create download task
    let session = wifiOnly ? wifiOnlySession! : cellularSession!
    guard let downloadTask = session.aggregateAssetDownloadTask(
      with: asset,
      mediaSelections: [preferredMediaSelection],
      assetTitle: cacheKey,
      assetArtworkData: nil,
      options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265000]
    ) else {
      print("[VideoCacheManager] Failed to create download task")
      return false
    }
    
    // The task description is the only identifier that survives into a fresh
    // process, so restore-after-relaunch depends on it being set here.
    downloadTask.taskDescription = cacheKey

    // Store download info
    activeDownloads[cacheKey] = downloadTask
    pendingMetadata[cacheKey] = metadata
    downloadContexts[cacheKey] = DownloadContext(videoId: videoId, libraryId: libraryId)
    
    // Initialize progress
    let progress = DownloadProgress(
      cacheKey: cacheKey,
      status: .downloading,
      progress: 0.0,
      downloadedSize: 0,
      totalSize: 0
    )
    downloadProgress[cacheKey] = progress
    progressPublisher.send(progress)
    
    // Start download
    downloadTask.resume()
    
    // Setup notifications
    requestNotificationPermission()
    updateNotification(cacheKey: cacheKey, title: metadata.title, progress: 0.0, status: .downloading)
    
    print("[VideoCacheManager] Download task started for: \(cacheKey)")
    return true
  }
  
  /// Request notification permissions
  public func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        print("[VideoCacheManager] Notification permission granted")
      } else if let error = error {
        print("[VideoCacheManager] Notification permission error: \(error.localizedDescription)")
      }
    }
  }
  
  /// Update notification for download
  private func updateNotification(cacheKey: String, title: String? = nil, progress: Double, status: DownloadStatus) {
    let center = UNUserNotificationCenter.current()
    
    // For completion or failure, send immediately
    if status == .completed || status == .failed {
      let content = UNMutableNotificationContent()
      content.title = status == .completed ? "Download Completed" : "Download Failed"
      content.body = title ?? "Video download \(status == .completed ? "finished" : "failed")"
      content.sound = .default
      
      let request = UNNotificationRequest(identifier: cacheKey, content: content, trigger: nil)
      center.add(request)
      lastNotificationUpdateTime.removeValue(forKey: cacheKey)
      return
    }
    
    // For progress, debounce updates (every 1.5 seconds)
    if let lastUpdate = lastNotificationUpdateTime[cacheKey], Date().timeIntervalSince(lastUpdate) < 1.5 {
      return
    }
    
    let content = UNMutableNotificationContent()
    content.title = "Downloading Video"
    
    // Create text progress bar
    let percentage = Int(progress * 100)
    let barLength = 10
    let filledCount = Int((progress * Double(barLength)))
    let emptyCount = barLength - filledCount
    let bar = String(repeating: "■", count: filledCount) + String(repeating: "□", count: emptyCount)
    
    content.body = "\(bar) \(percentage)%"
    if let title = title {
      content.body = "\(title)\n" + content.body
    }
    
    // Determine sound - only minimal or none for updates to avoid annoyance
    // content.sound = nil 
    
    let request = UNNotificationRequest(identifier: cacheKey, content: content, trigger: nil)
    center.add(request)
    lastNotificationUpdateTime[cacheKey] = Date()
  }
  
  /// Check if a video is cached
  /// - Parameter cacheKey: Cache key to check
  /// - Returns: True if video is cached
  public func isCached(cacheKey: String) -> Bool {
    return cachedVideos[cacheKey] != nil
  }
  
  /// Get local URL for cached video
  /// - Parameter cacheKey: Cache key
  /// - Returns: Local URL if video is cached, nil otherwise
  public func getCachedVideoURL(cacheKey: String) -> URL? {
    guard let offlineVideo = cachedVideos[cacheKey] else {
      return nil
    }
    
    return URL(fileURLWithPath: offlineVideo.localPath)
  }
  
  /// Get offline video info
  /// - Parameter cacheKey: Cache key
  /// - Returns: OfflineVideo if cached, nil otherwise
  public func getOfflineVideo(cacheKey: String) -> OfflineVideo? {
    return cachedVideos[cacheKey]
  }
  
  /// Get all cached videos
  /// - Returns: Array of all cached videos
  public func getAllCachedVideos() -> [OfflineVideo] {
    return Array(cachedVideos.values)
  }
  
  /// Delete cached video
  /// - Parameter cacheKey: Cache key to delete
  /// - Returns: True if deletion was successful
  @discardableResult
  public func deleteCachedVideo(cacheKey: String) -> Bool {
    print("[VideoCacheManager] Deleting cached video: \(cacheKey)")
    
    // Cancel active download if any
    if let downloadTask = activeDownloads[cacheKey] {
      downloadTask.cancel()
      activeDownloads.removeValue(forKey: cacheKey)
    }
    
    // Remove from cached videos
    guard let offlineVideo = cachedVideos.removeValue(forKey: cacheKey) else {
      print("[VideoCacheManager] Video not found in cache: \(cacheKey)")
      return false
    }
    
    // Delete files
    let videoURL = URL(fileURLWithPath: offlineVideo.localPath)
    try? fileManager.removeItem(at: videoURL)
    
    // Delete parent directory if it exists
    let parentDir = cacheDirectory.appendingPathComponent(cacheKey, isDirectory: true)
    try? fileManager.removeItem(at: parentDir)
    
    // Save updated metadata
    saveCachedVideosMetadata()
    
    print("[VideoCacheManager] Successfully deleted cached video: \(cacheKey)")
    return true
  }
  
  /// Pause an active download
  /// - Parameter cacheKey: Cache key
  public func pauseDownload(cacheKey: String) {
    guard let downloadTask = activeDownloads[cacheKey] else { return }
    downloadTask.suspend()
    
    if var progress = downloadProgress[cacheKey] {
      progress = DownloadProgress(
        cacheKey: progress.cacheKey,
        status: .paused,
        progress: progress.progress,
        downloadedSize: progress.downloadedSize,
        totalSize: progress.totalSize
      )
      downloadProgress[cacheKey] = progress
      progressPublisher.send(progress)
    }
  }
  
  /// Resume a paused download
  /// - Parameter cacheKey: Cache key
  public func resumeDownload(cacheKey: String) {
    guard let downloadTask = activeDownloads[cacheKey] else { return }
    downloadTask.resume()
    
    if var progress = downloadProgress[cacheKey] {
      progress = DownloadProgress(
        cacheKey: progress.cacheKey,
        status: .downloading,
        progress: progress.progress,
        downloadedSize: progress.downloadedSize,
        totalSize: progress.totalSize
      )
      downloadProgress[cacheKey] = progress
      progressPublisher.send(progress)
    }
  }
  
  /// Cancel an active download
  /// - Parameter cacheKey: Cache key
  public func cancelDownload(cacheKey: String) {
    guard let downloadTask = activeDownloads[cacheKey] else { return }
    downloadTask.cancel()
    activeDownloads.removeValue(forKey: cacheKey)
    downloadProgress.removeValue(forKey: cacheKey)
    downloadLocations.removeValue(forKey: cacheKey)
    downloadContexts.removeValue(forKey: cacheKey)
    lastNotificationUpdateTime.removeValue(forKey: cacheKey)
    
    // Remove notification
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [cacheKey])
    
    let progress = DownloadProgress(
      cacheKey: cacheKey,
      status: .cancelled,
      progress: 0.0,
      downloadedSize: 0,
      totalSize: 0
    )
    progressPublisher.send(progress)
    
    // Clean up partial download
    let downloadLocation = cacheDirectory.appendingPathComponent(cacheKey, isDirectory: true)
    try? fileManager.removeItem(at: downloadLocation)
  }
  
  /// Get current download progress
  /// - Parameter cacheKey: Cache key
  /// - Returns: Download progress if download is active
  public func getDownloadProgress(cacheKey: String) -> DownloadProgress? {
    return downloadProgress[cacheKey]
  }
  
  /// Get total cache size in bytes
  /// - Returns: Total size of all cached videos
  public func getTotalCacheSize() -> Int64 {
    return cachedVideos.values.reduce(0) { $0 + $1.fileSize }
  }
  
  /// Clear all cached videos
  public func clearAllCache() {
    print("[VideoCacheManager] Clearing all cache")
    
    // Cancel all active downloads
    for (_, task) in activeDownloads {
      task.cancel()
    }
    activeDownloads.removeAll()
    downloadProgress.removeAll()
    
    // Delete all cached files
    for (_, offlineVideo) in cachedVideos {
      let videoURL = URL(fileURLWithPath: offlineVideo.localPath)
      try? fileManager.removeItem(at: videoURL)
    }
    
    // Clear cache directory
    try? fileManager.removeItem(at: cacheDirectory)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    
    cachedVideos.removeAll()
    saveCachedVideosMetadata()
  }
  
  // MARK: - Private Methods
  
  private func loadCachedVideosMetadata() {
    let metadataURL = cacheDirectory.appendingPathComponent(metadataFileName)
    
    guard fileManager.fileExists(atPath: metadataURL.path),
          let data = try? Data(contentsOf: metadataURL),
          let videos = try? JSONDecoder().decode([OfflineVideo].self, from: data) else {
      print("[VideoCacheManager] No cached metadata found")
      return
    }
    
    // Verify files still exist
    for video in videos {
      let videoURL = URL(fileURLWithPath: video.localPath)
      if fileManager.fileExists(atPath: videoURL.path) {
        cachedVideos[video.cacheKey] = video
      }
    }
    
    print("[VideoCacheManager] Loaded \(cachedVideos.count) cached videos")
  }
  
  private func saveCachedVideosMetadata() {
    let metadataURL = cacheDirectory.appendingPathComponent(metadataFileName)
    let videos = Array(cachedVideos.values)
    
    guard let data = try? JSONEncoder().encode(videos) else {
      print("[VideoCacheManager] Failed to encode metadata")
      return
    }
    
    try? data.write(to: metadataURL)
    print("[VideoCacheManager] Saved metadata for \(videos.count) videos")
  }
  
  private func getFileSize(at url: URL) -> Int64 {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
          let fileSize = attributes[.size] as? Int64 else {
      return 0
    }
    return fileSize
  }

  private func handleDownloadCompletion(task: AVAssetDownloadTask, location: URL, cacheKey: String) {
    print("[VideoCacheManager] Handling download completion for: \(cacheKey) at \(location.path)")

    // AVFoundation wrote this package itself, so the directory's attributes
    // did not reach it — stamp protection and backup exclusion now.
    protect(location)

    // Get file size
    let fileSize = getFileSize(at: location)
    
    // Use what the caller supplied; falling back only when this download
    // started in an earlier process and its metadata is gone.
    let metadata = pendingMetadata[cacheKey] ?? OfflineVideo.VideoMetadata(
      title: nil,
      thumbnailUrl: nil,
      duration: 0,
      width: 0,
      height: 0
    )
    
    // Extract videoId and libraryId based on cache key if we had that info stored
    let context = downloadContexts[cacheKey]
    let videoId = context?.videoId ?? ""
    let libraryId = context?.libraryId ?? 0
    
    // Create offline video entry
    let offlineVideo = OfflineVideo(
      cacheKey: cacheKey,
      videoId: videoId,
      libraryId: libraryId,
      localPath: location.path,
      downloadDate: Date(),
      fileSize: fileSize,
      metadata: metadata
    )
    
    // Store in cache
    cachedVideos[cacheKey] = offlineVideo
    saveCachedVideosMetadata()
    
    // Update progress
    let progress = DownloadProgress(
      cacheKey: cacheKey,
      status: .completed,
      progress: 1.0,
      downloadedSize: fileSize,
      totalSize: fileSize
    )
    downloadProgress[cacheKey] = progress
    progressPublisher.send(progress)
    
    // Notify completion
    updateNotification(cacheKey: cacheKey, title: metadata.title, progress: 1.0, status: .completed)
    
    // Remove from trackers
    activeDownloads.removeValue(forKey: cacheKey)
    downloadLocations.removeValue(forKey: cacheKey)
    downloadContexts.removeValue(forKey: cacheKey)
    pendingMetadata.removeValue(forKey: cacheKey)

    print("[VideoCacheManager] Successfully cached video with key: \(cacheKey)")
  }
}

// MARK: - AVAssetDownloadDelegate

extension VideoCacheManager: AVAssetDownloadDelegate {
  
  public func urlSession(
    _ session: URLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    print("[VideoCacheManager] Download finished to location: \(location.path)")
    
    // Find the cache key for this task
    guard let cacheKey = activeDownloads.first(where: { $0.value == assetDownloadTask })?.key else {
      print("[VideoCacheManager] Could not find cache key for completed download")
      return
    }
    
    handleDownloadCompletion(task: assetDownloadTask, location: location, cacheKey: cacheKey)
  }
  
  public func urlSession(
    _ session: URLSession,
    assetDownloadTask: AVAssetDownloadTask,
    didLoad timeRange: CMTimeRange,
    totalTimeRangesLoaded loadedTimeRanges: [NSValue],
    timeRangeExpectedToLoad: CMTimeRange
  ) {
    // Find the cache key for this task
    guard let cacheKey = activeDownloads.first(where: { $0.value == assetDownloadTask })?.key else {
      return
    }
    
    // Calculate progress
    var percentComplete = 0.0
    for value in loadedTimeRanges {
      let loadedTimeRange = value.timeRangeValue
      percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
    }
    
    // Update progress
    if var currentProgress = downloadProgress[cacheKey] {
      let updatedProgress = DownloadProgress(
        cacheKey: cacheKey,
        status: .downloading,
        progress: percentComplete,
        downloadedSize: currentProgress.downloadedSize,
        totalSize: currentProgress.totalSize
      )
      downloadProgress[cacheKey] = updatedProgress
      progressPublisher.send(updatedProgress)
    }
  }
  
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    // If no error, we might need to handle success here if didFinishDownloadingTo didn't fire
    if error == nil {
      if let downloadTask = task as? AVAssetDownloadTask,
         let cacheKey = activeDownloads.first(where: { $0.value == downloadTask })?.key,
         let location = downloadLocations[cacheKey] {
        
        print("[VideoCacheManager] Task completed without error, handling success in didCompleteWithError")
        handleDownloadCompletion(task: downloadTask, location: location, cacheKey: cacheKey)
        return
      }
    }
    
    guard let error = error else { return }
    
    // Find the cache key for this task
    guard let downloadTask = task as? AVAssetDownloadTask,
          let cacheKey = activeDownloads.first(where: { $0.value == downloadTask })?.key else {
      return
    }
    
    print("[VideoCacheManager] Download failed for \(cacheKey): \(error.localizedDescription)")
    
    // Update progress with error
    let progress = DownloadProgress(
      cacheKey: cacheKey,
      status: .failed,
      progress: 0.0,
      downloadedSize: 0,
      totalSize: 0,
      error: error
    )
    downloadProgress[cacheKey] = progress
    progressPublisher.send(progress)
    
    // Notify failure
    updateNotification(cacheKey: cacheKey, progress: 0.0, status: .failed)
    
    // Remove from active downloads and locations
    activeDownloads.removeValue(forKey: cacheKey)
    downloadLocations.removeValue(forKey: cacheKey)
    downloadContexts.removeValue(forKey: cacheKey)
  }
  
  public func urlSession(
    _ session: URLSession,
    aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
    willDownloadTo location: URL
  ) {
    print("[VideoCacheManager] Will download to: \(location.path)")
    
    // Save location for later use in completion handler
    if let cacheKey = activeDownloads.first(where: { $0.value == aggregateAssetDownloadTask })?.key {
      downloadLocations[cacheKey] = location
    }
  }
  
  public func urlSession(
    _ session: URLSession,
    aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
    didCompleteFor mediaSelection: AVMediaSelection
  ) {
    print("[VideoCacheManager] Media selection completed")
  }
  
  public func urlSession(
    _ session: URLSession,
    aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
    didLoad timeRange: CMTimeRange,
    totalTimeRangesLoaded loadedTimeRanges: [NSValue],
    timeRangeExpectedToLoad: CMTimeRange,
    for mediaSelection: AVMediaSelection
  ) {
    // Find the cache key for this task
    guard let cacheKey = activeDownloads.first(where: { $0.value == aggregateAssetDownloadTask })?.key else {
      return
    }
    
    // Calculate progress
    var percentComplete = 0.0
    for value in loadedTimeRanges {
      let loadedTimeRange = value.timeRangeValue
      percentComplete += CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
    }
    
    percentComplete = min(percentComplete, 1.0)
    
    // Update progress
    if let currentProgress = downloadProgress[cacheKey] {
      let updatedProgress = DownloadProgress(
        cacheKey: cacheKey,
        status: .downloading,
        progress: percentComplete,
        downloadedSize: currentProgress.downloadedSize,
        totalSize: currentProgress.totalSize
      )
      downloadProgress[cacheKey] = updatedProgress
      progressPublisher.send(updatedProgress)
      
      // The caller's metadata is held for the life of the download now, so
      // the notification can show the real lesson title rather than a guid.
      updateNotification(
        cacheKey: cacheKey,
        title: pendingMetadata[cacheKey]?.title,
        progress: percentComplete,
        status: .downloading
      )
      
      // Log progress periodically
      if Int(percentComplete * 100) % 10 == 0 {
        print("[VideoCacheManager] Download progress for \(cacheKey): \(Int(percentComplete * 100))%")
      }
    }
  }
}

