# Next steps

Actionable pending work, as of the end of the session that wrote `HISTORY.md`. Read that
file first for context on *why* each of these is in the state it's in.

## Styling (done, pending two physical checks)

- **Physically re-verify touch** on the Self Care Start/Pause and Log water buttons. They
  are now `Ui/PanelButton` instances that register themselves with `TouchRouter`; the
  wiring is equivalent to before, but only a real tap proves it.
- **Eyeball the water picker and the reminder toast** on the panel (hold the knob, or wait
  for a reminder). Both were restyled from verified source (`HISTORY.md` §5a) but could not
  be triggered from the screenshot script, so they are the only surfaces not captured.
- Tune `Theme.scale` (currently 1.5) if the text reads too big or small at the real
  viewing distance — it is the single knob for both font and spacing.
- The Dashboard's `Sparkline` line/fill colors still use flat `theme.accent` — not flagged
  as wrong by the omarchy-design conventions doc, but worth a second look if a future pass
  wants graphs to read as more "themed" than a single accent hue.
- `omarchy-design` is currently **project-scoped** (`.claude/skills/omarchy-design/`), so
  it only auto-discovers in sessions rooted inside this repo. If it should be usable from
  anywhere, move it to `~/.claude/skills/omarchy-design/` — pending a decision on whether
  that's wanted.

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

1. Physically re-verify touch on the two Self Care buttons and glance at the water
   picker/toast (quick checks, see Styling above).
2. Pick one of: config.json wiring, systemd units, or the Home Assistant
   external-window approach — whichever the user most wants next — rather than
   continuing incremental styling polish, since the three built pages/features are
   functionally complete and visually consistent as of this write-up.
