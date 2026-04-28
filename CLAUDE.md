# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository

Swift Package Manager package (`Package.swift`, swift-tools-version 5.9) wrapping Bunny.net's Stream service for iOS 15+/macOS 13+. Fork of `BunnyWay/bunny-stream-ios`; the active branch (`remove-openapi`) has replaced the previous OpenAPI-generated client in `BunnyStreamAPI` with a hand-written `URLSession`-based client — keep that intact when editing API code (don't reintroduce OpenAPI generator dependencies or generated types).

## Common commands

CI (`.github/workflows/BuildAndTest.yml`) drives the canonical build via Xcode against the `Bunny-Package` scheme — mirror that locally:

```bash
# Build
xcodebuild build-for-testing -destination 'name=iPhone 14 Pro' -scheme 'Bunny-Package' | xcpretty

# All tests
xcodebuild test-without-building -destination 'name=iPhone 14 Pro' -scheme 'Bunny-Package' | xcpretty

# Single test (class or method)
xcodebuild test -destination 'name=iPhone 14 Pro' -scheme 'Bunny-Package' \
  -only-testing:BunnyStreamUploaderTests/VideoSHA256SignerTests | xcpretty

# Pure-SPM build (faster, no simulator) — useful for non-iOS-only targets
swift build
swift package clean
```

Docs under `Documentation/Reference/` are SourceDocs output post-processed by `./fix_readme.sh` (run from repo root); only re-run when regenerating reference docs.

## Architecture

Four products, layered. Anything but `BunnyStreamAPI` depends on it; do not let lower layers acquire upward dependencies.

- **`BunnyStreamAPI`** (`Sources/BunnyStreamAPI/BunnyStreamAPI.swift`) — single-file `URLSession` client against `https://video.bunnycdn.com`. Every request must set `AccessKey` + `Referer` headers; `Referer` defaults to `https://iframe.mediadelivery.net/` when caller passes `nil`. Status-code switch maps to `BunnyStreamAPIError` cases — preserve that mapping when adding endpoints. Models (`VideoResponse`, `VideoListResponse`, `CaptionResponse`) are the public shape; private request structs stay file-private.
- **`BunnyStreamUploader`** — TUS-protocol resumable uploads. Two parallel implementations under `VideoUploader/`: `TUS/TUSVideoUploader.swift` (TUSKit-backed, the documented path via `TUSVideoUploader.make(...)`) and `URLSession/URLSessionVideoUploader.swift` (background `URLSession` flow). Both implement the `VideoUploader` / `VideoUploaderActions` protocols in `Protocols/`. `Helpers/VideoSHA256Signer.swift` + `VideoRequestHeaderBuilder.swift` produce the auth headers Bunny's TUS endpoint requires — the only files with meaningful unit tests.
- **`BunnyStreamPlayer`** — SwiftUI `BunnyStreamPlayer` view → `VideoPlayerViewModel` → `MediaPlayer` (AVPlayer wrapper in `Utilities/MediaPlayer/`). `Player/Loaders/VideoPlayerConfigLoader` calls `BunnyStreamAPI.getVideoPlayData` to resolve playlist URL + theme; FairPlay DRM wired through `MediaPlayer/FairPlay/`. Kingfisher's `httpAdditionalHeaders` are mutated globally at module init and again per-instance to inject `Referer` (CDN bypass) — be careful editing `configureGlobalKingfisherHeaders` / `configureKingfisherHeaders`; both must stay in sync.
- **`BunnyStreamCameraUpload`** — RTMP livestream + camera capture via HaishinKit, surface is `BunnyStreamCameraUploadView` in `LiveStream/`.

### Offline playback (recent addition, branch-specific)

Offline support is wired through three files; treat as one subsystem:

- `Model/BunnyOfflineManager.swift` — public façade (`BunnyOfflineManager.shared.downloadVideo(...)`, progress/completion notifications).
- `Utilities/Cache/VideoCacheManager.swift` — disk cache + download orchestration keyed by a caller-supplied `cacheKey` (not the videoId — frontend owns the namespace).
- `Player/BunnyStreamPlayer.swift` — when constructed with `cacheKey:`, `loadFromCache` short-circuits the network path and builds a `Video` from `OfflineVideo` metadata, then plays via `MediaPlayer.makeOffline(url:)`.

When changing offline behavior, keep the `cacheKey` contract intact across all three files — `videoId` and `cacheKey` are deliberately distinct.

## Testing notes

`Tests/BunnyStreamPlayerTests/` exists but is empty; player changes are validated through the Example-App, not unit tests. Real test coverage lives in `Tests/BunnyStreamUploaderTests/Helpers/` (signing/headers) and `Tests/BunnyStreamAPITests/AuthenticationMiddlewareTests.swift`.

## Example app

`Example-App/Example-App.xcodeproj` is a separate Xcode project (not part of `Package.swift`) consuming the local package. Open it directly to manually verify player/uploader/camera changes; no shared scheme with the package.
