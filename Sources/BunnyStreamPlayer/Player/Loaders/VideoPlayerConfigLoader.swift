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
      print("[VideoPlayerConfigLoader] Failed to create URL")
      throw VideoPlayerError.unknownError
    }
    
    print("[VideoPlayerConfigLoader] Loading from URL: \(url.absoluteString)")
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    request.addValue("https://iframe.mediadelivery.net/", forHTTPHeaderField: "Referer")
    
    do {
      print("[VideoPlayerConfigLoader] Making network request...")
      let (data, response) = try await URLSession.shared.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse else {
        print("[VideoPlayerConfigLoader] Invalid response type")
        throw VideoPlayerError.unknownError
      }
      
      print("[VideoPlayerConfigLoader] HTTP Status: \(httpResponse.statusCode)")
      
      switch httpResponse.statusCode {
      case 200...299:
        print("[VideoPlayerConfigLoader] Success response, decoding JSON...")
        do {
          let config = try JSONDecoder().decode(VideoConfigResponse.self, from: data)
          print("[VideoPlayerConfigLoader] JSON decoded successfully")
          print("[VideoPlayerConfigLoader] Video playlist URL: \(config.videoPlaylistUrl)")
          print("[VideoPlayerConfigLoader] Video GUID: \(config.video.guid)")
          print("[VideoPlayerConfigLoader] Video dimensions: \(config.video.width)x\(config.video.height)")
          print("[VideoPlayerConfigLoader] Video length: \(config.video.length) seconds")
          print("[VideoPlayerConfigLoader] Available controls: \(config.controls.controlList.map { $0.rawValue })")
          return config
        } catch {
          print("[VideoPlayerConfigLoader] JSON decode error: \(error)")
          if let jsonString = String(data: data, encoding: .utf8) {
            print("[VideoPlayerConfigLoader] Response JSON: \(jsonString)")
          }
          throw VideoPlayerError.unknownError
        }
      case 401:
        print("[VideoPlayerConfigLoader] Unauthorized (401)")
        throw VideoPlayerError.unauthorized
      case 404:
        print("[VideoPlayerConfigLoader] Not found (404)")
        throw VideoPlayerError.notFound
      case 500:
        print("[VideoPlayerConfigLoader] Internal server error (500)")
        throw VideoPlayerError.internalServerError
      default:
        print("[VideoPlayerConfigLoader] Unexpected status code: \(httpResponse.statusCode)")
        if let responseData = String(data: data, encoding: .utf8) {
          print("[VideoPlayerConfigLoader] Response body: \(responseData)")
        }
        throw VideoPlayerError.unknownError
      }
    } catch let error as VideoPlayerError {
      throw error
    } catch {
      print("[VideoPlayerConfigLoader] Network error: \(error)")
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
