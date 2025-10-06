import Foundation

/// A simplified client SDK for interacting with the Bunny Stream API.
///
/// The `BunnyStreamAPI` class provides a convenient interface for accessing Bunny Stream's
/// content delivery and streaming services. It handles authentication, request management,
/// and provides access to common API endpoints without OpenAPI generator dependency.
///
/// Example usage:
/// ```swift
/// let api = BunnyStreamAPI(accessKey: "your-access-key")
/// let videoId = try await api.createVideo(libraryId: 12345, title: "My Video")
/// ```
///
/// - Important: Make sure to keep your access key secure and never expose it in client-side code.
public class BunnyStreamAPI {
  /// The authentication key used for accessing the Bunny Stream API.
  private let accessKey: String

  /// The base URL for the Bunny Stream API.
  private let baseURL = "https://video.bunnycdn.com"
  
  /// The URLSession used for network requests.
  private let urlSession: URLSession
  
  /// The referer value for API calls. If `nil`, uses default "https://iframe.mediadelivery.net/".
  private let referer: String?

  /// Creates a new instance of the Bunny Stream SDK.
  ///
  /// - Parameters:
  ///   - accessKey: The API access key for authentication. This can be found in your Bunny Stream dashboard.
  ///   - urlSession: An optional custom URLSession for network communications. Defaults to `.shared`.
  ///   - referer: The referer value for API calls. If `nil`, uses default "https://iframe.mediadelivery.net/".
  public init(accessKey: String, urlSession: URLSession = .shared, referer: String? = nil) {
    self.accessKey = accessKey
    self.urlSession = urlSession
    self.referer = referer
  }
  
  /// Creates a new video entry in the specified library.
  ///
  /// - Parameters:
  ///   - libraryId: The ID of the video library where the video will be created.
  ///   - title: The title of the new video.
  ///   - collectionId: Optional collection ID where the video will be placed.
  ///   - thumbnailTime: Optional video time in milliseconds used to extract the main video thumbnail.
  /// - Returns: The GUID of the created video.
  /// - Throws: `BunnyStreamAPIError` if the request fails.
  public func createVideo(libraryId: Int, title: String, collectionId: String? = nil, thumbnailTime: Int? = nil) async throws -> String {
    let url = URL(string: "\(baseURL)/library/\(libraryId)/videos")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    let refererValue = referer ?? "https://iframe.mediadelivery.net/"
    request.addValue(refererValue, forHTTPHeaderField: "Referer")
    request.addValue(accessKey, forHTTPHeaderField: "AccessKey")
    
    let requestBody = CreateVideoRequest(
      title: title,
      collectionId: collectionId,
      thumbnailTime: thumbnailTime
    )
    
    request.httpBody = try JSONEncoder().encode(requestBody)
    
    let (data, response) = try await urlSession.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200:
      let videoResponse = try JSONDecoder().decode(VideoResponse.self, from: data)
      guard let guid = videoResponse.guid else {
        throw BunnyStreamAPIError.missingVideoId
      }
      return guid
    case 401:
      throw BunnyStreamAPIError.unauthorized
    case 500:
      throw BunnyStreamAPIError.internalServerError
    default:
      throw BunnyStreamAPIError.httpError(httpResponse.statusCode)
    }
  }
  
  /// Deletes the specified video permanently from the video library.
  ///
  /// - Parameters:
  ///   - libraryId: The ID of the video library.
  ///   - videoId: The unique identifier of the video to be deleted.
  /// - Throws: `BunnyStreamAPIError` if the request fails.
  public func deleteVideo(libraryId: Int, videoId: String) async throws {
    let url = URL(string: "\(baseURL)/library/\(libraryId)/videos/\(videoId)")!
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    let refererValue = referer ?? "https://iframe.mediadelivery.net/"
    request.addValue(refererValue, forHTTPHeaderField: "Referer")
    request.addValue(accessKey, forHTTPHeaderField: "AccessKey")
    
    let (_, response) = try await urlSession.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200:
      return
    case 401:
      throw BunnyStreamAPIError.unauthorized
    case 404:
      throw BunnyStreamAPIError.notFound
    case 500:
      throw BunnyStreamAPIError.internalServerError
    default:
      throw BunnyStreamAPIError.httpError(httpResponse.statusCode)
    }
  }
  
  /// Retrieves the heatmap data for the specified video.
  ///
  /// - Parameters:
  ///   - libraryId: The ID of the video library.
  ///   - videoId: The unique identifier of the video.
  /// - Returns: A dictionary where keys are time segments and values are watch percentages.
  /// - Throws: `BunnyStreamAPIError` if the request fails.
  public func getVideoHeatmap(libraryId: Int, videoId: String) async throws -> [String: Int] {
    let url = URL(string: "\(baseURL)/library/\(libraryId)/videos/\(videoId)/heatmap")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let refererValue = referer ?? "https://iframe.mediadelivery.net/"
    request.addValue(refererValue, forHTTPHeaderField: "Referer")
    request.addValue(accessKey, forHTTPHeaderField: "AccessKey")
    
    let (data, response) = try await urlSession.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200:
      let heatmapResponse = try JSONDecoder().decode(HeatmapResponse.self, from: data)
      return heatmapResponse.heatmap ?? [:]
    case 401:
      throw BunnyStreamAPIError.unauthorized
    case 404:
      throw BunnyStreamAPIError.notFound
    case 500:
      throw BunnyStreamAPIError.internalServerError
    default:
      throw BunnyStreamAPIError.httpError(httpResponse.statusCode)
    }
  }
  
  /// Retrieves playback data for the specified video including video URLs, captions path, and player settings.
  ///
  /// - Parameters:
  ///   - libraryId: The ID of the video library.
  ///   - videoId: The unique identifier of the video.
  ///   - token: Optional authentication token for accessing the video playback data.
  ///   - expires: Optional expiration timestamp for the provided token.
  /// - Returns: A dictionary containing the video playback configuration.
  /// - Throws: `BunnyStreamAPIError` if the request fails.
  public func getVideoPlayData(libraryId: Int, videoId: String, token: String? = nil, expires: Int? = nil) async throws -> [String: Any] {
    var urlComponents = URLComponents(string: "\(baseURL)/library/\(libraryId)/videos/\(videoId)/play")!
    
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
      throw BunnyStreamAPIError.invalidResponse
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")
    let refererValue = referer ?? "https://iframe.mediadelivery.net/"
    request.addValue(refererValue, forHTTPHeaderField: "Referer")
    request.addValue(accessKey, forHTTPHeaderField: "AccessKey")
    
    let (data, response) = try await urlSession.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200:
      let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
      guard let dictionary = jsonObject as? [String: Any] else {
        throw BunnyStreamAPIError.decodingError
      }
      return dictionary
    case 401:
      throw BunnyStreamAPIError.unauthorized
    case 404:
      throw BunnyStreamAPIError.notFound
    case 500:
      throw BunnyStreamAPIError.internalServerError
    default:
      throw BunnyStreamAPIError.httpError(httpResponse.statusCode)
    }
  }
  
  /// Retrieves a paginated list of videos from the specified video library.
  ///
  /// - Parameters:
  ///   - libraryId: The ID of the video library.
  ///   - page: The page number to retrieve (defaults to 1).
  ///   - itemsPerPage: The number of videos per page (defaults to 100).
  ///   - search: Optional search term to filter videos by title or metadata.
  ///   - collection: Optional collection ID to filter videos by.
  ///   - orderBy: Optional field by which to order the video list (defaults to "date").
  /// - Returns: A `VideoListResponse` containing the paginated list of videos.
  /// - Throws: `BunnyStreamAPIError` if the request fails.
  public func listVideos(libraryId: Int, page: Int = 1, itemsPerPage: Int = 100, search: String? = nil, collection: String? = nil, orderBy: String? = nil) async throws -> VideoListResponse {
    var urlComponents = URLComponents(string: "\(baseURL)/library/\(libraryId)/videos")!
    
    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "itemsPerPage", value: String(itemsPerPage))
    ]
    
    if let search = search, !search.isEmpty {
      queryItems.append(URLQueryItem(name: "search", value: search))
    }
    
    if let collection = collection, !collection.isEmpty {
      queryItems.append(URLQueryItem(name: "collection", value: collection))
    }
    
    if let orderBy = orderBy, !orderBy.isEmpty {
      queryItems.append(URLQueryItem(name: "orderBy", value: orderBy))
    }
    
    urlComponents.queryItems = queryItems
    
    guard let url = urlComponents.url else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue(accessKey, forHTTPHeaderField: "AccessKey")
    
    let (data, response) = try await urlSession.data(for: request)
    
    guard let httpResponse = response as? HTTPURLResponse else {
      throw BunnyStreamAPIError.invalidResponse
    }
    
    switch httpResponse.statusCode {
    case 200:
      let videoListResponse = try JSONDecoder().decode(VideoListResponse.self, from: data)
      return videoListResponse
    case 401:
      throw BunnyStreamAPIError.unauthorized
    case 500:
      throw BunnyStreamAPIError.internalServerError
    default:
      throw BunnyStreamAPIError.httpError(httpResponse.statusCode)
    }
  }
}

