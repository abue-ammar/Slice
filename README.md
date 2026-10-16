# Slice

A native macOS app for recording your screen, webcam and microphone, then turning the result into a polished video without a subscription.

## Features

**Recording**
- Record a whole display, a single window, or a dragged-out area at native Retina resolution and up to 120 fps (on ProMotion displays), with live previews of the screen and camera before you start.
- Webcam, microphone and screen (app/system) audio, each saved as its own track, with live mic level meters.
- Pause and resume to record several takes into one project, or import existing videos.

**iPhone**
- Plug an iPhone in with USB and it gets its own window, titled with its model ("iPhone 17 Pro"): its live screen inside the matching device frame, drawn with Metal at the display's refresh rate. The model comes from the device's hardware identifier (or its screen size), and the frame's screen opening is measured from the frame image itself, so the picture lines up to the pixel. Pick another colour or frame, or none, from the window.
- Choose it under Window on the recording screen. It's recorded straight from the device at the frame's full resolution (for example 1406×2822 for iPhone 17 Pro), with transparency around the phone, so in the editor it sits on your background with its own shadow. The iPhone's sound can be recorded too.
- The window walks you through Trust, unlocking and camera permission, and follows the phone being unplugged, reconnected or swapped for another.
- **3D iPhone**: turn on "Edit on a 3D iPhone" in the iPhone panel and the take opens in the editor on a 3D iPhone: 17 Pro Max, Air, 16 Pro Max, 16 Plus, 15 Pro Max or 14 Pro Max. Recording itself is unchanged (same resolution and frame rate; nothing 3D is drawn into it). The editor lifts the screen back out of the frame's opening, paints out the frame's Dynamic Island (the model has its own) and maps it onto the phone's display, upright and at the screen's own shape, pointer and clicks included. Recordings taken on their side turn the phone on its side. The 3D tab (only shown for iPhone recordings) picks the model and finish, one-click poses, and fine controls for turn, tilt and rotation (all the way round), position, size and perspective; a sway or float animation; the background (the Frame tab's, a studio sweep or a colour), lighting, reflections and shadow. In the preview you can take hold of the phone: drag to move it, ⌥-drag to turn it, scroll to resize. For animations of your own, the timeline gets a 3D track: add keyframes, pose the phone at each, drag them to retime, and pick how it eases into each one. Zooms move the 3D camera in rather than enlarging a picture, and a zoom's tilt turns the phone. It's drawn with SceneKit in the same renderer as everything else, so the preview, scrubbing and export all show the same frame for the same moment. Switch it off at any time to get the flat frame back.

**Editing**
- Camera layouts: four corners (landscape, portrait or square, small or large), large and centred, or hidden. Change them anywhere on the timeline with smooth transitions.
- Zooms with an adjustable focal point, optional pan to a second point or following the cursor, per-zoom timing and easing curves, and light motion blur. Auto-zoom suggests zooms from your clicks.
- Liquid Glass zoom: a refracting glass lens (circle, squircle or pill) that magnifies the area under it, with adjustable size, magnification, refraction, thickness, dispersion, frost, rim light, shadow and opacity. It can glide between two spots or follow the cursor, and lenses placed back to back flow into each other as one glass, morphing position, size and shape.
- A real-time preview that renders the same composition as the export on its own thread, at the display's refresh rate (up to 120 Hz) and full Retina resolution, with a quality setting for slower Macs.
- Cursor drawn from the recorded mouse path, so it can be shown or hidden, resized and restyled after recording: the native macOS cursors (hand, I-beam, resize arrows...) in Big Sur or Tahoe artwork, picked from previews in the sidebar, with brief flickers between them ignored, adjustable zero-lag smoothing, motion blur along the pointer's path, and an optional tilt into movement.
- Click effects drawn at every click made while recording: a soft ripple ring, or a liquid wave rendered with a Metal shader.
- Split, trim and delete sections of a take, with undo/redo.
- Styled frame: gradient or image backgrounds (kept in a reusable library), padding, rounded corners and shadow. With no padding the screen fills the frame; padding changes glide in the preview.
- Webcam background blur (on-device person segmentation) and rounded, mirrored camera.
- Separate volume and mute for the mic and screen audio.
- Voice enhancement: [DeepFilterNet3](https://github.com/Rikorose/DeepFilterNet) noise removal on the microphone track only, with an optional podcast polish (gentle EQ, 2:1 compression, −16 LUFS loudness and a −1 dBFS limiter), and an Original / Enhanced switch to compare in the preview. It runs on your Mac and works offline. The model isn't bundled: the first time you turn it on, Slice asks before downloading it (35.9 MB: the DeepFilterNet3 weights plus the official `deep-filter` 0.5.6 runtime, MIT or Apache 2.0). Both files are pinned to SHA-256 hashes and kept in `~/Library/Application Support/Slice/Voice Enhancement`. Your recordings are never changed: the enhanced voice is saved beside each take's `mic.m4a`.

**Transcript and subtitles**
- On-device transcription with word timings, using the engine picked in Settings ▸ Transcription:
  - **Apple Speech**: SpeechAnalyzer on macOS 26 and later; on macOS 15–25 (or for a language SpeechAnalyzer lacks) the on-device `SFSpeechRecognizer`. A language the Mac can't recognise locally is refused rather than sent to Apple's servers.
  - **Parakeet AI**: [Parakeet Ultra 0.6B](https://huggingface.co/FluidInference/parakeet-ultra-coreml) (moondream's post-training of NVIDIA Parakeet TDT 0.6B v3, CC BY 4.0, 25 European languages), run on the Neural Engine with [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.7. It isn't bundled: Slice downloads it only when you click Download in Settings (632.2 MB, pinned to one revision, every file checked against its published hash) into `~/Library/Application Support/Slice/Transcription/Parakeet`, where it can be deleted again. No transcription API or account; it works offline after the download.
- Edit the video by deleting words or sentences from the transcript.
- Burned-in subtitles with the spoken word highlighted, editable without cutting the video, plus `.srt` export.

**Export**
- Auto (the recording's own shape), 16:9, 9:16 and 1:1 from one edit (portrait and square follow the cursor), at 1080p, 1440p or 4K, 30, 60 or 120 fps, three quality levels, HEVC or H.264.

## Requirements

- macOS 15 or later (Apple Speech uses SpeechAnalyzer on macOS 26 and on-device SFSpeechRecognizer before that; Parakeet AI needs the one-time model download)
- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

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

The app is signed ad-hoc by default, which is fine for running on your own Mac. On first use macOS asks for Screen Recording, Camera and Microphone permission.

### Signing with your own Developer ID

Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and fill in your team and bundle ID prefix. That file is ignored by git.

To build a notarized DMG, also copy `scripts/release.local.env.example` to `scripts/release.local.env`, store your notary credentials once with `xcrun notarytool store-credentials`, then run:

```sh
scripts/release.sh
```

## Project layout

- `Sources/SliceCore` – the engine, built as a Swift package so it can be tested on its own:
  - `Project` – project model, bundle on disk, cuts and splits, timeline segments, imports, transitions
  - `Rendering` – Core Image frame renderer, scene and layout maths, tilt, transitions, AVFoundation composition and export
  - `Capture` – frame pacing and the audio writer used while recording
  - `Input` – the drawn cursor, its motion smoothing, hover detection and keystrokes
  - `Analysis` – smart zoom and webcam glitch detection
  - `Audio` – music, levels, loudness, voice enhancement
  - `Captions` – transcription and subtitles
  - `Devices` – iPhone frames, layout, compositing and usbmuxd
  - `Resources` – Metal shaders (compiled at runtime), cursor artwork and sounds, and the 3D iPhone models (USDZ)
- `App/Sources` – the SwiftUI app:
  - `App` – app entry, recording session, window morphs
  - `Capture` – the capture bar, recorder, area and window pickers
  - `Devices` – connected iPhones: streams, windows, previews
  - `Projects` – the projects grid
  - `Editor` – editor view, preview, export, command palette; `Model` (editor state), `Timeline`, `Inspector`, `Transcript`
- `Tests/SliceCoreTests` – unit and rendering tests: `swift test`.

Projects are saved as `.slice` files in `~/Movies/Slice`. A `.slice` file is a package (a folder Finder shows as one file) holding `project.json` and every take's screen, camera, audio and cursor recordings, plus imported music and backgrounds (and, with voice enhancement, its enhanced voice under `voice/`). Everything inside uses relative paths, so a project can be moved, renamed or sent to someone else (AirDrop, or zipped) and opens with every edit intact. Double-click one in Finder, drop it on Slice's Dock icon or window, or use File ▸ Open… (⌘O). Edits save automatically; projects opened from somewhere read-only are copied into `~/Movies/Slice` first. Older `.screenrec` projects there are renamed to `.slice` the first time the projects list loads.

To test voice enhancement against the real model (it downloads 36 MB into the folder you name): `SLICE_VOICE_E2E=1 SLICE_VOICE_MODEL_DIR=/tmp/slice-voice swift test --filter VoiceEnhancementTests`.

To test Parakeet transcription against the real model (it downloads 632 MB into the folder you name): `SLICE_PARAKEET_E2E=1 SLICE_PARAKEET_MODEL_DIR=/tmp/slice-parakeet swift test --filter TranscriptionTests`.

## License

Public domain ([Unlicense](LICENSE)): use it however you like.

The 3D models in `Sources/SliceCore/Resources/Models` are licensed under [CC BY 4.0](http://creativecommons.org/licenses/by/4.0/) (see `CREDITS.txt` beside them):
- ["iPhone 17 Pro Max"](https://sketchfab.com/3d-models/iphone-17-pro-max-87fc1df741384124a8ce0226d2b2058d) and ["iPhone 16 Pro Max"](https://sketchfab.com/3d-models/iphone-16-pro-max-41a071ae12794b668502f58d1e0fd1a3) by [MajdyModels](https://sketchfab.com/MG990)
- ["iPhone Air"](https://sketchfab.com/3d-models/iphone-air-055022b853aa4c6cb25cc6979178e719) by [Ranguel](https://sketchfab.com/Ranguel)
- ["Iphone 16 Plus"](https://sketchfab.com/3d-models/iphone-16-plus-c1719ed762a7412d933f3ddef0ce2929) by [WhatIsLove](https://sketchfab.com/vladgutu11)
- ["IPhone 15 Pro Max Made In Blender"](https://sketchfab.com/3d-models/iphone-15-pro-max-made-in-blender-616945ef6bef415889c8748918700bc7) by [PolygonMBW](https://sketchfab.com/PolygonMBW)
- ["iPhone 14 Pro Max"](https://sketchfab.com/3d-models/iphone-14-pro-max-95f11f5a06604c8b9fd44046ae52a9cc) by [akshatmittal](https://sketchfab.com/akshatmittal)
