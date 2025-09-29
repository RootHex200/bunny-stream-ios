import Foundation
import SwiftUI

public struct VideoPlayerConfigLoader {
  public init() {}
  
  func load(libraryId: Int, videoId: String, token: String? = nil, expires: Int? = nil) async throws -> VideoConfigResponse {
    var urlComponents = URLComponents(string: "https://video.bunnycdn.com/library/\(libraryId)/videos/\(videoId)/play")!
    
    // Add token and expires parameters if provided
    var queryItems: [URLQueryItem] = []
    if let token = token, !token.isEmpty {
      queryItems.append(URLQueryItem(name: "token", value: token))
    }
    if let expires = expires {
      queryItems.append(URLQueryItem(name: "expires", value: String(expires)))
    }
    
    if !queryItems.isEmpty {
      urlComponents.queryItems = queryItems
    }
    
    guard let url = urlComponents.url else {
      throw VideoPlayerError.unknownError
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    request.addValue("https://iframe.mediadelivery.net/", forHTTPHeaderField: "Referer")
    
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse else {
        throw VideoPlayerError.unknownError
      }
      
      switch httpResponse.statusCode {
      case 200...299:
        let config = try JSONDecoder().decode(VideoConfigResponse.self, from: data)
        return config
      case 401:
        throw VideoPlayerError.unauthorized
      case 404:
        throw VideoPlayerError.notFound
      case 500:
        throw VideoPlayerError.internalServerError
      default:
        throw VideoPlayerError.unknownError
      }
    } catch let error as VideoPlayerError {
      throw error
    } catch {
      throw VideoPlayerError.unknownError
    }
  }
  
  public func loadVideoThumbnail(libraryId: Int, videoId: String, token: String? = nil, expires: Int? = nil) async throws -> String {
    try await load(libraryId: libraryId, videoId: videoId, token: token, expires: expires).thumbnailUrl
  }
}


extension VideoPlayerConfigLoader {
  enum VideoPlayerError: Error {
    case unauthorized
    case notFound
    case internalServerError
    case unknownError
  }
}