// MARK: - Request/Response Models

private struct CreateVideoRequest: Codable {
  let title: String
  let collectionId: String?
  let thumbnailTime: Int?
}

// Note: VideoResponse is now defined as a public struct in the public section

private struct HeatmapResponse: Codable {
  let heatmap: [String: Int]?
}

public struct VideoListResponse: Codable {
  public let totalItems: Int?
  public let currentPage: Int?
  public let itemsPerPage: Int?
  public let items: [VideoResponse]?
}

public struct VideoResponse: Codable {
  public let videoLibraryId: Int?
  public let guid: String?
  public let title: String?
  public let dateUploaded: String?
  public let views: Int?
  public let isPublic: Bool?
  public let length: Int?
  public let status: Int?
  public let framerate: Double?
  public let width: Int?
  public let height: Int?
  public let availableResolutions: String?
  public let outputCodecs: String?
  public let thumbnailCount: Int?
  public let encodeProgress: Int?
  public let storageSize: Int?
  public let captions: [CaptionResponse]?
  public let hasMP4Fallback: Bool?
  public let collectionId: String?
  public let thumbnailFileName: String?
  public let averageWatchTime: Int?
  public let totalWatchTime: Int?
  public let category: String?
}

public struct CaptionResponse: Codable {
  public let srclang: String?
  public let label: String?
}

// MARK: - Error Types

/// Errors that can occur when using the Bunny Stream API.
public enum BunnyStreamAPIError: Error, LocalizedError {
  case invalidResponse
  case unauthorized
  case notFound
  case internalServerError
  case httpError(Int)
  case missingVideoId
  case encodingError
  case decodingError
  
  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Invalid response from server"
    case .unauthorized:
      return "Request authorization failed"
    case .notFound:
      return "Requested resource was not found"
    case .internalServerError:
      return "Internal server error"
    case .httpError(let code):
      return "HTTP error with status code: \(code)"
    case .missingVideoId:
      return "Video ID is missing from response"
    case .encodingError:
      return "Failed to encode request data"
    case .decodingError:
      return "Failed to decode response data"
    }
  }
}
