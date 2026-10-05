Linkup scheduled prompts UI [shots]

## Your files (only these): new files under `ios/Linkup/UI/Schedules/`.
## Views (Claude wires entry points)
1. `SchedulesView()`: list from `try await store.schedules()` (.task + pull to refresh): each row AgentLogo, title,
   "Every day at 08:00" / "Mon, Wed, Fri at 18:30", next run relative ("in 3 h"), an enabled Toggle (saves via
   `store.saveSchedule` with enabled flipped), swipe to delete (`store.deleteSchedule`), context menu "Run now"
   (`store.runSchedule` → open the returned session via `ui.currentSessionId`). Toolbar "+" → editor. Empty state with
   examples ("Summarize my repos' CI every morning", "Daily news briefing with cards").
2. `ScheduleEditor(schedule: ScheduleInfo?)`: title, agent (AgentLogo segmented), model (from catalog), project
   (store.projects, optional), prompt TextEditor, time (DatePicker hourAndMinute → "HH:MM"), days (7 round toggle
   chips M T W T F S S; none = every day), enabled; Save → `store.saveSchedule` (new: id = "" — the bridge assigns it).
   Glass xmark, Theme.surface.
