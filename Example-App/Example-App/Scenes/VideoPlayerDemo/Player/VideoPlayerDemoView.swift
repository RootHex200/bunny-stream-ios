//
//  SwiftUIView.swift
//
//
//  Created by Egzon Arifi on 20/10/2023.
//

import SwiftUI
import BunnyStreamPlayer
import Combine

struct VideoPlayerDemoView: View {
  var dependenciesManager: DependenciesManager
  var videoInfo: VideoResponseInfo
  var deleteVideoCallback: () -> Void
  
  @State private var token: String = ""
  @State private var expires: String = ""
  @State private var cacheKey: String = ""
  @State private var showingTokenSettings = false
  @State private var showingOfflineSettings = false
  
  // Download states
  @State private var isDownloaded = false
  @State private var isDownloading = false
  @State private var downloadProgress: Double = 0.0
  @State private var downloadStatus: DownloadStatus = .notStarted
  @State private var errorMessage: String?
  @State private var cancellables = Set<AnyCancellable>()
  
  init(dependenciesManager: DependenciesManager,
       videoInfo: VideoResponseInfo,
       deleteVideoCallback: @escaping () -> Void) {
    self.dependenciesManager = dependenciesManager
    self.videoInfo = videoInfo
    self.deleteVideoCallback = deleteVideoCallback
  }
  
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        BunnyStreamPlayer.make(
          dependenciesManager: dependenciesManager, 
          videoId: videoInfo.id,
          token: token.isEmpty ? nil : token,
          expires: expires.isEmpty ? nil : Int(expires),
          cacheKey: cacheKey.isEmpty ? nil : cacheKey
        )
          .frame(width: geometry.size.width,
                 height: geometry.size.width < geometry.size.height ? geometry.size.width * (9 / 16) : geometry.size.height)
        
        if geometry.size.width < geometry.size.height {
          videoInformationView()
        }
      }
    }
  }
}

