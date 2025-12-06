//
//  PublicVideoDemoView.swift
//  Example-App
//
//  Created by Dejan Skledar on 02/04/2025.
//

import SwiftUI
import BunnyStreamPlayer
import Combine

struct PublicVideoDemoView: View {
  var dependenciesManager: DependenciesManager
  var videoId: String
  var token: String?
  var expires: Int?
  
  @State private var cacheKey: String
  @State private var showingCacheSettings = false
  
  // Download states
  @State private var isDownloaded = false
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0.0
  @State private var downloadStatus: DownloadStatus = .notStarted
  @State private var errorMessage: String?
  @State private var cancellables = Set<AnyCancellable>()
  
  init(
    dependenciesManager: DependenciesManager,
    videoId: String,
    token: String? = nil,
    expires: Int? = nil,
    cacheKey: String = ""
  ) {
    self.dependenciesManager = dependenciesManager
    self.videoId = videoId
    self.token = token
    self.expires = expires
    self._cacheKey = State(initialValue: cacheKey)
  }
  
  var body: some View {
    GeometryReader { geometry in
      VStack(alignment: .leading, spacing: 0) {
        BunnyStreamPlayer.make(
          dependenciesManager: dependenciesManager,
          videoId: videoId,
          token: token,
          expires: expires,
          cacheKey: cacheKey.isEmpty ? nil : cacheKey
        )
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
            
            Button {
              showingCacheSettings = true
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                  .foregroundColor(.green)
                Text("Offline Cache Key")
                  .foregroundColor(.primary)
                Spacer()
                if !cacheKey.isEmpty {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                } else {
                  Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
              }
            }
            
            if !cacheKey.isEmpty {
              HStack {
                Text("Cache Key:")
                  .foregroundColor(.secondary)
                Spacer()
                Text(cacheKey)
                  .font(.system(.caption, design: .monospaced))
                  .foregroundColor(.green)
              }
              
              if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey) {
                HStack {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                  Text("Available offline")
                    .font(.caption)
                    .foregroundColor(.green)
                }
              }
              
              // Download Management
              downloadManagementView
            }
          }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingCacheSettings) {
          NavigationStack {
            Form {
              Section {
                TextField("Cache Key", text: $cacheKey)
                  .autocapitalization(.none)
                  .disableAutocorrection(true)
                  .textInputAutocapitalization(.never)
              } header: {
                Text("Offline Playback")
              } footer: {
                Text("Enter a unique cache key for offline playback. Example: video_\(videoId)")
              }
              
              Section("Status") {
                if !cacheKey.isEmpty {
                  HStack {
                    Text("Cache Key:")
                    Spacer()
                    Text(cacheKey)
                      .foregroundColor(.green)
                      .font(.system(.caption, design: .monospaced))
                  }
                  
                  if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey) {
                    Label("Video cached (offline ready)", systemImage: "checkmark.circle.fill")
                      .foregroundColor(.green)
                  } else {
                    Label("Will stream online", systemImage: "icloud")
                      .foregroundColor(.secondary)
                  }
                } else {
                  Label("Streaming online only", systemImage: "wifi")
                    .foregroundColor(.secondary)
                }
              }
              
              Section("How It Works") {
                VStack(alignment: .leading, spacing: 8) {
                  Text("The player will:")
                    .font(.caption)
                    .fontWeight(.semibold)
                  
                  HStack(alignment: .top) {
                    Text("1.")
                      .fontWeight(.semibold)
                    Text("Check if video is cached with this key")
                  }
                  .font(.caption)
                  
                  HStack(alignment: .top) {
                    Text("2.")
                      .fontWeight(.semibold)
                    Text("Play from cache if available (offline)")
                  }
                  .font(.caption)
                  
                  HStack(alignment: .top) {
                    Text("3.")
                      .fontWeight(.semibold)
                    Text("Stream online if not cached")
                  }
                  .font(.caption)
                }
                .foregroundColor(.secondary)
              }
            }
            .navigationTitle("Cache Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                  showingCacheSettings = false
                  checkDownloadStatus()
                }
                .bold()
              }
            }
          }
        }
        .onAppear {
          checkDownloadStatus()
          subscribeToDownloadProgress()
        }
      }
    }
  }
  
  // MARK: - Download Management View
  
  @ViewBuilder
  private var downloadManagementView: some View {
    if isDownloaded {
      // Video is downloaded
      Button(role: .destructive) {
        deleteDownload()
      } label: {
        HStack {
          Image(systemName: "trash")
            .foregroundColor(.red)
          Text("Delete Offline Video")
            .foregroundColor(.red)
        }
      }
      
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text("Downloaded")
          .font(.caption)
          .foregroundColor(.green)
      }
    } else if isDownloading {
      // Downloading
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Downloading: \(Int(downloadProgress * 100))%")
            .font(.caption)
          Spacer()
        }
        
        ProgressView(value: downloadProgress)
          .progressViewStyle(.linear)
        
        HStack(spacing: 12) {
          if downloadStatus == .paused {
            Button {
              resumeDownload()
            } label: {
              Label("Resume", systemImage: "play.fill")
                .font(.caption2)
            }
          } else {
            Button {
              pauseDownload()
            } label: {
              Label("Pause", systemImage: "pause.fill")
                .font(.caption2)
            }
          }
          
          Button(role: .destructive) {
            cancelDownload()
          } label: {
            Label("Cancel", systemImage: "xmark.circle")
              .font(.caption2)
          }
        }
      }
    } else {
      // Not downloaded
      Button {
        startDownload()
      } label: {
        HStack {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundColor(.blue)
          Text("Download for Offline")
            .foregroundColor(.blue)
        }
      }
      
      if let error = errorMessage {
        Text("Error: \(error)")
          .font(.caption2)
          .foregroundColor(.red)
      }
    }
  }
  
  // MARK: - Download Functions
  
  private func checkDownloadStatus() {
    guard !cacheKey.isEmpty else { return }
    isDownloaded = BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey)
  }
  
  private func subscribeToDownloadProgress() {
    BunnyOfflineManager.shared.downloadProgressPublisher
      .receive(on: DispatchQueue.main)
      .sink { [self] progress in
        guard progress.cacheKey == cacheKey else { return }
        downloadProgress = progress.progress
        downloadStatus = progress.status
        isDownloading = progress.status == .downloading || progress.status == .paused
        
        if progress.status == .completed {
          isDownloaded = true
          isDownloading = false
        } else if progress.status == .failed {
          isDownloading = false
          errorMessage = progress.error?.localizedDescription ?? "Download failed"
        } else if progress.status == .cancelled {
          isDownloading = false
          downloadProgress = 0.0
        }
      }
      .store(in: &cancellables)
  }
  
  private func startDownload() {
    guard !cacheKey.isEmpty else { return }
    
    errorMessage = nil
    isDownloading = true
    
    BunnyOfflineManager.shared.downloadVideo(
      cacheKey: cacheKey,
      videoId: videoId,
      libraryId: dependenciesManager.libraryId,
      token: token,
      expires: expires
    ) { success, error in
      if !success {
        errorMessage = error?.localizedDescription ?? "Failed to start download"
        isDownloading = false
      }
    }
  }
  
  private func pauseDownload() {
    BunnyOfflineManager.shared.pauseDownload(cacheKey: cacheKey)
  }
  
  private func resumeDownload() {
    BunnyOfflineManager.shared.resumeDownload(cacheKey: cacheKey)
  }
  
  private func cancelDownload() {
    BunnyOfflineManager.shared.cancelDownload(cacheKey: cacheKey)
  }
  
  private func deleteDownload() {
    BunnyOfflineManager.shared.deleteVideo(cacheKey: cacheKey)
    isDownloaded = false
    checkDownloadStatus()
  }
}
