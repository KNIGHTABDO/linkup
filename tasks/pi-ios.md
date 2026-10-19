Add the Pi agent to the Linkup iOS app

## Goal
The bridge is getting a 4th agent `id = "pi"` (name "Pi", the Pi coding agent by Mario Zechner). Another agent is writing
the Python side right now; you do the whole iOS side so Pi is a first-class citizen everywhere Claude/Antigravity/Hermes
appear. The bridge sends the same normalized events and `AgentInfo` catalog as for other agents (models like
`meta-ai/muse-spark-1.3-contributor`, efforts `off/minimal/low/medium/high/xhigh`, `commands` list of
`{name, description, kind}` where names look like `skill:brainstorming`, supportsImages true, supportsPermissions false).
Pi's tool names are LOWERCASE: `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls` with args `bash{command}`,
`read{path,offset,limit}`, `write{path,content}`, `edit{path,oldText/newText or edits[]}` (check
`~/.local/lib/node_modules/@mariozechner/pi-coding-agent/docs` and `tasks/pi-rpc-sample.jsonl` for the real shapes; grep the pi
`dist/` tool sources for the exact edit-tool arguments).

## Do (grep the repo for every place the three agents are listed — `grep -rn '"hermes"\|case hermes\|\.hermes' ios/`)
1. `Core/Protocol/Models.swift` `AgentKind`: add `case pi` (title "Pi", SF symbol `function` or the closest to "π").
2. `UI/Brand/AgentLogo.swift`: Pi mark. No asset available: draw a bold serif/rounded "π" glyph inside the same-size frame
   (a `Text("π")` or a small custom `Shape` path of the pi symbol), tinted `Theme.text`, so it matches the monochrome Hermes
   treatment. Update `label`.
3. `UI/Theme/Theme.swift` `agentColor("pi")`: a distinct colour that fits the warm dark palette (e.g. a sage/teal green,
   clearly different from Claude orange, agy blue, Hermes). You MAY edit Theme.swift for this one function only.
4. `Core/Store/ToolPresentation.swift`: map pi's lowercase tools to the same symbols/titles/active titles/details as
   Claude's Read/Bash/Edit/Write/Grep/Glob(find)/LS equivalents (case-insensitive aliases). `bash` detail = command, `read`/`write`/
   `edit` detail = file path (last 2 components), etc. Keep all existing behaviour for other agents.
5. Pickers & lists: `UI/Usage/UsageDashboardView.swift` (add a Pi section like Hermes' — local tokens/cost totals from
   `store.usage?.totals?["pi"]` + sessions with agent "pi"; add "pi" to `knownOrder`), `UI/Usage/UsageRing.swift`,
   `UI/Multi/CompareView.swift`, `UI/Multi/CompareSheet.swift` (agent list + default selection stays claude/agy/hermes/pi),
   `UI/Multi/HandoffSheet.swift`, `UI/Schedules/SchedulesView.swift` (agent picker), the new-session/model picker in `UI/Composer`
   and `UI/Sidebar` + `UI/Settings` (agent filters, badges, labels, colours, effort pickers: Pi's efforts come from the
   catalog like Claude's — make sure effort UI shows for Pi models that have efforts and hides it for those without),
   `UI/Chat` (anything switching on agent for image attach, interrupt, permissions UI hidden because supportsPermissions false).
6. Slash-command menu: Pi's `commands` come in the catalog (kind "skill"/"command"/"prompt"); make sure the composer's `/` menu
   shows them for Pi like for agy/hermes and inserts `/<name>` verbatim.
7. `App/DebugLaunch.swift`: add Pi to the fixture agents (one model `meta-ai/muse-spark-1.3-contributor`, efforts) so `[shots]`
   builds show it. `Resources/Fixtures/screenshot-fixture.json`: only add a pi agent entry if it is a pure data addition.
8. `scripts/make-source.py` / README text: mention Pi next to the other agents.
Do NOT add network code, new packages, or mock data in production. Keep iOS 26 / Swift 5 mode / existing style. You cannot
compile (no Mac) — be extremely careful: exhaustive `switch` statements over `AgentKind` must all gain the `.pi` case; re-grep
for `switch` on `AgentKind`/agent strings at the end; check every edit for balanced braces and real symbol names by reading
the files you depend on. Only touch iOS/doc files; another agent edits `bridge/` at the same time.
Final message: list each file changed with one line, plus the exhaustive-switch grep proving none was missed.