extension VideoPlayerDemoView {
  func videoInformationView() -> some View {
    List {
      Section {
        Text(videoInfo.title ?? "")
          .font(.headline)
        
        HStack(spacing: 12) {
          Image(systemName: "stopwatch.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .foregroundStyle(.gray)
          Text(Double(videoInfo.length).toFormattedTime())
        }
        
        HStack(spacing: 12) {
          Image(systemName: "eye.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .foregroundStyle(.gray)
          Text("\(videoInfo.views) views")
        }
        
        HStack(spacing: 12) {
          Image(systemName: "server.rack")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .foregroundStyle(.gray)
          Text(videoInfo.formattedFileSize)
        }
        
        Button {
          showingTokenSettings = true
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "key")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 20, height: 20)
              .foregroundStyle(.blue)
            Text("Token Settings")
              .foregroundStyle(.blue)
          }
        }
        
        Button {
          showingOfflineSettings = true
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 20, height: 20)
              .foregroundStyle(.green)
            Text("Offline Cache Key")
              .foregroundStyle(.green)
            if !cacheKey.isEmpty {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }
        }
        
        // Download Management Section
        if !cacheKey.isEmpty {
          downloadManagementView
        }
        
        Button {
          deleteVideoCallback()
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "trash")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 20, height: 20)
              .foregroundStyle(.red)
            Text("Delete video")
              .foregroundStyle(.red)
          }
        }
      }
    }
    .ignoresSafeArea()
    .sheet(isPresented: $showingTokenSettings) {
      NavigationStack {
        Form {
          Section {
            TextField("Token", text: $token)
              .autocapitalization(.none)
              .disableAutocorrection(true)
            TextField("Expires", text: $expires)
              .keyboardType(.numberPad)
              .autocapitalization(.none)
              .disableAutocorrection(true)
          } header: {
            Text("Authentication")
          } footer: {
            Text("Enter token and expires for protected videos. Leave empty for public videos.")
          }
          
          Section("Current Settings") {
            if !token.isEmpty || !expires.isEmpty {
              HStack {
                Text("Token:")
                Spacer()
                Text(token.isEmpty ? "Not set" : "Set")
                  .foregroundColor(token.isEmpty ? .secondary : .green)
              }
              HStack {
                Text("Expires:")
                Spacer()
                Text(expires.isEmpty ? "Not set" : expires)
                  .foregroundColor(expires.isEmpty ? .secondary : .green)
              }
            } else {
              Text("Playing as public video")
                .foregroundColor(.secondary)
            }
          }
        }
        .navigationTitle("Token Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
              showingTokenSettings = false
            }
            .bold()
          }
        }
      }
    }
    .sheet(isPresented: $showingOfflineSettings) {
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
            Text("Enter a unique cache key for offline playback. The video will use this key to store and retrieve cached content. Leave empty to stream online only.")
          }
          
          Section("Current Settings") {
            if !cacheKey.isEmpty {
              HStack {
                Text("Cache Key:")
                Spacer()
                Text(cacheKey)
                  .foregroundColor(.green)
                  .font(.system(.caption, design: .monospaced))
              }
              
              if BunnyOfflineManager.shared.isVideoDownloaded(cacheKey: cacheKey) {
                HStack {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                  Text("Video is cached (available offline)")
                    .foregroundColor(.green)
                }
              } else {
                HStack {
                  Image(systemName: "icloud")
                    .foregroundColor(.secondary)
                  Text("Will stream online (not cached yet)")
                    .foregroundColor(.secondary)
                }
              }
            } else {
              HStack {
                Image(systemName: "wifi")
                  .foregroundColor(.secondary)
                Text("Streaming online only")
                  .foregroundColor(.secondary)
              }
            }
          }
          
          Section("Info") {
            Text("When you provide a cache key, the player will:")
              .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .top) {
                Text("•")
                Text("Check if the video is already cached")
              }
              HStack(alignment: .top) {
                Text("•")
                Text("Play from cache if available (offline)")
              }
              HStack(alignment: .top) {
                Text("•")
                Text("Stream online if not cached")
              }
            }
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
        .navigationTitle("Offline Cache Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
              showingOfflineSettings = false
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
  
  // MARK: - Download Management View
  
  @ViewBuilder
  private var downloadManagementView: some View {
    if isDownloaded {
      // Video is downloaded
      Button(role: .destructive) {
        deleteDownload()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "trash")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .foregroundStyle(.red)
          Text("Delete Offline Video")
            .foregroundStyle(.red)
        }
      }
      
      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 20, height: 20)
          .foregroundStyle(.green)
        Text("Available Offline")
          .foregroundStyle(.green)
      }
    } else if isDownloading {
      // Downloading
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Downloading: \(Int(downloadProgress * 100))%")
            .font(.subheadline)
          Spacer()
        }
        
        ProgressView(value: downloadProgress)
          .progressViewStyle(.linear)
        
        HStack(spacing: 16) {
          if downloadStatus == .paused {
            Button {
              resumeDownload()
            } label: {
              Label("Resume", systemImage: "play.fill")
                .font(.caption)
            }
          } else {
            Button {
              pauseDownload()
            } label: {
              Label("Pause", systemImage: "pause.fill")
                .font(.caption)
            }
          }
          
          Button(role: .destructive) {
            cancelDownload()
          } label: {
            Label("Cancel", systemImage: "xmark.circle.fill")
              .font(.caption)
          }
        }
      }
      .padding(.vertical, 4)
    } else {
      // Not downloaded
      Button {
        startDownload()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "arrow.down.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .foregroundStyle(.blue)
          Text("Download for Offline")
            .foregroundStyle(.blue)
        }
      }
      
      if let error = errorMessage {
        Text("Error: \(error)")
          .font(.caption)
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
      videoId: videoInfo.id,
      libraryId: dependenciesManager.libraryId,
      token: token.isEmpty ? nil : token,
      expires: expires.isEmpty ? nil : Int(expires)
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
