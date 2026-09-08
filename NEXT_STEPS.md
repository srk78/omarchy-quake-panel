# Next steps

Actionable pending work, as of the end of the session that wrote `HISTORY.md`. Read that
file first for context on *why* each of these is in the state it's in.

## Styling (in progress, mostly done)

- The `omarchy-design` skill's corrections were applied to `DashboardPage.qml` and
  `PersonalCarePage.qml` and verified via a real capture (see `HISTORY.md` §5). **Not yet
  reconfirmed**: that real touch (not just mouse/dev-testing) still reliably triggers the
  Personal Care page's Start/Pause and Log water buttons after the restyle — the
  `TouchRouter.registerTap`/`unregisterTap` wiring wasn't touched, but a physical-hardware
  re-check is the only real proof and hasn't happened since these edits.
- **`ToastOverlay.qml` and `WaterAmountPicker.qml` still use the old flat
  `theme.surfaceBorder`** — explicitly out of scope for the last restyle request ("the
  personal care page and the stats page" only). Worth a follow-up pass to bring them onto
  `controlBorderColor`/`separatorColor`/`secondaryForeground` for full consistency.
- The Dashboard's `Sparkline` line/fill colors still use flat `theme.accent` — not flagged
  as wrong by the omarchy-design conventions doc (sparkline color isn't a
  border/separator/text case), but worth a second look if a future pass wants graphs to
  read as more "themed" rather than a single accent hue.
- `omarchy-design` is currently **project-scoped** (`.claude/skills/omarchy-design/`), so
  it only auto-discovers in sessions rooted inside this repo (confirmed: a session rooted
  in the sibling `bedrock-panel` repo couldn't find it via the `Skill` tool). If it should
  be usable from anywhere, move it to `~/.claude/skills/omarchy-design/` (same place the
  built-in `omarchy` skill lives) — not done yet, pending a decision on whether that's
  wanted.

## Functionality not yet built

- **`config/config.example.json` wiring** — `PersonalCareState.qml`'s thresholds (pomodoro
  durations, stand interval, ml presets) are still hardcoded in the QML rather than read
  from a real user config file.
- **systemd autostart units** — nothing currently starts the daemon + `quickshell -p
  shell/shell.qml` automatically on login/boot; both are launched manually today (or via
  `.claude/skills/omarchy-design/scripts/capture-panel.sh` for dev/verification).
- **Home Assistant page is on hold**, not abandoned. `shell/Pages/HomeAssistantPage.qml`
  exists but can't use `WebEngineView` (crashes Quickshell — see `HISTORY.md` §3/§4). The
  only viable path identified so far is an **external kiosk browser window** that this
  shell yields focus/space to, rather than embedding a web view directly — this hasn't
  been designed or attempted yet.

## Suggested order if resuming cold

1. Physically re-verify touch on the two Personal Care buttons post-restyle (quick, high
   confidence check).
2. Pick one of: config.json wiring, systemd units, or the Home Assistant
   external-window approach — whichever the user most wants next — rather than
   continuing incremental styling polish, since the three built pages/features are
   functionally complete and visually consistent as of this write-up.
