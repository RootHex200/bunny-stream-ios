import SwiftUI
import Combine

/// Example implementation showing how to use offline video playback
///
/// This example demonstrates:
/// 1. Downloading a video with a cache key
/// 2. Monitoring download progress
/// 3. Playing video from cache when offline
/// 4. Managing downloaded videos

// MARK: - Example View Model

class OfflineVideoViewModel: ObservableObject {
  @Published var downloadProgress: Double = 0.0
  @Published var downloadStatus: DownloadStatus = .notStarted
  @Published var isDownloaded: Bool = false
  @Published var downloadedVideos: [OfflineVideo] = []
  @Published var errorMessage: String?
  
  private var cancellables = Set<AnyCancellable>()
  
  let offlineManager = BunnyOfflineManager.shared
  
  init() {
    setupProgressSubscription()
    refreshDownloadedVideos()
  }
  
  // MARK: - Setup
  
  private func setupProgressSubscription() {
    // Subscribe to download progress updates
    offlineManager.downloadProgressPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] progress in
        guard let self = self else { return }
        self.downloadProgress = progress.progress
        self.downloadStatus = progress.status
        
        if progress.status == .completed {
          self.isDownloaded = true
          self.refreshDownloadedVideos()
        }
      }
      .store(in: &cancellables)
  }
  
  // MARK: - Download Actions
  
  /// Download a video for offline playback
  func downloadVideo(
    cacheKey: String,
    videoId: String,
    libraryId: Int,
    token: String? = nil,
    expires: Int? = nil
  ) {
    print("Starting download for cache key: \(cacheKey)")
    
    // Reset state
    downloadProgress = 0.0
    downloadStatus = .downloading
    errorMessage = nil
    
    // Start download
    offlineManager.downloadVideo(
      cacheKey: cacheKey,
      videoId: videoId,
      libraryId: libraryId,
      token: token,
      expires: expires
    ) { [weak self] success, error in
      guard let self = self else { return }
      
      if !success {
        self.errorMessage = error?.localizedDescription ?? "Download failed"
        self.downloadStatus = .failed
      }
    }
  }
  
  /// Check if a video is downloaded
  func checkIfDownloaded(cacheKey: String) {
    isDownloaded = offlineManager.isVideoDownloaded(cacheKey: cacheKey)
  }
  
  /// Pause current download
  func pauseDownload(cacheKey: String) {
    offlineManager.pauseDownload(cacheKey: cacheKey)
  }
  
  /// Resume paused download
  func resumeDownload(cacheKey: String) {
    offlineManager.resumeDownload(cacheKey: cacheKey)
  }
  
  /// Cancel current download
  func cancelDownload(cacheKey: String) {
    offlineManager.cancelDownload(cacheKey: cacheKey)
    downloadProgress = 0.0
    downloadStatus = .cancelled
  }
  
  /// Delete downloaded video
  func deleteVideo(cacheKey: String) {
    let success = offlineManager.deleteVideo(cacheKey: cacheKey)
    if success {
      isDownloaded = false
      refreshDownloadedVideos()
    }
  }
  
  // MARK: - Cache Management
  
  /// Get all downloaded videos
  func refreshDownloadedVideos() {
    downloadedVideos = offlineManager.getAllDownloadedVideos()
  }
  
  /// Get total cache size
  func getTotalCacheSize() -> String {
    let bytes = offlineManager.getTotalCacheSize()
    let mb = Double(bytes) / (1024 * 1024)
    return String(format: "%.2f MB", mb)
  }
  
  /// Clear all downloads
  func clearAllDownloads() {
    offlineManager.clearAllDownloads()
    refreshDownloadedVideos()
    isDownloaded = false
  }
}

// MARK: - Example SwiftUI View

struct OfflineVideoExampleView: View {
  @StateObject private var viewModel = OfflineVideoViewModel()
  
  // Video configuration
  let cacheKey = "my_video_1"
  let videoId = "your_video_id"
  let libraryId = 12345
  
