# Contributing to Slice

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs**: open an [issue](https://github.com/rit3zh/slice/issues) with your macOS version, your Mac, what you did and what happened. A screenshot or short recording helps a lot.
- **Features**: open an issue first so we can agree on the idea before you write the code.
- **Pull requests**: keep each one to a single change, and describe what it does and how you tested it.

By submitting a contribution you agree to section 6 of the [license](LICENSE): you keep the copyright, and you give the Licensor a license to use your contribution in Slice.

## Building

You'll need macOS 15 or later, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Slice.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project Slice.xcodeproj -scheme Slice -configuration Release -derivedDataPath build
open "build/Build/Products/Release/Slice.app"
```

The app is signed ad-hoc by default, which is fine for running on your own Mac. Run `xcodegen generate` again whenever you add or remove files.

### Building a DMG without a Developer ID

Run `scripts/setup-local-signing.sh` once to create a self-signed certificate, then:

```sh
scripts/dmg.sh
```

This writes `dist/Slice.dmg` and its SHA-256. The app isn't notarized, so people opening it must click **Open Anyway** in System Settings › Privacy & Security the first time. Sign every release with the same certificate. If the certificate changes, users have to grant Screen Recording, Camera and Microphone permission again.

### Signing with your own Developer ID

Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and fill in your team and bundle ID prefix. Git ignores that file.

To build a notarized DMG, also copy `scripts/release.local.env.example` to `scripts/release.local.env`, store your notary credentials once with `xcrun notarytool store-credentials`, then run:

```sh
scripts/release.sh
```

## Project layout

- `Sources/SliceCore`: the engine, built as a Swift package so it can be tested on its own.
  - `Project`: project model, bundle on disk, cuts and splits, timeline segments, imports, transitions
  - `Rendering`: Core Image frame renderer, scene and layout maths, tilt, transitions, AVFoundation composition and export
  - `Capture`: frame pacing and the audio writer used while recording
  - `Input`: the drawn cursor, its motion smoothing, hover detection and keystrokes
  - `Analysis`: smart zoom and webcam glitch detection
  - `Audio`: music, levels, loudness, voice enhancement
  - `Captions`: transcription and subtitles
  - `Devices`: iPhone frames, layout, compositing and usbmuxd
  - `Resources`: Metal shaders (compiled at runtime), cursor artwork and sounds, and the 3D iPhone and MacBook models (USDZ)
- `App/Sources`: the SwiftUI app.
  - `App`: app entry, recording session, window morphs
  - `Capture`: the capture bar, recorder, area and window pickers
  - `Devices`: connected iPhones: streams, windows, previews
  - `Projects`: the projects grid
  - `Editor`: editor view, preview, export, command palette; `Model` (editor state), `Timeline`, `Inspector`, `Transcript`
- `Packages`: local Swift packages (BorderBeamKit, SmoothGradient).
- `Tests/SliceCoreTests`: unit and rendering tests.
- `website`: the Next.js site, including the license and credits pages.

Projects are saved as `.slice` packages in `~/Movies/Slice`. Each one holds `project.json` and every take's screen, camera, audio and cursor recordings, all with relative paths, so a project can be moved or shared and still opens with its edits intact.

## Tests

```sh
swift test
```

The voice enhancement and Parakeet tests can also run against the real models. They download them into the folder you name:

```sh
SLICE_VOICE_E2E=1 SLICE_VOICE_MODEL_DIR=/tmp/slice-voice swift test --filter VoiceEnhancementTests        # 36 MB
SLICE_PARAKEET_E2E=1 SLICE_PARAKEET_MODEL_DIR=/tmp/slice-parakeet swift test --filter TranscriptionTests  # 632 MB
```

### CI

Every push to `main` and every pull request runs two GitHub Actions workflows:

- **CI**: typechecks and builds the website, and syntax-checks the scripts.
- **Checks**: makes sure `LICENSE` matches the website's license page, every Swift file has its header, and the JSON resources are valid.

To skip them, put `[skip ci]` anywhere in the commit message, or add the `skip ci` label to a pull request. To run them on demand, use **Run workflow** in the Actions tab.

## Code style

- Match the code around your change: its naming, idioms and comment density.
- Start every new Swift file with the standard header (file name, target, `Created by …`).
- Keep comments for `// MARK:` sections, workarounds, compatibility rules and credits.
- Keep files small, around 400 lines at most. Split large types into `Type+Section.swift` extensions.
- Don't add third-party code or assets unless their license allows it, and add them to section 11 of the license (`LICENSE` and `website/src/components/license/content.ts`, kept word for word the same).
