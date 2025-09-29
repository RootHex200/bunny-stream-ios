//
//  PublicVideoDemoView.swift
//  Example-App
//
//  Created by Dejan Skledar on 02/04/2025.
//

import SwiftUI
import BunnyStreamPlayer

struct PublicVideoDemoView: View {
  var dependenciesManager: DependenciesManager
  var videoId: String
  var token: String?
  var expires: Int?
  
  init(
    dependenciesManager: DependenciesManager,
    videoId: String,
    token: String? = nil,
    expires: Int? = nil
  ) {
    self.dependenciesManager = dependenciesManager
    self.videoId = videoId
    self.token = token
    self.expires = expires
  }
  
  var body: some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 0) {
        BunnyStreamPlayer.make(dependenciesManager: dependenciesManager, videoId: videoId, token: token, expires: expires)
          .frame(
            width: geometry.size.width,
            height: geometry.size.width < geometry.size.height ? geometry.size.width * (9 / 16) : geometry.size.height
          )
        
        List {
          Section {
            Text("Direct Video Play")
              .font(.headline)
            
            if let token = token, !token.isEmpty {
              HStack {
                Text("Token:")
                  .foregroundColor(.secondary)
                Spacer()
                Text(token)
                  .font(.system(.caption, design: .monospaced))
                  .lineLimit(1)
              }
            }
            
            if let expires = expires {
              HStack {
                Text("Expires:")
                  .foregroundColor(.secondary)
                Spacer()
                Text("\(expires)")
                  .font(.system(.caption, design: .monospaced))
              }
            }
            
            if token == nil && expires == nil {
              Text("Playing as public video")
                .foregroundColor(.secondary)
                .font(.caption)
            }
          }
        }
        .ignoresSafeArea()
      }
    }
  }
}
