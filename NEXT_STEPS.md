# Next steps

Actionable pending work, as of the end of the session that wrote `HISTORY.md`. Read that
file first for context on *why* each of these is in the state it's in.

## Foxy's Hermes latency fixed: warm gateway HTTP API, not a cold CLI — done

See `HISTORY.md` §42. Root-caused the reported ~30s Foxy latency (vs. Signal/Telegram's
own much faster replies): the `hermes chat --oneshot` CLI call itself hung for 24-99s
*after* already producing the correct answer, fighting the already-running Hermes
gateway daemon over shared local state. Fixed by having `askHermes()` talk directly to
that gateway's own documented HTTP API Server instead (`POST`/poll `GET
/p/foxy/v1/runs/...`) — the same warm process Signal/Telegram already use. Verified live:
full turns (including a real multi-turn session-continuity check) now complete in
7-10 seconds, down from 30-100+; cancel and the Claude-fallback path both still work
exactly as before.

- **Signal/Telegram were never literally instant either** — cross-checked the gateway's
  own logs and found their real response times run 5-20+ seconds depending on tool-call
  complexity, the same honest range Foxy now sees. The fix eliminates the CLI-specific
  overhead on top of that, it doesn't (and can't) make the underlying ~35B local model
  itself instant.
- **A real secret exposure happened this session, not a code bug**: diagnosing why the
  API server wouldn't start required reading the Pi's `~/.hermes/.env`, which printed
  real Signal/Slack/Telegram bot tokens into the assistant's context. Nothing was
  written anywhere from it, but **the user may want to rotate those credentials** as a
  precaution.
- `OQP_PA_HERMES_API_HOST`/`_PORT`/`_PROFILE`/`_TIMEOUT_MS` are env-overridable but
  default to this specific Pi/profile — a different machine needs its own values. The
  API key itself lives in `~/.config/omarchy-quake-panel/config.json`'s new
  `hermes.apiKey` field (outside git, matching the existing Home Assistant credential
  convention), not an env var.
- The gateway's `/v1/runs/{id}/stop` cancel call is fire-and-forget (matches this
  project's existing "best-effort" stance elsewhere) — not independently confirmed
  server-side that a cancelled run's inference actually halts immediately on the Mac
  Studio, only that Foxy's own UI stops waiting/listening for it correctly.

## Stop-Foxy control moved to the header's pulsing dot — done

See `HISTORY.md` §41. The top-right icon on the particle-cloud block is gone; tapping
the pulsing "continuous listening" dot in the shared page header now stops Foxy
instead, via a real (comfortably-sized, invisible) hit-area around the visually
unchanged tiny dot. Verified live end-to-end, not just by code review: a synthetic
touch point fed through the actual `TouchRouter.feed()` path confirmed the tap genuinely
turns Foxy off, and does nothing while the dot is already hidden (Foxy off). A real
Row-layout bug (anchoring a child to a sibling inside a `Row` silently breaks the
WHOLE row, not just that child) was caught live and fixed along the way — `qmllint`
stayed clean throughout, another instance of the load-time-only gap `HISTORY.md` §9
already documented.

- Nothing outstanding from this pass.

## FOXY transcript: touch scroll-back, speech-paced reveal, off icon's real home — done, one gap remains

See `HISTORY.md` §40. The transcript can now be scrolled back by touch (`TouchRouter.
registerDrag`, the same pattern `Ui/Slider.qml` already uses); a `pinnedToBottom` flag
means new content never yanks the view away from a manual scroll-back; and a long Foxy
reply is now revealed at the pace of real speaking time (a new `speakingStarted` wire
message carrying the already-known audio duration) instead of snapping to the bottom
the instant its text is appended. The off icon now sits on the particle-cloud block's
own top-right corner, not the conversation block's (superseding §39's placement).

Two real bugs were found and fixed only by testing against the actual panel, not
assumed from the code: recomputing `pinnedToBottom` on every content-height change
(including a Foxy reply's own not-yet-scrolled growth) silently disabled the paced
reveal on every single turn; and a 5-second "Piper failed" fallback timer was firing
during perfectly ordinary synthesis of a long reply (bumped to 30s).

- **Touch-drag scrolling itself was verified by code review and by matching
  `Slider.qml`'s already-hardware-proven `registerDrag` pattern, not by an actual
  finger on the panel** — worth a real touch test at some point, though the underlying
  mechanism (`TouchRouter.registerDrag`/`feed()`) is exactly what every other touch
  control in this app already relies on in production, so no new risk is expected.

## FOXY page: auto-scroll, top-right off icon, answer-time caption — done

See `HISTORY.md` §39. All three verified live with real screenshots against the actual
panel: the transcript now genuinely settles at the bottom even for long, multi-line-
wrapping replies (a second `onContentHeightChanged` scroll trigger, not just
`onCountChanged`); "Turn Foxy off" is now a compact top-right icon via a new, reusable
`Ui/Section.qml` `headerTrailing` slot (also fixed a real layout bug found only by
screenshotting: a full-size touch button centered on the label row still overhung into
the content area — the header row now genuinely grows to fit it); and each Foxy reply
shows a small "3.2s"-style caption for how long the "thinking" phase took, honestly
including a failed Hermes attempt's own wait when it fell back to Claude.

- Nothing outstanding from this pass — `PersonalCarePage.qml`/`SettingsPage.qml`'s
  existing `Section` usage was screenshot-confirmed unaffected by the `headerTrailing`
  addition.

## Foxy's brain moves to Hermes over Tailscale, Claude fallback — done, two real gaps remain

See `HISTORY.md` §38. `askHermes()` (SSH + the `hermes` CLI against a dedicated `foxy`
profile on the user's self-hosted Pi) is now Foxy's primary brain; `askClaude()` — kept
completely unmodified — is the fallback whenever Hermes is unreachable, with its reply
audibly prefixed so a fallback is never silent. Verified live end-to-end: real replies
from the real Hermes instance, session continuity across turns via `--resume`, a clean
knob-press cancel (including a real gotcha found and fixed — killing the local `ssh`
client does NOT kill the remote `hermes` process, needed a second targeted `pkill` over
SSH), and the fallback itself forced with a genuinely unreachable host.

- **No tools wired into Hermes yet, by explicit choice this pass** — pomodoro-by-voice,
  `remember_fact`/`forget_fact`/`list_remembered_facts`, and Home Assistant control only
  work while Foxy is in the Claude-fallback state; the Hermes primary path is
  conversation-only. Hermes' own CLI mentions `hermes mcp serve` (exposing Hermes' own
  conversations as an MCP tool to something else — the reverse direction from what would
  be needed here), so this isn't a ready-made answer. Revisit once there's a known way to
  register outside tools with Hermes — worth checking `website/docs/user-guide/features/
  api-server.md` in the `NousResearch/hermes-agent` repo first (an "API Server" feature
  surfaced while researching this, not investigated in depth since the SSH+CLI path was
  already working well by the time it came up).
- **Not yet tried with a real human voice** — everything above was verified through a
  temporary debug IPC hook bypassing `startTurn()`/Voxtype (removed before finishing, same
  pattern §37 used), not a real "Hey Foxy" + spoken follow-up. The turn-loop plumbing
  itself (`startTurn`/`endTurn`/`finishTurn`) is completely unchanged by this work, so no
  new risk is expected, but it's worth a real end-to-end pass.
- `HERMES_SSH_HOST`/`HERMES_SSH_USER`/`HERMES_BIN`/`HERMES_PROFILE` are all
  env-overridable (`OQP_PA_HERMES_*`) but currently default to this specific Pi/user/path
  — a different machine (or the Pi's own `hermes` install location changing) needs its own
  values.
- The `foxy` Hermes profile's `SOUL.md` (on the Pi, not in this repo) was hand-written
  once this session by porting this file's `SYSTEM_PROMPT` wording — if that system prompt
  is ever tuned again for the Claude-fallback path, remember the Hermes-side `SOUL.md`
  won't pick up the change automatically; it would need the same edit made twice.

## Six fixes from real use — done

See `HISTORY.md` §34: bar-widget connection status (mode options hidden when the panel
hardware isn't connected, a diagonal strike-through on the icon otherwise), Personal
Care's daily counters now actually roll over with no interaction needed (a periodic
timer, not just a lazy check on the next log/start), a Water Reset button, "nothing
transcribed" no longer shown as a chat error after a quiet wake word, Foxy no longer
says "asterisk" (system-prompt instruction + a code-level markdown stripper before
Piper), and the knob-brightness percentage clamped so it can't show over 100%. All six
verified live on the real hardware/daemon, including a real debugging detour worth
knowing about if the bar widget ever seems unresponsive again: it lives on the right
side of the bar, not the left (§34 has the full story of how a working feature looked
broken for a while because of this).

Testing the mic fix with a genuine physical power cycle (§35) surfaced two more real
bugs no software-only restart could have caught: the kiosk window not re-homing to a
reconnected panel output (fixed, then a real regression in that same fix caught
unplugging the panel and dragging kiosk content onto the main screen — also fixed), and
the knob's chosen color not actually surviving a real power-off at the firmware level
(worked around with a local preference file the app reconciles against the device on
every reconnect). All confirmed working by the user on the real hardware.

## Foxy: persistent memory, knob-press cancel, session reset — done

See `HISTORY.md` §37. `remember_fact`/`forget_fact`/`list_remembered_facts` (backed by
`~/.local/state/omarchy-quake-panel/foxy-memory.json`, passively injected into every
turn's system prompt) verified live end-to-end via real `claude` CLI calls against the
actual installed MCP server — remember, a completely separate fresh-session recall with
no `--resume`, and forget all confirmed working. The knob press now cancels an in-flight
turn instead of always fully toggling Foxy off (`PaState.busy`/`cancelTurn()`,
`daemon/src/paBridge.js`'s new `activeChild`/`turnWasCancelled`) — verified live against
the real daemon that a cancel during "thinking" and during "speaking" both drop to idle
almost instantly with no lingering `paplay`/`piper-tts` process and no spurious error.
Foxy's own conversation session now resets on toggle-off and after a 30-minute idle
timer (`OQP_PA_SESSION_IDLE_RESET_MS`) — both verified live (a debug hook read the
daemon's real in-memory session ID; a temporary second standalone instance with a
4-second override confirmed the idle timer itself actually fires).

- **Everything above was verified through temporary debug IPC hooks and direct `claude`
  CLI calls, not a real human voice** — no live test yet of saying "Hey Foxy, remember
  that I like my coffee black" out loud, letting a later real conversation recall it
  unprompted, or physically pressing the knob mid-reply to interrupt real Foxy-spoken
  audio triggered by an actual wake word. The underlying mechanisms are the same ones
  every other real-voice-verified Foxy feature already relies on (the wake-word
  listener, `speak()`, `KnobRouter`'s existing dispatch), so no new risk is expected, but
  this hasn't been done with a human voice/hand yet the way §33's wake-word work was.
- **No Settings-page UI to browse/edit remembered facts** — deliberately not built this
  pass; `list_remembered_facts`/`forget_fact` already make this manageable by voice, and
  a touch UI can follow later if it turns out to be needed.
- **`SESSION_IDLE_RESET_MS`'s 30-minute default is a guess**, not tuned against real
  usage patterns — worth revisiting once there's a sense of how long a real idle Foxy
  conversation tends to sit before someone comes back to it.

## FOXY's 3D particle visualizer — done

See `HISTORY.md` §30. A real `QtQuick3D`/`Particles3D` cloud on the right 1/5 of the
FOXY page, verified live: renders and idles correctly, and visibly reacts (denser/
larger/brighter) during FOXY's real spoken replies. Needs the `qt6-quick3d` system
package, now installed. Now also confirmed rendering correctly during real wake-word-
triggered turns (§31's redesign testing), since push-to-talk itself no longer exists.

- If a future pass wants the user's own voice to be genuinely audio-reactive too (not
  just an ambient pulse while listening), re-read this section's write-up in
  `HISTORY.md` §30 first — that was a deliberate, user-approved trade-off against
  reintroducing §26's mic-contention flakiness, not an oversight.

## FOXY redesign: one power control, auto-follow-up, scrolling transcript — done, two gaps remain

See `HISTORY.md` §31. The Talk button is gone; `continuousMode` is now the one on/off
control, on-screen and via the knob press — **confirmed working on the real hardware by
the user's own hand**. Foxy auto-listens (skipping the wake word) after asking a
question — verified live twice, real acoustic loopback, both times correctly going
straight to `"listening"` with no wake phrase needed. The transcript is now a real
scrolling `ListView` (`PaState.qml`'s `transcript` `ListModel`), verified live growing
across multiple turns and auto-scrolling to the newest line.

- **The full auto-follow-up round trip (question → auto-listen → a real spoken answer
  actually getting transcribed) wasn't cleanly demonstrated** — one live attempt timed
  out with "Nothing transcribed" from a test-timing miss on my end (the follow-up
  answer was played slightly outside the 6-second `CONTINUOUS_TURN_MS` window), not a
  code defect: the mechanism itself (mic reopening without a wake word) was clearly
  confirmed working both times. Worth a cleaner real test — or just real usage — to see
  a full back-and-forth complete without the timing miss.

## "Hey Jarvis" → "Hey Foxy" — done

See `HISTORY.md` §33 for the full story, including a long, fully-diagnosed chain of
openWakeWord's own training notebook being bit-rotted against current library versions
(not abandoned for lack of trying) that led to training with a different, actively
maintained tool instead — **nanowakeword** (`github.com/arcosoph/nanowakeword`). That
changed the integration, not just where the model came from: `wakeword.py` now uses
`nanowakeword.NanoInterpreter` instead of `openwakeword.model.Model`. The trained model
is committed to the repo at `daemon/src/paTools/models/hey_foxy.onnx` (a one-of-a-kind
artifact from the user's own training run, unlike Piper's generic re-downloadable voice
model), with `hey_foxy_lite.onnx` (an unused-for-now low-power gate model) and
`hey_foxy.pt` (the raw checkpoint, kept in case retraining is needed later) alongside
it. `nanowakeword` needs `pip install --user nanowakeword` — README's setup steps need
a pass to mention this alongside the existing `openwakeword`/`sounddevice` install
line (openWakeWord itself is no longer imported anywhere and could be `pip uninstall`'d,
though leaving it installed is harmless).

**Verified live, real acoustic loopback**: a real "Hey Foxy" utterance correctly fired
a wake event through the actual running plugin, and a full turn — "Hey Foxy" + "What is
2 plus 2?" — was correctly transcribed and answered ("2 plus 2 is 4.") end to end by the
real daemon. Not yet tried: a real human voice saying "Hey Foxy" (every test so far used
Piper-synthesized speech for the wake phrase itself, same caveat this project has always
had for wake-word testing — see `HISTORY.md` §26).

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

## Settings page / knob RGB ring — mostly resolved via real power-cycle testing

See `HISTORY.md` §35. A genuine physical power cycle (not just a software restart —
the first time this project ever tested that) settled two things that were previously
only verified at the firmware-reported-value level, never by real physical observation:

- **`KnobLighting.solidColorEffect` (`1`) is confirmed correct** — the ring does settle
  into a real, stable solid color once the app (re-)sends it; this was never actually
  the bug. **Resolved**, no longer open.
- **`saveLighting()` (VIA `0x09`) does not reliably persist through a real power-off on
  this exact firmware** — confirmed after two different timing-based fixes both failed
  against real hardware. Worked around at the software layer (a local preference file,
  reconciled against the device on every reconnect) rather than fixed at the firmware
  layer, which is out of reach from here. **Verified working** by the user on real
  hardware: the ring briefly shows its firmware boot-default cycling animation right
  after power-on, then self-corrects to the last chosen color within moments of the
  daemon reconnecting.
- **Still open**: whether `setLedBrightness`'s own value has the same real-persistence
  gap as color did (the new reconciliation logic also re-applies brightness when it
  mismatches, so it should already be covered, but this hasn't been separately
  power-cycle-tested the way color was).
- **Physically confirm the microphone actually mutes/unmutes** — there's no manual
  toggle anymore (`HISTORY.md` §32: the mic is now gated entirely by Foxy's own on/off
  state, `off` at boot, `on` only while Foxy is armed). The command round-trip is
  verified against the device's own reported state and a real race at boot was found
  and fixed (§32), but nothing has confirmed audio is actually captured or blocked at
  the hardware level, only that the device acknowledges the on/off flag.
- **Physically look at the screen while dragging the Screen Brightness slider** — the
  ring's own brightness/color now have real physical confirmation (above), but screen
  brightness is a separate, still-unconfirmed control: `setBrightness`/
  `queryLuminance`'s software round-trip is confirmed (drag to a value, read the same
  value back), but a `grim` screenshot fundamentally cannot show a backlight change (it
  captures the rendered framebuffer, not the physical light output), so nobody has
  confirmed the screen actually dims. Screen brightness also has no
  `saveLighting`-equivalent persist command in the driver at all — given color's own
  `saveLighting()` turned out not to reliably work either, this is worth assuming
  doesn't persist through a power cycle unless/until proven otherwise.
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
