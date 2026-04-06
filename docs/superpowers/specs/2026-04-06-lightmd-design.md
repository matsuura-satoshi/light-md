# LightMD — Lightweight Markdown Viewer for macOS

## Overview

LightMD is a lightweight, view-only Markdown viewer for macOS inspired by Marked 2 and iA Writer. It prioritizes readability, fast startup, and beautiful typography with a warm, minimalist design aesthetic.

## Design Goals

- **High readability**: iA Writer-inspired typography with generous whitespace and line height
- **Lightweight & fast**: Native Swift app targeting sub-200ms startup
- **View-only**: No editing — purely a Markdown viewer
- **Customizable theming**: Preset and custom themes with font selection
- **macOS native**: Proper integration with macOS conventions and system features

## Technology Stack

| Component | Technology |
|---|---|
| App framework | SwiftUI (macOS 14+) |
| Markdown rendering | WKWebView + custom CSS |
| Markdown parser | cmark-gfm (C library via SPM) |
| File watching | FSEvents (DispatchSource.makeFileSystemObjectSource) |
| Package management | Swift Package Manager |

### Why SwiftUI + WKWebView

- SwiftUI provides native macOS window management, menus, and preferences
- WKWebView gives full HTML/CSS control for Markdown rendering, enabling GitHub-style rendering with custom styling
- cmark-gfm provides complete GFM support including tables, task lists, and code blocks

## Architecture

```
LightMDApp (SwiftUI App)
├── ContentView
│   ├── MarkdownWebView (NSViewRepresentable → WKWebView)
│   └── TOC sidebar (right side, SwiftUI List or in-WebView)
├── MarkdownRenderer (cmark-gfm → HTML)
├── FileWatcher (FSEvents)
├── ThemeManager (CSS loading, saving, switching)
└── PreferencesView (theme & font settings)
```

### Component Responsibilities

| Component | Responsibility |
|---|---|
| `LightMDApp` | SwiftUI App entry point. Handles `onOpenURL` for .md file association, window management |
| `ContentView` | Main view. Hosts WKWebView and optional TOC sidebar |
| `MarkdownWebView` | `NSViewRepresentable` wrapping WKWebView. Loads rendered HTML, handles theme injection |
| `MarkdownRenderer` | Calls cmark-gfm C API to convert Markdown → HTML. Wraps output in HTML template with CSS |
| `FileWatcher` | Monitors open file for changes using FSEvents. Triggers re-render on save |
| `ThemeManager` | Manages preset and custom themes. Reads/writes theme CSS files. Persists user preference |
| `PreferencesView` | SwiftUI settings window for theme selection, font choice, and custom theme management |

## File Opening

Three methods supported:

1. **Double-click .md files**: UTI registration in Info.plist for `net.daringfireball.markdown` and `public.markdown`
2. **Drag & drop**: `onDrop` modifier on ContentView accepts .md files
3. **File open dialog**: `⌘O` triggers `NSOpenPanel` filtered to .md files

## Markdown Rendering Pipeline

```
.md file → read as String
         → cmark-gfm (Markdown → HTML)
         → wrap in HTML template (inject theme CSS + TOC JS)
         → WKWebView.loadHTMLString()
```

### cmark-gfm Extensions Enabled

- Tables (`CMARK_GFM_EXTENSION_TABLE`)
- Autolinks (`CMARK_GFM_EXTENSION_AUTOLINK`)
- Strikethrough (`CMARK_GFM_EXTENSION_STRIKETHROUGH`)
- Task lists (`CMARK_GFM_EXTENSION_TASKLIST`)

## Design System

### Visual Style

