Linkup in-app updates: GitHub release check, update banner, SideStore install + source

## Your files (only these)
- create `ios/Linkup/Core/Support/UpdateChecker.swift`
- create `ios/Linkup/UI/Shell/UpdateBanner.swift`
- create `ios/Linkup/UI/Settings/UpdatesSection.swift`
- edit `ios/Linkup/App/LinkupApp.swift` ONLY to: add `let updates = UpdateChecker()` to AppModel, inject
  `.environment(app.updates)`, call `app.updates.checkIfDue()` in `start()` and when the scene becomes active.
- edit `ios/Linkup/UI/RootView.swift` ONLY to overlay the `UpdateBanner` at the top (below the top bar) when
  `updates.showsBanner`.
- edit `ios/Linkup/UI/Settings/SettingsViews.swift` ONLY to add `UpdatesSection()` as a section in SettingsView.

## What to build
Port the working implementation from the Knight Music app in the sibling repo (read these files first and adapt
them, do not reinvent): `/home/knight/Desktop/projects/knight-music/KnightMusic/Core/Support/UpdateChecker.swift`,
`/home/knight/Desktop/projects/knight-music/KnightMusic/UI/Shell/UpdateBanner.swift`,
`/home/knight/Desktop/projects/knight-music/KnightMusic/UI/Settings/UpdatesSection.swift`.
Changes: repo `KNIGHTABDO/linkup`; texts "Linkup X available"; source URL
`https://github.com/KNIGHTABDO/linkup/releases/latest/download/apps.json`; the IPA asset is `Linkup.ipa`;
Knight Music's `DebugLaunch.isDemo` check becomes `DebugLaunch.screen != nil`; use Linkup's `Theme`
(Theme.accent, Theme.text, Theme.secondaryText) instead of Knight Music's names; Linkup's UIState has `toast`.
Keep `sidestore://install?url=` and `sidestore://source?url=` deep links exactly as in Knight Music.
