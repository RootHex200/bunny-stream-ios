//
//  VideoListViewModel.swift
//  Example-App
//
//  Created by Egzon Arifi on 06/10/2023.
//

import Foundation
import BunnyStreamAPI
import BunnyStreamPlayer
import SwiftUI

@MainActor
class VideoListViewModel: ObservableObject {
  let bunnyStreamAPI: BunnyStreamAPI
  let videoPlayerConfigLoader: VideoPlayerConfigLoader
  @Published var videoInfos: [VideoResponseInfo] = []
  @Published var loadingState: LoadingState = .loading
  @Published var thumbnails: [VideoResponseInfo: URL] = [:]
  
  enum LoadingState {
    case loading, loaded, failed(String)
  }
  
  init(
    bunnyStreamAPI: BunnyStreamAPI,
    videoPlayerConfigLoader: VideoPlayerConfigLoader = .init()
  ) {
    self.bunnyStreamAPI = bunnyStreamAPI
    self.videoPlayerConfigLoader = videoPlayerConfigLoader
  }
  
  func loadVideos(libraryId: Int64) async {
    do {
      loadingState = .loading
      let videoListResponse = try await bunnyStreamAPI.listVideos(libraryId: Int(libraryId))
      handleVideoListResponse(videoListResponse)
    } catch BunnyStreamAPIError.unauthorized {
      loadingState = .failed("Unauthorized")
    } catch BunnyStreamAPIError.internalServerError {
      loadingState = .failed("Internal Server Error")
    } catch {
      loadingState = .failed(error.localizedDescription)
    }
  }
  
  func deleteVideo(_ video: VideoResponseInfo) async {
    do {
      try await bunnyStreamAPI.deleteVideo(
        libraryId: Int(video.libraryId),
        videoId: video.id
      )
      if let index = videoInfos.firstIndex(where: { $0.id == video.id }) {
        withAnimation {
          _ = videoInfos.remove(at: index)
        }
      }
    } catch {
      // Handle error silently for now
    }
  }
  
  @MainActor
  func loadThumbnailIfNeeded(_ video: VideoResponseInfo) async {
    if thumbnails[video] != nil {
      return
    }
    
    do {
      let thumbnailUrl = try await videoPlayerConfigLoader.loadVideoThumbnail(
        libraryId: Int(video.libraryId),
        videoId: video.id
      )
      guard let url = URL(string: thumbnailUrl) else {
        return
      }
      thumbnails[video] = url
    } catch {
      ///
    }
  }
}

// MARK: - Private
private extension VideoListViewModel {
  private func handleVideoListResponse(_ response: VideoListResponse) {
    guard let items = response.items else { 
      loadingState = .failed("No videos found")
      return 
    }
    
    videoInfos = items.map { video in
      VideoResponseInfo(
        id: video.guid ?? "",
        title: video.title,
        thumbnailCount: Int32(video.thumbnailCount ?? 0),
        width: Float(video.width ?? 0),
        height: Float(video.height ?? 0),
        length: Int32(video.length ?? 0),
        libraryId: Int64(video.videoLibraryId ?? 0),
        encodeProgress: Int32(video.encodeProgress ?? 0),
        storageSize: Double(video.storageSize ?? 0),
        thumbnailFileName: video.thumbnailFileName,
        averageWatchTime: Int64(video.averageWatchTime ?? 0),
        views: video.views ?? 0
      )
    }
    
    withAnimation {
      loadingState = .loaded
    }
  }
}
