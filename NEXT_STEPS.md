# Next steps

Actionable pending work, as of the end of the session that wrote `HISTORY.md`. Read that
file first for context on *why* each of these is in the state it's in.

## PA voice agent — Phases A–D done

**Phases A+B confirmed working by the user's own hand**: "I tried it, it is working.
Two way communication is working and it starts the Pomodoro." Manual push-to-talk,
real speech in, a real spoken reply out, the `start_pomodoro` tool actually firing.

See `HISTORY.md` §22 (Phase A: push-to-talk, one tool, text reply), §24 (Phase B: spoken
replies via Piper), and §26 (Phase C: continuous "Hey Jarvis" mode) for the full build.
Recurring gotchas worth not rediscovering: `claude -p` needs `--system-prompt` (not
`--append-system-prompt`) and `--allowedTools` for non-interactive tool permission
(§22); a wake-word listener orphan can survive `omarchy-restart-shell` and needs
`SIGKILL`, not `SIGTERM`, to reliably stop (§26).

- **Say "Hey Jarvis" out loud (a real human voice, not synthesized speech) and speak a
  real follow-up command in one breath** — Phase C's wake-word detection and turn
  mechanics were verified with real acoustic loopback (a speaker playing a clip, picked
  up by the actual mic) and are confirmed working end-to-end including a real
  `start_pomodoro` call, but every test this session used Piper-synthesized speech for
  the follow-up command specifically (no human available during automated testing) —
  see `HISTORY.md` §26 for why the resulting mis-transcriptions ("start the motor
  wheel", "start to promote the room") are a TTS-diction artifact, not a real concern,
  but real human speech through the *wake-triggered* path specifically hasn't been
  tried yet (only through the manual push-to-talk path, which the user already
  confirmed).
- **Confirm `piper-tts` actually installed from AUR and remove the temporary
  `~/.local/bin/piper-tts` shim** (a `pip install --user piper-tts` symlinked to that
  name, used to verify the pipeline while the AUR package's sudo step was pending) —
  `which piper-tts` should resolve to `/usr/bin/piper-tts` once the real package is in;
  if it still shows `~/.local/bin/piper-tts`, either the AUR install didn't finish or
  `$PATH` ordering needs a second look. Removing the shim isn't required for anything to
  keep working (`/usr/bin` precedes `~/.local/bin` on `$PATH` here), but it's stale
  clutter once the real package exists. `openwakeword`/`sounddevice` are also currently
  only `pip install --user`-installed, not packaged system-wide — fine as-is (both are
  pure-Python-plus-ONNX, no compiled-extension fragility like Piper's build), just
  worth knowing where they live if this ever moves to a different user/machine.
- **Confirm the mic mute toggle actually gates the C-Media device**, not just that the
  device works — toggle `MicState`'s on/off (Settings page) and watch
  `pactl list sources` / a capture-level meter while it's off, to be sure `setMic`
  really controls this same audio path and not something unrelated.
- **A real "Hey Foxy" wake word still needs Google Colab training** (see `HISTORY.md`
  §26) — "Hey Jarvis" is a deliberate stand-in, not the final phrase. This needs the
  user to actually go run openWakeWord's training notebook (a Google account, a browser
  session, real time) whenever they want the real phrase; swapping the trained model in
  afterward is a one-line change in `wakeword.py`.
- **The fixed 6-second recording window for wake-triggered turns is untuned** — see
  `HISTORY.md` §26 for why it's fixed-duration rather than silence-detected. Worth
  adjusting `CONTINUOUS_TURN_MS` (env-overridable) once real usage shows whether 6s is
  too short (cutting off longer requests) or too long (awkward dead air after a short
  one).
- **Phase D — Home Assistant control — done, verified against the user's real
  instance** (see `HISTORY.md` §29): `list_ha_entities`/`propose_ha_action`/
  `confirm_pending_action`/`cancel_pending_action`, scoped to lights/switches/climate/
  locks, gated by a code-enforced `OQP_PA_TURN_ID` check (not just a prompt) so a single
  `claude -p` turn can never propose and confirm an action in one shot. One real device
  in the user's own setup returned an HTTP 500 from Home Assistant's own backend on an
  ordinary `turn_on` call — confirmed as that specific entity/integration's own issue,
  not a bug here, but worth knowing if it recurs; a different entity of the same domain
  worked cleanly right after.
- **Real spoken smart-home requests haven't been tried yet** — Phase D was verified via
  raw MCP protocol calls and real `claude -p` conversations driven from a terminal, not
  by actually saying "turn on the living room light" out loud to the panel. Worth doing
  once, same shape as every other "confirmed via a scripted call, not a human" item here.
- **Cost/latency of `claude -p` per turn is real and untuned**: a trivial one-line reply
  during this session's testing cost roughly $0.02–0.05 and took several seconds
  end-to-end (`claude-haiku-4-5` was already chosen specifically to keep this down
  versus the default Sonnet), and Piper synthesis adds its own real time on top (a ~2s
  reply took a noticeable moment to render before `paplay` even started). Worth keeping
  an eye on now that continuous mode (Phase C) can trigger turns without a deliberate
  button press.
- **`ALLOWED_TOOLS` in `daemon/src/paBridge.js` needs a new entry every time a new MCP
  tool is added** (Phase D's Home Assistant tools especially) — easy to forget, and the
  failure mode (a silent `permission_denials` entry, the model apologizing that it
  "isn't connected") looks like a connection bug rather than a missing allowlist entry.
  See `HISTORY.md` §22 if this happens again.
- **`OQP_PA_SPEAKER_SINK` is hardcoded to this laptop's exact ALSA sink name** — a
  different machine (or this one after a hardware change) needs its own value from
  `pactl list short sinks`, either via that env var or by editing `paBridge.js`'s
  default.

## Touch leaking to the main screen — RESOLVED for kiosk mode

**Fixed and confirmed by the user's own hand**: the virtual touch device is now only
created in "desktop" mode (verified via `/proc/bus/input/devices` — zero entries in
kiosk mode, appears/disappears exactly on mode toggle). This app's own kiosk UI never
used that device for anything, so removing it in kiosk mode removed the only mechanism
that could ever have leaked touch to the main screen — an architectural elimination, not
a configuration guess, and the user confirmed the scrolling is gone after dragging a
Settings slider. See `HISTORY.md` §15–§18 for the full diagnostic trail (multiple
Hyprland-level fixes tried and confirmed *not* to work, including a full logout/login,
before this approach worked). One thing remains genuinely open:

- **The underlying Hyprland-level question — why its own documented per-device *and*
  global touch-output binding, both confirmed correctly applied, never actually
  confined this device — was never answered**, and no longer needs to be for kiosk mode
  to work correctly. It remains open for **desktop mode** specifically, which still
  creates the virtual device (it's genuinely needed there, for ordinary windows to
  receive touch) and hasn't been retested against this exact symptom. If the same
  leak-to-main-screen behavior ever shows up while in desktop mode, `HISTORY.md`
  §16/§17 is the reference for what's already been ruled out — don't re-try the
  per-device or global Hyprland binding fixes, both are confirmed dead ends on this
  machine's Hyprland version.
- **A harmless side artifact from the investigation, kept**: `hl.device({name=
  "hotlotus-wcidtest-mouse", enabled=false})` in `~/.config/hypr/input.lua` and
  `ops/hyprland/input.example.lua`. It turned out not to be the cause (confirmed via a
  direct kernel-level read: zero events from it during a live drag), but disabling a
  device with no legitimate use for this project is reasonable regardless.
- **Important caveat on this project's own track record, worth remembering for any
  future touch work**: every "confirmed working" claim made while building the Settings
  page and its sliders used a temporary debug hook calling touch-handling code directly
  in software (`TouchRouter.feed()` invoked from an IPC method, or a service function
  called directly). That path never touches the real `uinput → kernel → libinput →
  Hyprland` chain this whole bug lived in — nothing in that testing could have caught
  it, regardless of when it actually started. Treat any "touch confirmed" note from that
  work as validating only this app's own internal dispatch, not real hardware delivery,
  unless it explicitly says a human touched the panel.

## Plugin conversion (done, pending real hardware + a git push)

- **`omarchy plugin disable`/`enable` does NOT reload changed QML from disk** — confirmed
  live while adding the Pomodoro/Stand reset buttons: editing files under
  `~/.config/omarchy/plugins/srk78.quake-panel/` and then disabling/re-enabling kept
  serving an old cached version. Only a genuine file *write* under that directory (which
  fires Quickshell's own "Local plugin changed, reloading" watcher) or a full
  `omarchy-restart-shell` reliably reloads real code changes — and even the file-watcher
  path can race with the OLD daemon process still holding the HID device if something
  else (e.g. a leftover standalone dev instance) is also touching it at the same moment.
  When in doubt after editing an installed plugin's files, `omarchy-restart-shell` is the
  one command that's actually guaranteed clean. This will stop mattering once the
  standing "push + reinstall via `omarchy plugin add`" item below happens, since a fresh
  `add` always clones fresh rather than reusing a running cache.
- **Push `manifest.json`, `shell/Service.qml`, and `ops/` to GitHub**, then reinstall via
  the real path — `omarchy plugin remove srk78.quake-panel` (the manual test copy at
  `~/.config/omarchy/plugins/srk78.quake-panel/`), then `omarchy plugin add
  https://github.com/srk78/omarchy-quake-panel.git --enable`. The manual copy works today
  but isn't git-managed (`omarchy plugin update` can't fast-forward it), and its
  `daemon/node_modules` was hand-synced rather than `npm install`ed in place.
- **Physically hold the knob for ~3 seconds** to confirm the mode toggle actually fires
  from real hardware, not just the IPC call — this session verified the IPC/CLI/timer
  logic but has no way to simulate a physical hold.
- ~~Re-verify touch while loaded as the real plugin~~ — confirmed: the touch-leaking-to-
  main-screen investigation (see the top section, `HISTORY.md` §15–§18) exercised real
  physical touch on the real plugin extensively, including the Settings sliders. Still
  worth a specific tap on the Self Care buttons and water picker options at some point,
  since those weren't the exact controls tested, but the `TouchRouter` path itself is
  now confirmed working correctly as the real plugin.
- **Migrate `Services/Theme.qml` / `Ui/Card.qml` / `SectionLabel.qml` / `SectionSeparator.qml`
  / `PageHeader.qml` onto real `import qs.Commons` (`Color`, `Style`) and Omarchy's own
  `Ui/PopupCard.qml` / `PanelSectionHeader.qml` / `PanelSeparator.qml` / `PanelHero.qml`**
  — confirmed genuinely reachable now that `shell/Service.qml` loads inside `omarchy-shell`
  (see `HISTORY.md` §7), but deliberately not done in the same pass as the plugin
  conversion itself. This also removes the 3-second theme-file poll in favor of the
  shell's real in-process theme push. Needs its own `capture-panel.sh` screenshot review
  like every prior styling pass — and note `Pages/*.qml`/most of `Ui/`/`Services/` are
  still shared with the standalone `shell/shell.qml` dev entry point, which genuinely
  cannot use `qs.Commons` (see `project-styling-notes.md`), so this migration has to
  either accept that `shell.qml`'s dev loop stops matching production exactly, or grow a
  small compatibility shim.
- Update `.claude/skills/omarchy-design/scripts/capture-panel.sh` if useful to also
  support capturing while loaded as the real plugin (today it only drives the standalone
  `shell.qml` path) — not attempted this session.

## Top-bar mode dropdown (new, done pending a real mouse click — `HISTORY.md` §20)

- **Click the bar icon and a dropdown row with an actual mouse** — this session verified
  the widget loads with no errors and that its icon correctly tracks `mode` (toggled via
  IPC, diffed before/after screenshots), but this machine has no pointer-click
  simulation tool (`ydotool`/`wlrctl`/`dotool` all absent), so `PopupCard`'s open/close
  and the row `MouseArea`'s `onClicked: root.service.setMode(...)` were verified by
  reading the code against `omarchy.media`'s own working equivalent, not by a live
  click. Low risk (nothing bespoke, same base components dozens of first-party widgets
  use) but genuinely untested.
- If this plugin is ever converted from a service-only install to also declare
  `bar-widget` again elsewhere (a fresh machine, a reinstall), remember `HISTORY.md`
  §20's first gotcha: a leftover top-level `plugins: [{"id": "srk78.quake-panel"}]`
  entry in `shell.json` makes `omarchy plugin enable ... --section right` report success
  while placing nothing. Remove that entry before enabling the bar-widget kind.
- Any other icon choice made from a codepoint's *name* rather than an actual render
  against the live font (JetBrainsMono Nerd Font here, confirmed via `fc-match
  monospace` — not necessarily the same font other checks in this project used) carries
  the same latent risk `HISTORY.md` §20 found and fixed for this widget's own icons. Not
  re-audited this session: any icon glyph chosen in an earlier session purely from a
  cmap-presence check rather than an actual screenshot.

## Settings page / knob RGB ring / mic toggle (new, done pending a physical look)

- **Physically look at the knob's ring** after picking a color on the Settings page —
  this session verified the full round trip at the firmware level (set a color, restart
  the shell fresh, and `getLighting()` genuinely read the same value back from the
  device), but there is no camera on this hardware, so nobody has actually confirmed the
  ring itself renders as a stable solid color rather than, say, continuing to animate.
  Same caveat for "None": confirmed `setLedEffect(0)` round-trips correctly (and,
  incidentally, the ring's real state was already off with a stale color when this was
  tested, which is exactly the case the current-detection fix needed to handle), but
  nobody has looked at the physical ring to confirm it actually goes dark.
- **Physically confirm the microphone toggle actually mutes/unmutes** — the query/set
  round-trip was verified against the device's own reported state (toggled off, queried
  back as off; toggled back on before finishing), but nothing in this session could
  confirm audio is actually captured or blocked, only that the device acknowledges the
  on/off flag.
- **Physically look at the ring while dragging the Knob Light Brightness slider** — the
  round-trip (drag to a value, full restart, `getLighting()` reads back a
  quantized-but-close value) is confirmed at the firmware level, same as color; nobody
  has looked at the actual ring to confirm brightness visibly changes, or that a low
  value is dim rather than, say, imperceptible or unchanged.
- **Physically look at the screen while dragging the Screen Brightness slider** — same
  situation as the ring: `setBrightness`/`queryLuminance`'s software round-trip is
  confirmed (drag to a value, read the same value back), but a `grim` screenshot
  fundamentally cannot show a backlight change (it captures the rendered framebuffer,
  not the physical light output), so nobody has confirmed the screen actually dims.
  Screen brightness also has no `saveLighting`-equivalent persist command in the driver
  — worth confirming whether it survives a power cycle at all, or always resets.
- **The mic was found off at the start of the brightness/layout session**, despite being
  explicitly restored to on at the end of the previous one — restored to on again before
  finishing, but nothing in either session explains why it didn't hold. Worth a glance if
  it happens again: either the device doesn't persist mic state the way ring lighting
  does (no `saveLighting`-equivalent exists for it in `Aris68Connector.js`), or something
  else reset it between sessions.
- **`KnobLighting.solidColorEffect` (currently `1`) is inferred from QMK convention, not
  verified against this exact firmware's effect list** — `Aris68Connector.js`'s own
  comment only documents effect indices as "0=All Off … 43 (RGB-Matrix list)", no names.
  If a chosen preset doesn't look like a stable solid color on the real ring (animates,
  cycles, etc.), this is the constant to revisit — see `shell/Services/KnobLighting.qml`'s
  own header comment.
- **`qmllint` did not catch a real load-time error** ("Cannot assign to non-existent
  default property" from a bare `Connections {}` under a `QtObject`) — see `HISTORY.md`
  §9. Worth remembering for any future `QtObject`-rooted service: give every non-visual
  child an explicit `property` name, and don't trust `qmllint` alone before a real
  `omarchy-restart-shell` load.
- **`TouchRouter.registerDrag` has only ever been exercised by synthetic, direct
  `feed()` calls** (a temporary debug hook, reading real on-screen bounds and feeding a
  real multi-point sequence through the actual dispatch code — see `HISTORY.md` §13) —
  never by an actual finger. The underlying touch delivery mechanism is the same one
  every tap in this app already relies on, so no new risk is expected, but a real drag
  on both sliders is still worth doing at least once.

## Styling (done, pending two physical checks — carried over from the prior session)

- **Physically re-verify touch** on the Self Care Start/Pause and Log water buttons. They
  are now `Ui/PanelButton` instances that register themselves with `TouchRouter`; the
  wiring is equivalent to before, but only a real tap proves it. (Now folded into the
  plugin-conversion re-verification above, since the window is drawn differently.)
- **Eyeball the water picker and the reminder toast** on the panel (hold the knob briefly
  — under 3s, or it'll trigger the new mode toggle instead — or wait for a reminder).
  Both were restyled from verified source (`HISTORY.md` §5a) but could not be triggered
  from the screenshot script, so they are the only surfaces not captured.
- Tune `Theme.scale` (currently 1.5) if the text reads too big or small at the real
  viewing distance — it is the single knob for both font and spacing.
- The System page's `Sparkline` line/fill colors still use flat `theme.accent` — not flagged
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
- **The Home Assistant *dashboard* page is on hold**, not abandoned — don't confuse this
  with FOXY's Home Assistant *control* (`HISTORY.md` §29), which is real and done.
  `shell/Pages/HomeAssistantPage.qml` (a different, embedded-web-view approach for
  *viewing* the HA dashboard itself) still can't use `WebEngineView` (crashes Quickshell
  — see `HISTORY.md` §3/§4). The only viable path identified so far is an **external
  kiosk browser window** that this shell yields focus/space to, rather than embedding a
  web view directly — this hasn't been designed or attempted yet.

## Suggested order if resuming cold

1. Push the plugin files and reinstall via `omarchy plugin add` for real, then physically
   confirm the knob long-hold, both sliders, and the ring's actual color on real
   hardware (see Plugin conversion and Settings page above) — this is the only remaining
   gap between "built and IPC-tested" and "actually done." (Touch itself is now
   confirmed working correctly in kiosk mode — see above.)
2. The `qs.Commons`/`qs.Ui` styling migration, since it's now unblocked and was the
   biggest standing style debt in the project.
3. Pick one of: config.json wiring or the Home Assistant external-window approach —
   whichever the user most wants next.
