Linkup bridge: projects, files, git, GitHub Actions and dev-server proxy

## Your files: `bridge/linkup_bridge/workspace.py` (replace the stub, keep every name/signature/return shape)

- `create_project(name, git, readme, template)`: sanitize the name (letters, digits, -, _, space→-; no slashes,
  no leading dot), create `PROJECTS/<name>` (error if it exists), `git init -q` when git=True, a README.md with
  `# <name>` when readme=True. Templates: None/"empty" (nothing else), "web" (index.html + style.css + script.js
  minimal starter), "python" (main.py, .gitignore, README), "ios" (README noting it's a SwiftUI app built by GitHub
  Actions like the user's other apps, plus a project.yml skeleton for XcodeGen targeting iOS 26 and an empty
  `<Name>/App.swift` with a minimal SwiftUI @main app). Return {"name", "path"}.
- `list_dir(path)`: entries sorted dirs first then name (case-insensitive); skip `.git`, `node_modules`, `.build`,
  `build`, `__pycache__`, `.DS_Store`; include other dotfiles only if they are files like `.gitignore`. Max 2000.
- `read_file(path, media_url)`: text if the file is UTF-8 decodable and ≤ 2 MB (truncate to 2 MB with truncated=True),
  language from the extension (swift, py, js, ts, json, md, html, css, yml, sh, …); for images/pdf/html/video also
  `url = media_url(path)`; binaries → text None.
- git (`asyncio.create_subprocess_exec("git", "-C", path, …)`, 20 s timeout): `git_status` via
  `git status --porcelain=v1 -b` (parse branch, ahead/behind, files with staged flag; isRepo False when not a repo),
  `git_diff(path, file)` (`git diff HEAD -- <file>` or whole repo; include untracked files' content as additions;
  cap 400 KB), `git_log` (`--pretty=%H%x1f%h%x1f%s%x1f%an%x1f%ct`), `git_commit` (`git add -A` then commit; return
  the new commit like log entries, None if nothing to commit), `git_push` (return combined output; 60 s timeout).
- `gh_runs(path)`: if the repo has a GitHub remote, `gh run list --limit N --json databaseId,name,displayTitle,status,
  conclusion,headBranch,event,url,createdAt` run inside the repo; created → epoch. `artifacts`: for completed runs only,
  skip (keep []) unless cheap. Return [] when gh/remote is missing.
- `proxy(request, port, tail)`: reverse proxy to `http://127.0.0.1:<port>/<tail>?<query>` for any method with
  aiohttp ClientSession (stream the body back, copy status and headers except hop-by-hop/content-encoding/length),
  and WebSocket upgrade passthrough (for Vite/Next HMR). Only ports 1024–65535 except 8890 (the bridge itself).
  Rewrite `Location` headers that point at localhost:<port> to `/linkup/proxy/<port>/…`.
Test against real repos in ~/Desktop/projects (e.g. knight-music, linkup) and a throwaway project you create and
then delete under /tmp (set LINKUP_PROJECTS=/tmp/... for the create test).

---
# Shared rules for Linkup bridge tasks (Python)
The bridge (`bridge/linkup_bridge/`) is a Python 3.12 aiohttp service on the user's Linux PC (systemd
`linkup-bridge`, venv `~/.linkup/.venv`, data in `~/.linkup`). It drives the user's signed-in CLIs. Read
`bridge/linkup_bridge/server.py` (how your module is called), `store.py` and the stub you replace FIRST.
- Only edit the files your task lists. Keep every function name/signature/return shape in the stub exactly.
- No new dependencies beyond the stdlib and aiohttp (already installed). Never print secrets.
- Use `asyncio.create_subprocess_exec` for commands (never shell=True with user input), timeouts on everything,
  and never block the event loop (wrap blocking work in `asyncio.to_thread` if you call it from async code).
- Verify for real on this PC: run your functions with `~/.linkup/.venv/bin/python -c ...` from `bridge/` and show the
  output in your final message. Do NOT restart the systemd service (Claude does that when merging).
- Commit only your files when done.
