# Screenshots

## Invariants

- The feature, text recognition, and cloud downloads start off. Storage Duration starts at **Never**.
- Original files stay in the configured search folders. Tinycast does not copy them into a library.
- Search scopes are recursive. Overlapping scopes produce one entry per path. Hidden files,
  symbolic-link files, and package contents are skipped. An empty scope list returns nothing.
- Automatic cleanup moves original screenshots to Trash only after confirmation in Settings.
  Pinned files, cloud-only files, ordinary media, and files with no known date are kept.
- **Paste Last Screenshot** scans for the newest screenshot image. It ignores the grid query,
  filter, pins, and videos. A missing file or a failed read leaves the clipboard unchanged.
- Recognition runs in the bundled `ClipboardTextHelper`, one image at a time. Each invocation
  receives the recognition mode. Clipboard recognition keeps its Accurate default.
- OCR, cloud-download consent, and automatic cleanup are excluded from backups and `settings.json`.
  Safe display and scope preferences use the normal `AppSettingsKey` / `SettingsFileKey` bindings.

## Settings and commands

Settings → Screenshots contains the feature switch, a 3–6 column preview picker, search folders,
Include All Media, text recognition, Fast / Accurate mode, cloud-file consent, and Storage Duration.
The initial scope is macOS's screenshot save location, or Desktop when none is configured.
Add other capture-tool folders with **Add Folder…**.

The Commands section owns **Search Screenshots** and **Paste Last Screenshot**. Both have the
standard alias, global shortcut, and launcher-visibility controls. They remain independent of
Settings → Commands.

## Search and management

The screen is a newest-first thumbnail grid, with pins first. The header filter offers All, Images,
Movies, and Pinned. Use ⌘P for the filter, ⌘K for actions, and ⌘Y for Quick Look.

- Plain text searches filenames and recognized image text.
- `name:receipt` restricts a term to the filename.
- `text:"invoice number"` searches a recognized phrase.
- `date:2026-10-01`, `date:2026-10`, `date:today`, and `date:yesterday` filter capture dates.
- Terms combine with AND. Quotes keep a phrase together.

Arrow keys move through grid cells. Return or a double-click copies the image; Command-Return pastes
it into the app that was active before the palette. Image copies include the original image bytes and
a file URL. Movies copy as files. Actions also provide Open, Show in Finder, Pin / Unpin, Settings,
and confirmed Move to Trash. A copy made while an image is loading takes priority over that image.

Quick Look appears inside the palette and follows the selected entry. Images use the existing
Quick Look surface; movies use the existing AVKit player and start playing when previewed.
Escape, the Close button, or a click in the card's margin closes it. Hiding the palette, leaving
Screenshots, or reaching an empty result set also closes it and releases playback. Space remains
ordinary search input.

## Ownership and storage

`AppCore` owns `ScreenshotStore` and `ScreenshotsCoordinator`. Both palette and settings hierarchies
inject the coordinator. Settings changes apply through `AppCore.track`, including file imports.
Disabling removes the commands, cancels work, and leaves the screenshot screen.

`ScreenshotScanner` runs off-main. It identifies captures from Spotlight's `kMDItemIsScreenCapture`
metadata or known screenshot / screen-recording / Snapzy / CleanShot names. Include All Media admits
other images and movies. Filesystem `SF_DATALESS` marks cloud-only files; automatic thumbnails skip
these files, and OCR reads them only with consent.

The store scans on opening and periodically while enabled. OCR runs in bounded batches between scans,
with a 15-second helper timeout and a five-minute retry delay after failure. Scope failures are shown
in Settings and on the search screen. There is no copying, scanning, or recognition while disabled.

Pins live in channel-local UserDefaults under `screenshotPinnedPaths`. Rebuildable text lives in
`~/Library/Caches/<bundle-id>/screenshot-text.sqlite3`. The index stores each path's modification time,
size, recognition mode, and text. A changed fingerprint forces recognition again. SQLite reads one
text row at a time off-main; the app keeps fingerprints and matching paths in memory, not the text of
the whole library. Filename results are immediate; text matching is cancellable and debounced by
100 ms. Old queries cannot publish over a new query. Records outside current scopes are pruned.

## Verification

- `screenshots-test`: query syntax, filters, expiry safety, real recursive scanning, overlapping
  scopes, hidden files, symlinks, missing folders, and private-pasteboard image/file writes.
- `screenshot-index-test`: disk fingerprints, replacement and invalidation, pins, opt-in lifecycle,
  cancellation, serialized recognition, and asynchronous text results.
- `clipboard-text-test`: real Vision recognition, including Fast mode.
- `palette-navigation-test`: Quick Look closes on hide, fresh summon, and screen navigation.

Live checks: compare all four column counts against the reference layout; copy and paste PNG, JPEG,
and movie files; use two scopes with overlap; search recognized text; pin an old fixture before
turning cleanup on; verify that only the unpinned old screenshot fixture reaches Trash. Verify the
search screen in Light and Dark and confirm that thumbnails release when the palette closes.
Open Quick Look from Actions and ⌘Y, move between images and movies, and check movie playback and
transport controls. Escape closes only the preview. Hiding the palette stops playback; reopening
and searches with no results leave the preview closed.
