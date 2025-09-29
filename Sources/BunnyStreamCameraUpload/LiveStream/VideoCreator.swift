import Foundation
import BunnyStreamAPI

final class VideoCreator {
  private let bunnyStreamAPI: BunnyStreamAPI
  private let libraryId: Int
  
  init(bunnyStreamAPI: BunnyStreamAPI,
       libraryId: Int) {
    self.bunnyStreamAPI = bunnyStreamAPI
    self.libraryId = libraryId
  }
  
  func createVideo() async throws -> String? {
    do {
      let videoId = try await bunnyStreamAPI.createVideo(
        libraryId: libraryId,
        title: "streaming_title"
      )
      return videoId
    } catch BunnyStreamAPIError.unauthorized {
      throw VideoCreatorError.failedToCreateVideoWithReason(message: "Not authorized to create videos in this library!")
    } catch {
      throw VideoCreatorError.failedToCreateVideo
    }
  }
  
  func deleteVideo(_ videoId: String) async throws {
    try await bunnyStreamAPI.deleteVideo(
      libraryId: libraryId,
      videoId: videoId.lowercased()
    )
  }
}

extension VideoCreator {
  enum VideoCreatorError: LocalizedError {
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