  var body: some View {
    VStack(spacing: 20) {
      
      // Download Section
      VStack(spacing: 10) {
        Text("Download Management")
          .font(.headline)
        
        if viewModel.isDownloaded {
          Text("✓ Video Downloaded")
            .foregroundColor(.green)
          
          Button("Delete Download") {
            viewModel.deleteVideo(cacheKey: cacheKey)
          }
          .foregroundColor(.red)
        } else {
          // Show download progress
          if viewModel.downloadStatus == .downloading {
            VStack {
              Text("Downloading: \(Int(viewModel.downloadProgress * 100))%")
              ProgressView(value: viewModel.downloadProgress)
              
              HStack {
                Button("Pause") {
                  viewModel.pauseDownload(cacheKey: cacheKey)
                }
                
                Button("Cancel") {
                  viewModel.cancelDownload(cacheKey: cacheKey)
                }
                .foregroundColor(.red)
              }
            }
          } else if viewModel.downloadStatus == .paused {
            VStack {
              Text("Paused: \(Int(viewModel.downloadProgress * 100))%")
              Button("Resume") {
                viewModel.resumeDownload(cacheKey: cacheKey)
              }
            }
          } else {
            Button("Download Video") {
              viewModel.downloadVideo(
                cacheKey: cacheKey,
                videoId: videoId,
                libraryId: libraryId
              )
            }
          }
        }
        
        if let error = viewModel.errorMessage {
          Text("Error: \(error)")
            .foregroundColor(.red)
            .font(.caption)
        }
      }
      .padding()
      .background(Color.gray.opacity(0.1))
      .cornerRadius(10)
      
      // Video Player Section
      VStack(spacing: 10) {
        Text("Video Player")
          .font(.headline)
        
        // Play video with cache key for offline support
        BunnyStreamPlayer(
          accessKey: nil, // Can be nil for offline playback
          videoId: videoId,
          libraryId: libraryId,
          cacheKey: cacheKey // This enables offline playback
        )
        .frame(height: 250)
        .cornerRadius(10)
        
        Text("Player will use cache if available, otherwise streams online")
          .font(.caption)
          .foregroundColor(.gray)
      }
      
      // Downloaded Videos List
      VStack(spacing: 10) {
        Text("Downloaded Videos (\(viewModel.getTotalCacheSize()))")
          .font(.headline)
        
        if viewModel.downloadedVideos.isEmpty {
          Text("No downloaded videos")
            .foregroundColor(.gray)
        } else {
          List(viewModel.downloadedVideos, id: \.cacheKey) { video in
            VStack(alignment: .leading) {
              Text(video.cacheKey)
                .font(.headline)
              Text("Duration: \(Int(video.metadata.duration))s")
                .font(.caption)
              Text("Size: \(formatBytes(video.fileSize))")
                .font(.caption)
              Text("Downloaded: \(formatDate(video.downloadDate))")
                .font(.caption)
            }
          }
          .frame(height: 200)
          
          Button("Clear All Downloads") {
            viewModel.clearAllDownloads()
          }
          .foregroundColor(.red)
        }
      }
      .padding()
      .background(Color.gray.opacity(0.1))
      .cornerRadius(10)
      
      Spacer()
    }
    .padding()
    .onAppear {
      viewModel.checkIfDownloaded(cacheKey: cacheKey)
    }
  }
  
  private func formatBytes(_ bytes: Int64) -> String {
    let mb = Double(bytes) / (1024 * 1024)
    return String(format: "%.2f MB", mb)
  }
  
