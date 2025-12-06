//
//  ContentView.swift
//  Example-App
//
//  Created by Egzon Arifi on 06/10/2023.
//

import SwiftUI
import BunnyStreamUploader
import BunnyStreamCameraUpload
import BunnyStreamPlayer

struct ContentView: View {
  @EnvironmentObject var dependenciesManager: DependenciesManager
  @State private var isShowingSheet = false
  @State private var tempAccessKey: String = ""
  @State private var libraryId: String = ""
  @State private var isStreamingPresented: Bool = false
  @State private var isShowingVideoIdAlert = false
  @State private var videoId: String = ""
  @State private var token: String = ""
  @State private var expires: String = ""
  @State private var cacheKey: String = ""
  @State private var showPublicVideoPlayer = false
  
  var body: some View {
    NavigationStack {
      List {
        Section("Actions") {
          NavigationLink("Video Player") {
            VideoListView(viewModel: .init(bunnyStreamAPI: dependenciesManager.bunnyStreamAPI))
              .environmentObject(dependenciesManager)
          }
          NavigationLink("Video Uploader") {
            VideoUploaderTypesView()
              .environmentObject(dependenciesManager)
          }
          NavigationLink("Camera Upload") {
            Button {
              isStreamingPresented.toggle()
            } label: {
              Image(systemName: "dot.radiowaves.left.and.right")
              Text("Start uploading")
            }
          }
          Button {
            videoId = ""
            token = ""
            expires = ""
            cacheKey = ""
            isShowingVideoIdAlert = true
          } label: {
            Text("Direct Video Play")
          }
        }
        
        Section("Configuration") {
          configurationView
        }
      }
      .navigationTitle("BunnyStream Demo")
      .sheet(isPresented: $isShowingVideoIdAlert) {
        NavigationStack {
          Form {
            Section("Video Information") {
              TextField("Video ID", text: $videoId)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            }
            
            Section {
              TextField("Token", text: $token)
                .autocapitalization(.none)
                .disableAutocorrection(true)
              TextField("Expires", text: $expires)
                .keyboardType(.numberPad)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            } header: {
              Text("Authentication (Optional)")
            } footer: {
              Text("Leave token and expires empty for public videos. For protected videos, enter the authentication token and expiration timestamp.")
            }
            
            Section {
              TextField("Cache Key", text: $cacheKey)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
              
              if !cacheKey.isEmpty {
                HStack {
                  if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey) {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(.green)
                    Text("Cached (available offline)")
                      .font(.caption)
                      .foregroundColor(.green)
                  } else {
                    Image(systemName: "icloud")
                      .foregroundColor(.secondary)
                    Text("Not cached (will stream online)")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
              }
            } header: {
              Text("Offline Playback (Optional)")
            } footer: {
              Text("Enter a unique cache key to enable offline playback. The player will automatically use cached content if available, otherwise it will stream online. Example: my_video_1")
            }
          }
          .formStyle(.grouped)
          .navigationTitle("Play Video")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
              Button("Play") {
                showPublicVideoPlayer = true
                isShowingVideoIdAlert = false
              }
              .disabled(videoId.isEmpty)
              .bold()
            }
            ToolbarItem(placement: .navigationBarLeading) {
              Button("Cancel") {
                isShowingVideoIdAlert = false
                videoId = ""
                token = ""
                expires = ""
                cacheKey = ""
              }
            }
          }
        }
      }
      .sheet(isPresented: $showPublicVideoPlayer) {
        let expiresInt = Int(expires.isEmpty ? "0" : expires) ?? 0
        PublicVideoDemoView(
          dependenciesManager: dependenciesManager, 
          videoId: videoId,
          token: token.isEmpty ? nil : token,
          expires: expiresInt == 0 ? nil : expiresInt,
          cacheKey: cacheKey
        )
      }

    }
    .fullScreenCover(isPresented: $isStreamingPresented,
                     content: {
      BunnyStreamCameraUploadView(
        accessKey: dependenciesManager.accessKey,
        libraryId: dependenciesManager.libraryId
      )
    })
    .onAppear {
      tempAccessKey = dependenciesManager.accessKey
      libraryId = String(dependenciesManager.libraryId)
    }
  }
}

private extension ContentView {
  var configurationView: some View {
    Button("BunnyStream Configuration") {
      isShowingSheet = true
    }
    .sheet(isPresented: $isShowingSheet) {
      NavigationStack {
        Form {
          Section("Video Library ID") {
            TextField("Enter your Library ID", text: $libraryId)
              .keyboardType(.numberPad)
              .autocapitalization(.none)
              .disableAutocorrection(true)
          }
          Section("Video Library API Key") {
            TextField("Enter your Library API Key", text: $tempAccessKey)
              .autocapitalization(.none)
              .disableAutocorrection(true)
            
          }
        }
        .formStyle(.grouped)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Save") {
              saveConfig()
            }
            .bold()
          }
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
              isShowingSheet = false
            }
          }
        }
      }
    }
  }

  private func saveConfig() {
    dependenciesManager.storedAccessKey = tempAccessKey
    dependenciesManager.libraryId = Int(libraryId) ?? .zero
    isShowingSheet = false
  }
}
