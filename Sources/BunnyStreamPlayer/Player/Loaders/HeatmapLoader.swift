import Foundation
import BunnyStreamAPI

struct HeatmapLoader {
  let bunnyStreamAPI: BunnyStreamAPI

  init(bunnyStreamAPI: BunnyStreamAPI) {
    self.bunnyStreamAPI = bunnyStreamAPI
  }
  
  func loadHeatmap(videoId: String, libraryId: Int) async throws -> Heatmap {
    do {
      let heatmapData = try await bunnyStreamAPI.getVideoHeatmap(
        libraryId: libraryId,
        videoId: videoId
      )
      
      var convertedDict = [Int: Int]()
      for (key, value) in heatmapData {
        if let intKey = Int(key) {
          convertedDict[intKey] = value
        }
      }
      
      return Heatmap(data: convertedDict)
    } catch BunnyStreamAPIError.notFound {
      throw HeatmapLoaderError.notFound
    } catch {
      throw HeatmapLoaderError.loadError
    }
  }
}

extension HeatmapLoader {
  enum HeatmapLoaderError: Error {
    case notFound
    case loadError
  }
}
