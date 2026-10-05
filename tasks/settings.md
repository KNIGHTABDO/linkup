Linkup settings: pairing (link/QR/manual), settings sheet, usage dashboard [shots]

## Your files (only these)
- `ios/Linkup/UI/Settings/SettingsViews.swift` (replace stubs; keep `SettingsView()`, `ConnectView()`, `UsageView()`)
- you may add more files under `ios/Linkup/UI/Settings/`

## ConnectView ("Connect to your PC")
Shown on first launch. Big `SparkView(size: 56, animating: true)`, title "Link up your agents" (Theme.serif 30),
subtitle "Run `python -m linkup_bridge pair` on your PC and scan the code." (Theme.sans 16 secondaryText, the
command in mono in a rounded box with a copy button).
- Primary: "Scan pairing code" (`.buttonStyle(.glassProminent)`, accent) → camera QR scanner using
  `DataScannerViewController` (VisionKit, `recognizedDataTypes: [.barcode(symbologies: [.qr])]`) wrapped in a
  UIViewControllerRepresentable; when a `linkup://pair?...` payload is found → `settings.apply(pairingLink: url)`,
  `client.connect()`, dismiss (`ui.isShowingConnect = false`). Check `DataScannerViewController.isSupported/isAvailable`
  and fall back to a message.
- "Paste link" button: reads `UIPasteboard.general.url` or string, applies it the same way.
- Manual section (DisclosureGroup "Enter manually"): Server URL field (placeholder
  "https://your-pc.tailnet.ts.net"), Token SecureField, "Connect" button → set `settings.serverURL`/`settings.token`,
  `client.connect()`; show live `client.state.label` underneath with a status dot; when `.connected` show a
  checkmark and close after 0.8 s.
Background Theme.background, content centered, max width 520.

## SettingsView (sheet, Form `.insetGrouped`, `.scrollContentBackground(.hidden)`, background Theme.surface)
- "Connection": server URL, status (dot + label + latency), "Reconnect" (client.connect()), "Pair again"
  (ui.isShowingConnect = true), "Disconnect" (client.disconnect()).
- "Agents": one row per `store.agents`: symbol, name, status (Available / error text), model count, account label;
  "Refresh agents" → `await store.refreshCatalog(force: true)`.
- "Usage" → NavigationLink to `UsageView()`.
- "About": app version from Bundle, "Bridge on <serverName>".
Glass xmark close top-left, title "Settings".

## UsageView ("Usage")
Real numbers only from `store.usage` (UsageSnapshot) and `store.sessions`:
- **Claude plan** card (if `usage.claude` exists): two big rings or bars: "Current session" = `fiveHour.utilization`
  (0…1 → %) with "Resets in 2 h 14 min" from `fiveHour.resetDate`, and "Weekly" = `sevenDay`; color shifts to
  accent above 80% and danger above 95%; status text from `claude.status` ("allowed", "allowed_warning" → "Close to
  the limit", "rejected" → "Limit reached"). Account label from `store.agent("claude")?.accountLabel`.
  If no rate limit has been seen yet: "Send a message with Claude Code to see your plan usage."
- **Per agent** cards from `usage.totals[agentId]`: input/output tokens (formatted 12.3k / 1.2M), sessions count,
  cost in USD when > 0 (Claude Code reports cost equivalents).
- **Top sessions** by tokens: list of the 8 sessions with the most `usage` (input+cacheRead+cacheWrite+output),
  each with agent icon, title, tokens.
- Pull to refresh → `await store.refreshCatalog(force: false)`.
Glass xmark close, title "Usage", background Theme.surface, numbers animate with `.contentTransition(.numericText())`.