  private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

// MARK: - Usage Examples in Code

/*
 
 // EXAMPLE 1: Simple offline playback
 // ---------------------------------
 // Just add the cacheKey parameter to BunnyStreamPlayer
 
 BunnyStreamPlayer(
   accessKey: nil,
   videoId: "your_video_id",
   libraryId: 12345,
   cacheKey: "my_cached_video" // This enables offline support
 )
 
 
 // EXAMPLE 2: Download a video for offline use
 // --------------------------------------------
 
 BunnyOfflineManager.shared.downloadVideo(
   cacheKey: "my_video_1",
   videoId: "abc123",
   libraryId: 12345
 ) { success, error in
   if success {
     print("Download started successfully")
   } else {
     print("Failed to start download: \(error?.localizedDescription ?? "Unknown error")")
   }
 }
 
 
 // EXAMPLE 3: Monitor download progress
 // -------------------------------------
 
 import Combine
 
 var cancellables = Set<AnyCancellable>()
 
 BunnyOfflineManager.shared.downloadProgressPublisher
   .receive(on: DispatchQueue.main)
   .sink { progress in
     print("Video: \(progress.cacheKey)")
     print("Progress: \(Int(progress.progress * 100))%")
     print("Status: \(progress.status)")
     
     if progress.status == .completed {
       print("Download completed!")
     }
   }
   .store(in: &cancellables)
 
 
 // EXAMPLE 4: Check if video is downloaded
 // ----------------------------------------
 
 let cacheKey = "my_video_1"
 
 if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey) {
   // Video is available offline
   print("Video is cached and ready for offline playback")
 } else {
   // Need to download or stream online
   print("Video not cached")
 }
 
 
 // EXAMPLE 5: Manage downloads
 // ---------------------------
 
 // Pause download
 BunnyOfflineManager.shared.pauseDownload(cacheKey: "my_video_1")
 
 // Resume download
 BunnyOfflineManager.shared.resumeDownload(cacheKey: "my_video_1")
 
 // Cancel download
 BunnyOfflineManager.shared.cancelDownload(cacheKey: "my_video_1")
 
 // Delete downloaded video
 BunnyOfflineManager.shared.deleteVideo(cacheKey: "my_video_1")
 
 
 // EXAMPLE 6: Get all downloaded videos
 // -------------------------------------
 
 let downloadedVideos = BunnyOfflineManager.shared.getAllDownloadedVideos()
 
 for video in downloadedVideos {
   print("Cache Key: \(video.cacheKey)")
   print("Video ID: \(video.videoId)")
   print("File Size: \(video.fileSize) bytes")
   print("Duration: \(video.metadata.duration) seconds")
   print("Downloaded: \(video.downloadDate)")
   print("---")
 }
 
 
 // EXAMPLE 7: Get cache information
 // ---------------------------------
 
 // Get total cache size
 let totalBytes = BunnyOfflineManager.shared.getTotalCacheSize()
 let totalMB = Double(totalBytes) / (1024 * 1024)
 print("Total cache size: \(totalMB) MB")
 
 // Get info for specific video
 if let videoInfo = BunnyOfflineManager.shared.getVideoInfo(cacheKey: "my_video_1") {
   print("Video duration: \(videoInfo.metadata.duration) seconds")
   print("Video size: \(videoInfo.fileSize) bytes")
 }
 
 
 // EXAMPLE 8: Clear all cache
 // ---------------------------
 
 BunnyOfflineManager.shared.clearAllDownloads()
 print("All cached videos cleared")
 
 
 // EXAMPLE 9: Integration with existing player
 // --------------------------------------------
 
 struct MyVideoPlayerView: View {
   let videoId: String
   let libraryId: Int
   let cacheKey: String
   
   @State private var isDownloaded = false
   
   var body: some View {
     VStack {
       // Show download status
       if isDownloaded {
         Text("✓ Available Offline")
           .foregroundColor(.green)
       } else {
         Text("Streaming Online")
           .foregroundColor(.orange)
       }
       
       // Player automatically uses cache if available
       BunnyStreamPlayer(
         accessKey: "your_access_key",
         videoId: videoId,
         libraryId: libraryId,
         cacheKey: cacheKey
       )
       
       // Download button
       if !isDownloaded {
         Button("Download for Offline") {
           downloadVideo()
         }
       }
     }
     .onAppear {
       checkIfDownloaded()
     }
   }
   
   private func checkIfDownloaded() {
     isDownloaded = BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey)
   }
   
   private func downloadVideo() {
     BunnyOfflineManager.shared.downloadVideo(
       cacheKey: cacheKey,
       videoId: videoId,
       libraryId: libraryId
     ) { success, error in
       if success {
         print("Download started")
       }
     }
   }
 }
 
 */

