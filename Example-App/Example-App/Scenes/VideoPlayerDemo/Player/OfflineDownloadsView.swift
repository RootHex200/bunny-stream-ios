//
//  OfflineDownloadsView.swift
//  Example-App
//
//  Mirrors the Android demo's Downloads screen so the offline path can be
//  exercised on both platforms the same way.
//

import SwiftUI
import BunnyStreamPlayer
import Combine

/// Start, watch, and play back downloads without going through a player first.
///
/// Deliberately talks to `BunnyOfflineManager` directly rather than through
/// `BunnyStreamPlayer`: that is the same entry point the Flutter plugin uses,
/// so whatever is verified here is what the plugin gets.
struct OfflineDownloadsView: View {
  @EnvironmentObject var dependenciesManager: DependenciesManager

  @State private var videoId: String = ""
  @State private var cacheKey: String = ""
  @State private var token: String = ""
  @State private var expires: String = ""
  @State private var wifiOnly: Bool = false

  @State private var progressByKey: [String: DownloadProgress] = [:]
  @State private var downloaded: [OfflineVideo] = []
  @State private var message: String?
  @State private var playing: OfflineVideo?

  @State private var cancellables = Set<AnyCancellable>()

  var body: some View {
    List {
      startSection
      inProgressSection
      downloadedSection
      howToTestSection
    }
    .navigationTitle("Offline Downloads")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Refresh") { refresh() }
      }
    }
    .onAppear {
      refresh()
      subscribe()
    }
    .fullScreenCover(item: $playing) { video in
      NavigationStack {
        PublicVideoDemoView(
          dependenciesManager: dependenciesManager,
          videoId: video.videoId,
          cacheKey: video.cacheKey
        )
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") { playing = nil }
          }
        }
      }
    }
  }

  // MARK: - Sections

  private var startSection: some View {
    Section {
      TextField("Video ID", text: $videoId)
        .autocapitalization(.none)
        .disableAutocorrection(true)
      TextField("Cache Key (defaults to Video ID)", text: $cacheKey)
        .autocapitalization(.none)
        .disableAutocorrection(true)
      TextField("Token (optional)", text: $token)
        .autocapitalization(.none)
        .disableAutocorrection(true)
      TextField("Expires (optional)", text: $expires)
        .keyboardType(.numberPad)
      Toggle("Wi-Fi only", isOn: $wifiOnly)

      Button("Start download") { startDownload() }
        .disabled(videoId.trimmingCharacters(in: .whitespaces).isEmpty)

      if let message {
        Text(message)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    } header: {
      Text("Download")
    } footer: {
      Text("Library ID \(dependenciesManager.libraryId) — change it in BunnyStream Configuration.")
    }
  }

  @ViewBuilder
  private var inProgressSection: some View {
    let active = progressByKey.values
      .filter { $0.status == .downloading || $0.status == .paused || $0.status == .notStarted }
      .sorted { $0.cacheKey < $1.cacheKey }

    if !active.isEmpty {
      Section("In progress") {
        ForEach(active, id: \.cacheKey) { progress in
          VStack(alignment: .leading, spacing: 6) {
            Text(progress.cacheKey)
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)

            // A negative value means the total is not known yet; an
            // indeterminate bar is honest about that, a 0% bar is not.
            if progress.progress < 0 {
              ProgressView()
            } else {
              ProgressView(value: min(max(progress.progress, 0), 1))
              Text("\(Int(progress.progress * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            // Same reason as the Downloaded rows: without this, tapping the
            // progress bar anywhere in the row would cancel the download.
            Button(role: .destructive) {
              BunnyOfflineManager.shared.cancelDownload(cacheKey: progress.cacheKey)
              progressByKey.removeValue(forKey: progress.cacheKey)
            } label: {
              Label("Cancel", systemImage: "xmark.circle")
                .font(.caption2)
            }
            .buttonStyle(.borderless)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }

  @ViewBuilder
  private var downloadedSection: some View {
    Section {
      if downloaded.isEmpty {
        Text("Nothing downloaded yet")
          .foregroundColor(.secondary)
          .font(.caption)
      } else {
        ForEach(downloaded, id: \.cacheKey) { video in
          VStack(alignment: .leading, spacing: 6) {
            Text(video.cacheKey)
              .font(.system(.caption, design: .monospaced))
              .lineLimit(1)
            Text(sizeText(video.fileSize))
              .font(.caption2)
              .foregroundColor(.secondary)

            // `.borderless` on every button is load-bearing, not cosmetic.
            // A List row makes its whole area one tap target, so without an
            // explicit style a tap on "Play offline" fires "Delete" as well —
            // which silently wiped the download a moment before the player
            // opened, and made offline playback look broken.
            HStack(spacing: 16) {
              Button {
                playing = video
              } label: {
                Label("Play offline", systemImage: "play.circle")
                  .font(.caption2)
              }
              .buttonStyle(.borderless)

              Button(role: .destructive) {
                BunnyOfflineManager.shared.deleteVideo(cacheKey: video.cacheKey)
                refresh()
              } label: {
                Label("Delete", systemImage: "trash")
                  .font(.caption2)
              }
              .buttonStyle(.borderless)
            }
          }
          .padding(.vertical, 2)
        }

        Button(role: .destructive) {
          BunnyOfflineManager.shared.clearAllDownloads()
          refresh()
        } label: {
          Text("Delete all")
        }
      }
    } header: {
      Text("Downloaded (\(downloaded.count))")
    } footer: {
      if !downloaded.isEmpty {
        Text("Total \(sizeText(BunnyOfflineManager.shared.getTotalCacheSize()))")
      }
    }
  }

  private var howToTestSection: some View {
    Section("How to verify offline") {
      VStack(alignment: .leading, spacing: 6) {
        Text("1. Start a download and wait for it to appear under Downloaded.")
        Text("2. Turn the network off — Airplane Mode on a device, or the Mac's Wi-Fi for the simulator.")
        Text("3. Tap Play offline. It plays with no network, and the log shows no [VideoPlayerConfigLoader] request.")
        Text("4. Force-quit and relaunch while still offline, then play again — this proves the saved location survived.")
      }
      .font(.caption2)
      .foregroundColor(.secondary)
    }
  }

  // MARK: - Actions

  private func startDownload() {
    let video = videoId.trimmingCharacters(in: .whitespaces)
    let key = cacheKey.trimmingCharacters(in: .whitespaces).isEmpty
      ? video
      : cacheKey.trimmingCharacters(in: .whitespaces)

    message = nil

    BunnyOfflineManager.shared.downloadVideo(
      cacheKey: key,
      videoId: video,
      libraryId: dependenciesManager.libraryId,
      token: token.isEmpty ? nil : token,
      expires: Int(expires),
      title: key,
      wifiOnly: wifiOnly
    ) { accepted, error in
      if accepted {
        message = "Queued \(key)"
      } else {
        // A refusal is usually "already downloaded" or "already running",
        // which is not an error worth alarming anyone about.
        message = error?.localizedDescription ?? "Refused — already downloaded or in progress"
        refresh()
      }
    }
  }

  private func refresh() {
    downloaded = BunnyOfflineManager.shared
      .getAllDownloadedVideos()
      .sorted { $0.downloadDate > $1.downloadDate }
  }

  private func subscribe() {
    guard cancellables.isEmpty else { return }

    BunnyOfflineManager.shared.downloadProgressPublisher
      .receive(on: DispatchQueue.main)
      .sink { progress in
        switch progress.status {
        case .completed:
          progressByKey.removeValue(forKey: progress.cacheKey)
          refresh()
        case .cancelled:
          progressByKey.removeValue(forKey: progress.cacheKey)
        case .failed:
          progressByKey.removeValue(forKey: progress.cacheKey)
          message = "Failed \(progress.cacheKey): "
            + (progress.error?.localizedDescription ?? "unknown error")
        default:
          progressByKey[progress.cacheKey] = progress
        }
      }
      .store(in: &cancellables)
  }

  private func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

extension OfflineVideo: Identifiable {
  public var id: String { cacheKey }
}
