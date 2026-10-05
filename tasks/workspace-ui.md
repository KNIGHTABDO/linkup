Linkup projects: new project, file browser, code viewer, git panel, CI runs [shots]

## Your files (only these): new files under `ios/Linkup/UI/Workspace/` (create the folder).
Use only the store API in `Core/Store/SessionStore+Extras.swift` (createProject, listFiles, readFile, gitStatus,
gitDiff, gitLog, gitCommit, gitPush, ciRuns) and `store.projects` / `store.loadProjects()`.

## Views to build (Claude wires their entry points)
1. `NewProjectSheet(onCreated: (ProjectInfo) -> Void)`: name field (validated: letters/digits/-/_/spaces), template
   picker as large selectable cards (Empty, Web, Python, iOS app — icons + one-line descriptions), toggles
   "Initialize git" (on) and "Add README" (on), Create button (glassProminent) → `store.createProject` → onCreated.
   Errors inline. Theme.surface background, glass xmark, title "New project".
2. `ProjectsView()`: list of `store.projects` (folder icon, name, path tail) with search, "+" toolbar button presenting
   NewProjectSheet; tap → `ProjectDetailView(project:)`. `.task { await store.loadProjects() }`.
3. `ProjectDetailView(project: ProjectInfo)`: segmented control **Files | Changes | History | Builds**, plus a
   toolbar menu "New session here" (sets `ui.draftProject = project.path; ui.newChat()` and dismisses — use
   `@Environment(\.dismiss)` and UIState).
   - **Files**: `FileBrowserView(path:)` drill-down list (folders first, size/modified secondary, file icons by
     extension), pull to refresh; tap file → `FileViewer(path:)`.
   - `FileViewer(path:)`: text files in a mono, line-numbered, horizontally scrollable view with lightweight syntax
     colouring (keywords/strings/comments for swift, python, js/ts, json, yaml, html/css, sh; keep it fast: highlight
     only the first 3000 lines), search within file, copy, share; images/pdf/html (`content.url`) → present
     `ArtifactViewer` via `ui.openArtifact = ArtifactRef(id: url, kind: <image|pdf|html>, title: name, url: url,
     path: path, mime: nil, size: size)`; markdown → MarkdownView; binary → "Can't preview this file".
   - **Changes**: `GitStatusView(path:)`: branch + ahead/behind header, changed files list with colored status badges
     (M orange, A green, D red, ?? grey), tap → diff view (unified diff coloured +/− lines, file headers bold), a
     commit box (TextField message + "Commit" + "Push" glass buttons, results/errors as toasts), "Not a git repository"
     state.
   - **History**: commits list (short hash mono, subject, author, relative date).
   - **Builds**: `ciRuns` list: workflow name, title, branch, status icon (queued/in progress spinner/success green
     check/failure red x), relative date; tap opens the run URL in SFSafariViewController; auto-refresh every 20 s
     while visible if any run is in progress.
All lists: Theme.background, rows like the sidebar (Theme.sans 17, secondary 13), insetGrouped where it fits.