- **Base**: Warm cream background (#faf9f6) with dark brown text (#2c2825)
- **Typography**: System sans-serif (-apple-system) as default, with Serif and Mono options
- **Accent**: Warm gold (#c9a96e) for heading underlines, table header borders, active TOC items
- **Code blocks**: Warm-toned background (#f0ede7) with subtle border
- **Tables**: Gold header underline, alternating row backgrounds, generous padding
- **Blockquotes**: Left gold border with warm background
- **Line height**: 1.85 for body text (readability-focused)
- **Content width**: max-width 720px, centered

### Dark Theme Variant

- Background: #1c1b19
- Text: #e8e4dd
- Secondary text: #b0a99e
- Code background: #27261f
- Same gold accent (#c9a96e) maintained across themes

## Theme System

### Storage

```
~/Library/Application Support/LightMD/
├── themes/
│   ├── warm-light.css      (built-in, bundled)
│   ├── warm-dark.css       (built-in, bundled)
│   ├── classic-light.css   (built-in, bundled)
│   └── my-solarized.css    (user-created)
├── preferences.json
│   ├── selectedTheme: "warm-light"
│   ├── fontFamily: "system-sans"
│   └── fontSize: 16
```

### Preset Themes

1. **Warm Light** (default): Cream background, warm brown text, gold accents
2. **Warm Dark**: Dark warm background, light text, gold accents maintained
3. **Classic Light**: White background, neutral gray text, GitHub-like

### Custom Themes

- Users can create new themes with font and color customization
- Themes are CSS files stored in the themes directory
- Settings UI allows creating, editing, and deleting custom themes
- Theme CSS is injected into the HTML template at render time

### Font Options

- System Sans (-apple-system, Helvetica Neue)
- Serif (Georgia)
- Mono (SF Mono, Menlo)
- Custom font path (user-specified)

## TOC Sidebar

- Positioned on the **right side** of the window
- Extracts headings (h1-h6) from rendered HTML via JavaScript
- Click to smooth-scroll to heading
- Shows/hides with toggle (⌘T or button)
- Highlights current section based on scroll position
- Styled consistently with active theme

## File Watching & Auto-Reload

- Uses `DispatchSource.makeFileSystemObjectSource` (FSEvents wrapper) to monitor the open file
- On change detection: re-read file, re-render, update WKWebView
- Preserves scroll position across reloads via JavaScript
- Debounce at 100ms to avoid rapid re-renders during save operations

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘O` | Open file |
| `⌘R` | Manual reload |
| `⌘T` | Toggle TOC sidebar |
| `⌘F` | Find in page (WKWebView built-in) |
| `⌘,` | Preferences |
| `⌘+` / `⌘-` | Zoom in/out |

## SPM Dependencies

Use a community cmark-gfm SPM wrapper that includes GFM extensions (tables, autolink, strikethrough, tasklist). Candidates at implementation time:

- `apple/swift-cmark` does NOT include GFM extensions — not sufficient alone
- Wrap the cmark-gfm C library as a local SPM C target, or use a maintained fork that exposes GFM extensions
- Evaluate available wrappers at implementation time and pick the most maintained option

## Project Structure

```
LightMD/
├── Package.swift (or LightMD.xcodeproj)
├── Sources/
│   └── LightMD/
│       ├── App/
│       │   ├── LightMDApp.swift
│       │   └── ContentView.swift
│       ├── Rendering/
│       │   ├── MarkdownRenderer.swift
│       │   └── MarkdownWebView.swift
│       ├── FileWatcher/
│       │   └── FileWatcher.swift
│       ├── Theme/
│       │   ├── ThemeManager.swift
│       │   └── PreferencesView.swift
│       └── Resources/
│           ├── template.html
│           ├── toc.js
│           └── themes/
│               ├── warm-light.css
│               ├── warm-dark.css
│               └── classic-light.css
├── docs/
└── README.md
```

## Verification

1. **Build**: `swift build` or Xcode build succeeds with no errors
2. **Launch**: App opens within 200ms
3. **File open**: All 3 methods (double-click, drag & drop, ⌘O) work
4. **Rendering**: Tables, code blocks, blockquotes, lists, headings render correctly
5. **Auto-reload**: Edit .md file externally → view updates automatically
6. **TOC**: Right sidebar shows headings, click scrolls to section
7. **Themes**: Switch between preset themes, create and save custom theme
8. **Font**: Change font family and verify rendering updates
