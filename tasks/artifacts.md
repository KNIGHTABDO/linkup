Linkup artifacts: artifact cards, full-screen viewer (HTML, images, PDF, video, files), remote images [shots]

## Your files (only these)
- `ios/Linkup/UI/Artifacts/ArtifactViews.swift` (replace stubs; keep `ArtifactCard(artifact:)`,
  `ArtifactViewer(artifact:)`, `RemoteImageView(url:)`)
- you may add more files under `ios/Linkup/UI/Artifacts/`

Agents produce files: HTML pages, images (Antigravity has image generation), SVG, PDF, markdown, video, audio,
code. The bridge serves them at relative URLs; ALWAYS turn them into real URLs with `client.resolve(relativeURL)`.

## ArtifactCard (inline, like the Claude "Slack Tide · Artifact" card)
Full-width rounded card (radius 18, `Theme.surface` with hairline border), height ~76: a 56×56 rounded tile on the
left (`Theme.artifactTile` indigo for html/svg/code with `square.on.circle`-style icon; for images show the actual
image thumbnail via RemoteImageView; pdf `doc.richtext`, video `play.rectangle`, audio `waveform`, markdown
`doc.text`, other `doc`), then title (Theme.sans 17 semibold, ivory) and subtitle (Theme.sans 15 secondaryText):
"Artifact" for html/svg, "Image", "PDF", "Video", "Audio", or the file size formatted with ByteCountFormatter.
For `kind == "image"` show instead a large inline image (full width, max height 360, aspect fit, radius 16) with the
title under it — images must appear directly in the chat. Tap → `ui.openArtifact = artifact`.
Context menu: Open, Share (download to a temp file then share), Copy link.

## ArtifactViewer (full-screen cover)
Top bar like the screenshot: glass circle `xmark` left (dismiss), centered title, glass capsule right with
`square.and.arrow.up` (share the file: download with URLSession to a temp file named `artifact.title`, then
ShareLink / UIActivityViewController) and `arrow.clockwise` (reload).
Content by kind:
- html / svg / pdf / markdown / code / file (text-like): a `WKWebView` (UIViewRepresentable) loading
  `client.resolve(artifact.url)` (the token in the URL lets the bridge set a cookie so the page's own CSS/JS/images
  load too). Enable JavaScript, inline media playback, back/forward gestures, pinch zoom for pdf/svg; show a thin
  accent progress bar while loading (KVO `estimatedProgress`); errors → centered message with Retry.
  For markdown use the web view too (the browser shows it as text) — fine.
- image: zoomable image (pinch + double-tap zoom, pan) on black, using a ScrollView-based zoom or MagnifyGesture.
- video / audio: `AVPlayer` with `VideoPlayer` (import AVKit).
Background black for media, Theme.background otherwise. Swipe down to dismiss for images.

## RemoteImageView(url:)
`url` is bridge-relative (or absolute). Load with `AsyncImage(url: client.resolve(url))` with a shimmering
rounded placeholder (Theme.elevated) while loading and an `photo` + "Couldn't load image" state on failure.
`.scaledToFit()` by default; callers set frames. Tap → full screen viewer (present `ArtifactViewer` with an
`ArtifactRef(id: url, kind: "image", title: "Image", url: url, path: nil, mime: nil, size: nil)` via
`ui.openArtifact`).
