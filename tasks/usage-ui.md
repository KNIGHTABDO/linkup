Linkup usage dashboard v2: live plan usage for Claude Code and Antigravity [shots]

## Your files (only these)
- `ios/Linkup/UI/Settings/SettingsViews.swift` — ONLY the `UsageView` type (rewrite it fully; leave SettingsView and
  ConnectView untouched), plus new files under `ios/Linkup/UI/Usage/`.

## Build (real data only, updates live — the bridge pushes `usage` every minute; views observe `store.usage`)
- **Claude plan** (`store.usage?.claudePlan`, fall back to `store.usage?.claude` when nil): four rings in a 2×2 grid —
  "5-hour session" (fiveHour), "Weekly" (sevenDay), "Weekly · Opus" (sevenDayOpus, only if present), "Weekly · Sonnet"
  (sevenDaySonnet, only if present); each ring animates to its value, center % with numericText, caption
  "Resets in 2 h 14 min" from resetDate using a live `TimelineView(.periodic(from: .now, by: 30))` countdown; colors:
  ivory < 50 %, accent < 80 %, `#E8B04B` < 95 %, danger ≥ 95 %. Subscription label (`claudePlan.subscription`).
  "Updated 12 s ago" (live) from `claudePlan.at`.
- **Antigravity** (`store.usage?.agy`): card with AgentLogo, the credits text exactly as reported (`credits`, e.g. "Out of
  credits" in danger color, or the number), status, per-model quota bars when `models` non-empty (name, remaining %,
  reset time), updated-ago label. When nil: "Antigravity usage appears after the bridge's next check".
- **Hermes**: tokens from `usage.totals["hermes"]`.
- **Per agent totals** (existing): keep, but with AgentLogo, animated numbers, and a small bar chart (Swift Charts) of
  tokens per day for the last 7 days computed from `store.sessions` (bucket each session's total tokens by its
  `updated` day — label it "by last activity").
- **Top sessions** (keep) with AgentLogo.
- Pull to refresh → `await store.refreshCatalog(force: false)`.
- Also create `ios/Linkup/UI/Usage/UsageRing.swift`: `struct UsageRingBadge: View { let utilization: Double?; var size: CGFloat = 18 }`
  — a tiny circular progress ring (stroke 2.5) colored by the same thresholds, for the composer's model pill
  (Claude will wire it). And `UsageAlertWatcher` (ViewModifier `.usageAlerts()`): when Claude's 5-hour utilization
  crosses 0.8 or 0.95 (once per reset window, remembered in UserDefaults by resetsAt) set `ui.toast` to
  "Claude: 80 % of your 5-hour limit used" etc. (Claude will attach it to RootView.)
