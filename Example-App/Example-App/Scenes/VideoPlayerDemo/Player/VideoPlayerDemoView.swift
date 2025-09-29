//
//  SwiftUIView.swift
//
//
//  Created by Egzon Arifi on 20/10/2023.
//

import SwiftUI
import BunnyStreamPlayer

struct VideoPlayerDemoView: View {
  var dependenciesManager: DependenciesManager
  var videoInfo: VideoResponseInfo
  var deleteVideoCallback: () -> Void
  
  @State private var token: String = ""
  @State private var expires: String = ""
  @State private var showingTokenSettings = false
  
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
          expires: expires.isEmpty ? nil : Int(expires)
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
  }
}
