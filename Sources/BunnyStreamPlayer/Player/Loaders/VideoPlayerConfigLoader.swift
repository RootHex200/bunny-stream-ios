import Foundation
import SwiftUI

public struct VideoPlayerConfigLoader {
  public init() {}
  
  func load(libraryId: Int, videoId: String, token: String? = nil, expires: Int? = nil, referer: String? = nil) async throws -> VideoConfigResponse {
    var urlComponents = URLComponents(string: "https://video.bunnycdn.com/library/\(libraryId)/videos/\(videoId)/play")!
    
    // A blank token is not a token, and a blank referer is not a referer.
    // Both arrive that way from bridges that hand through an empty text field.
    let cleanToken = token?.trimmed.nonEmpty
    let cleanExpires = expires.flatMap { $0 > 0 ? $0 : nil }

    // Add token and expires parameters if provided
    var queryItems: [URLQueryItem] = []
    if let cleanToken = cleanToken {
      queryItems.append(URLQueryItem(name: "token", value: cleanToken))
    }
    if let cleanExpires = cleanExpires {
      queryItems.append(URLQueryItem(name: "expires", value: String(cleanExpires)))
    }
    
    if !queryItems.isEmpty {
      urlComponents.queryItems = queryItems
    }
    
    guard let url = urlComponents.url else {
      print("[VideoPlayerConfigLoader] Failed to create URL")
      throw VideoPlayerError.unknownError
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    let refererValue = referer?.trimmed.nonEmpty ?? Constants.defaultReferer
    request.addValue(refererValue, forHTTPHeaderField: "Referer")

    // Log what this request actually presents, not just where it is going. A
    // 401 on a token-authenticated library has exactly two causes — no pair
    // sent, or a pair Bunny will not accept — and the URL alone cannot tell
    // them apart once a reader stops noticing the missing query string.
    let tokenHint = cleanToken.map { "\($0.prefix(8))… (\($0.count) chars)" } ?? "<none>"
    print("[VideoPlayerConfigLoader] Loading from URL: \(url.absoluteString)")
    print("""
      [VideoPlayerConfigLoader] Auth: token=\(tokenHint) \
      expires=\(cleanExpires.map(String.init) ?? "<none>") referer=\(refererValue)
      """)
    
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
      case 401, 403:
        // 403 is what a library with "Block direct URL access" answers when
        // the Referer is not on its allow-list — the same class of problem as
        // a missing token, and worth reporting as such rather than as an
        // unknown failure.
        print("[VideoPlayerConfigLoader] Unauthorized (\(httpResponse.statusCode))")
        print("[VideoPlayerConfigLoader] Response body: \(String(data: data, encoding: .utf8) ?? "<empty>")")
        if cleanToken == nil {
          print("""
            [VideoPlayerConfigLoader] No token was sent. Library \(libraryId) is \
            answering 401, which is what a library with Embed View Token \
            Authentication enabled does for an unsigned /play request — an \
            AccessKey does not substitute for the token. Whoever constructs the \
            player (or calls BunnyOfflineManager.downloadVideo) has to pass a \
            token and the matching expires; empty strings are dropped, which is \
            why the URL above carries no query string.
            """)
        } else if cleanExpires == nil {
          print("""
            [VideoPlayerConfigLoader] A token was sent without expires. The token \
            is SHA256(securityKey + videoId + expires), so Bunny cannot verify it \
            without the same expires it was signed with.
            """)
        } else {
          print("""
            [VideoPlayerConfigLoader] The token pair was rejected. It is signed \
            over (securityKey + videoId + expires), so it fails when any of the \
            three differs from what Bunny expects: expires already elapsed, \
            expires sent in milliseconds, a token minted for a different video, \
            or a different library's security key.
            """)
        }
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


// The loader used to declare its own nested `VideoPlayerError`, which shadowed
// the shared one inside this file. Every failure it threw was therefore a type
// `BunnyStreamPlayer`'s `catch let error as VideoPlayerError` could not match,
// so a 401 surfaced as the generic reload screen instead of the real reason.
