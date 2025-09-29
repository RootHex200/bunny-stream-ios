//
//  BunnyService.swift
//  Example-App
//
//  Created by Egzon Arifi on 16/10/2023.
//

import Foundation
import BunnyStreamAPI

final class BunnyService {
  private let bunnyStreamAPI: BunnyStreamAPI

  init(bunnyStreamAPI: BunnyStreamAPI) {
    self.bunnyStreamAPI = bunnyStreamAPI
  }
  
  func createVideo(title: String, libraryId: Int) async throws -> String? {
    do {
      let videoId = try await bunnyStreamAPI.createVideo(
        libraryId: libraryId,
        title: title
      )
      return videoId
    } catch BunnyStreamAPIError.unauthorized {
      throw VideoUploaderError.failedToCreateVideoWithReason(message: "Not authorized to create videos in this library!")
    } catch {
      throw VideoUploaderError.failedToCreateVideo
    }
  }
  
  func deleteVideo(_ videoId: String, libraryId: Int) async throws {
    try await bunnyStreamAPI.deleteVideo(
      libraryId: libraryId,
      videoId: videoId.lowercased()
    )
  }
}

extension BunnyService {
  enum VideoUploaderError: LocalizedError {
    case failedToCreateVideoWithReason(message: String)
    case failedToCreateVideo
    
    
    public var errorDescription: String? {
      switch self {
      case .failedToCreateVideoWithReason(let message):
        return "An error occurred while creating the video! \nReason: \(message)"
      case .failedToCreateVideo:
        return "An error occurred while creating the video!"
      }
    }
  }
}
