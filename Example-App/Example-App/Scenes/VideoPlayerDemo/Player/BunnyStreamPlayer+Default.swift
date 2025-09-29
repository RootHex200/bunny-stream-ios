//
//  BunnyStreamPlayer+Default.swift
//  Example-App
//
//  Created by Egzon Arifi on 17/11/2023.
//

import SwiftUI
import BunnyStreamPlayer

extension BunnyStreamPlayer {
  static func make(dependenciesManager: DependenciesManager, videoId: String, token: String? = nil, expires: Int? = nil) -> BunnyStreamPlayer {
    let playerIcons = PlayerIcons(play: Image(systemName: "play.fill"))
    let accessKey = dependenciesManager.accessKey.isEmpty ? nil : dependenciesManager.accessKey
    
    return BunnyStreamPlayer(
      accessKey: accessKey,
      videoId: videoId,
      libraryId: dependenciesManager.libraryId,
      token: token,
      expires: expires,
      playerIcons: playerIcons
    )
  }
}
