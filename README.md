<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="112" height="112" alt="Slice">
</p>

<h1 align="center">Slice</h1>

<p align="center">
  A native screen recorder and video editor for Mac.<br>
  Free, no account, and everything stays on your Mac.
</p>

<p align="center">
  <a href="https://github.com/rit3zh/slice/releases/latest"><img src="https://img.shields.io/badge/Download-0A84FF?style=flat&logo=apple&logoColor=white" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-5E5CE6?style=flat&labelColor=1c1c1e" alt="macOS 15 or later">
  <img src="https://img.shields.io/badge/Swift-6-FF9F0A?style=flat&logo=swift&logoColor=white&labelColor=1c1c1e" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Source--available-30D158?style=flat&labelColor=1c1c1e" alt="Source-available license"></a>

<p align="center">
  <a href="https://www.buymeacoffee.com/rit3zh" target="_blank" title="Buy me a coffee"><img src="https://iili.io/JoQ1MeS.md.png" alt="Buy me a coffee" width="130"></a>
</p>

<p align="center">
  <a href="https://www.producthunt.com/products/slice-5?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-slice-7" target="_blank" rel="noopener noreferrer"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1284128&amp;theme=light&amp;t=1792420172404" alt="Slice - A native macOS screen recorder and editor. | Product Hunt" width="250" height="54"></a>
</p>
</p>

<br>

<p align="center">
  <img src="website/public/media/slice-editor.jpg" alt="The Slice editor" width="100%">
</p>

## Features

- **Recording**: a display, a window or any area, at Retina resolution and up to 120 fps, with camera, microphone and system audio on separate tracks.
- **Zooms**: Smart Zoom suggests zooms from your clicks. Each one can pan or follow the cursor.
- **Liquid Glass lens**: a glass magnifier that glides across the screen and morphs into the next one.
- **Cursor**: resize, smooth, restyle or hide it after recording, and add click effects.
- **iPhone**: record a connected iPhone in its device frame, or edit the take on a 3D iPhone.
- **Transcript**: on-device transcription. Delete words to cut the video, and add subtitles.
- **Voice enhancement**: offline noise removal and podcast-style polish.
- **Export**: 16:9, 9:16 and 1:1 from one edit, up to 4K and 120 fps.
- **Private**: no account, no tracking, no watermark.

## Install

The easiest way is one line in Terminal. It downloads the latest release, moves Slice to Applications and opens it, with no "can't verify" warning:

```sh
curl -fsSL https://slice.rit3zh.dev/install.sh | bash
```

Requires macOS 15 or later on Apple silicon.

Or download `Slice.dmg` from [Releases](https://github.com/rit3zh/slice/releases/latest). Slice isn't notarized by Apple yet, so macOS says it can't verify it. To open it anyway:

1. Open the DMG. If macOS blocks it, click **Done**, then go to **System Settings › Privacy & Security** and click **Open Anyway**.
2. Drag Slice to Applications.
3. Open Slice. If macOS blocks it again, click **Open Anyway** in the same place, or run `xattr -dr com.apple.quarantine /Applications/Slice.app`.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Slice.xcodeproj
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for signing, release builds, the project layout and tests.

## Support

Slice is free and made by one person. If it's useful to you, you can [buy me a coffee](https://buymeacoffee.com/rit3zh). Starring the repo and [reporting bugs](https://github.com/rit3zh/slice/issues) helps too.

## License

Slice is source-available under the [Slice Source-Available License](LICENSE).

You can use it for free, including at work, and read, build and modify the code. Selling it, redistributing it commercially or rebranding it needs written permission. Third-party components keep their own licenses (section 11).

## Credits

[FluidAudio](https://github.com/FluidInference/FluidAudio), [Parakeet](https://huggingface.co/FluidInference/parakeet-ultra-coreml), [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet), [SmoothGradient](https://github.com/raymondjavaxx/SmoothGradient), [border-beam](https://beam.jakubantalik.com), and the [3D iPhone models](Sources/SliceCore/Resources/Models/CREDITS.txt) by their Sketchfab artists.
<br>

<p align="center"><sub>Made by <a href="https://x.com/rit3zh">@rit3zh</a></sub></p>
