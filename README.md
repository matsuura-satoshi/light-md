# LightMD

A lightweight, view-only Markdown viewer for macOS. Inspired by Marked 2 and iA Writer — focused on readability, fast startup, and beautiful typography.

## Highlights

- **Fast & Lightweight** — Native Swift app, launches instantly
- **Beautiful Rendering** — Warm-toned themes with iA Writer-inspired typography
- **GFM Support** — Tables, task lists, strikethrough, autolinks via cmark-gfm
- **Table of Contents** — Right-side overlay sidebar with scroll tracking
- **Theme System** — 3 built-in themes + custom theme support
- **PDF Export** — Multi-page A4 output with proper pagination
- **Auto-Reload** — File watching with automatic re-render on save
- **Fully Local** — No network required

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

## Getting Started

### Download

Download the latest zip from [GitHub Releases](https://github.com/matsuura-satoshi/light-md/releases), extract it, and move `LightMD.app` to your Applications folder.

The app is not notarized, so you need to remove the quarantine attribute before first launch:

```bash
xattr -d com.apple.quarantine /Applications/LightMD.app
```

### Build from Source

Requires Xcode 16+ and macOS 14 SDK.

```bash
# Build release .app bundle
./Scripts/build_app.sh 1.0.0

# Output: build/LightMD-v1.0.0.zip
```

Or build directly with Xcode:

```bash
xcodebuild -project LightMD.xcodeproj -scheme LightMD -configuration Release build
```

### Regenerate Xcode Project

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
```

## Usage

### Opening Files

- **Cmd+O** — File open dialog
- **Drag & Drop** — Drop `.md` files anywhere on the window
- **Double-click** — Associate `.md` files with LightMD in Finder (Get Info > Open with)

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+O` | Open file |
| `Cmd+R` | Reload |
| `Cmd+T` / `Cmd+I` | Toggle Table of Contents |
| `Cmd+E` / `Cmd+P` | Export as PDF |
| `Cmd+,` | Preferences |
| `Cmd+Plus` / `Cmd+Minus` | Zoom in/out |
| `Cmd+0` | Reset zoom |

### Themes

Three built-in themes:

- **Warm Light** (default) — Cream background, gold accents
- **Warm Dark** — Dark warm background, gold accents
- **Classic Light** — White background, GitHub-like styling

Custom themes can be created in Preferences (`Cmd+,`). Themes are stored in `~/Library/Application Support/LightMD/themes/`.

### PDF Export

Export the current document as a multi-page A4 PDF with `Cmd+E` or `Cmd+P`, or click the export icon in the toolbar. The PDF preserves the current theme styling with print-optimized layout.

## Architecture

```
LightMD/
├── App/            — SwiftUI app entry, ContentView, TOC sidebar, drop overlay
├── Rendering/      — cmark-gfm wrapper, WKWebView, HTML template, PDF paginator
├── FileWatcher/    — FSEvents-based file monitoring with debounce
├── Theme/          — Theme manager, built-in CSS themes, preferences
├── Models/         — App state, TOC heading model
└── Resources/      — CSS theme files, TOC JavaScript
```

**Tech stack:** SwiftUI + WKWebView + cmark-gfm (via [brokenhandsio/cmark-gfm](https://github.com/brokenhandsio/cmark-gfm))

## License

MIT
