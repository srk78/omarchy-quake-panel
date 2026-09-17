#!/usr/bin/env node
'use strict';
/*
 * paBridge.js — orchestrates the "PA" voice-agent turn loop: Voxtype (local speech-to-
 * text) -> Hermes, a self-hosted agent harness reached over Tailscale via SSH (see
 * askHermes()), falling back to the `claude` CLI (a real agent, given tools via
 * paTools/server.js) when Hermes is unreachable -> Piper (local text-to-speech) -> a
 * spoken/shown reply. See HISTORY.md for the design brainstorm this implements — Phase A
 * (manual push-to-talk), Phase B (spoken replies), Phase C (continuous "wake word" mode),
 * and Phase D (Home Assistant control, Claude-fallback-path only) are done; the Hermes
 * primary brain is its own later addition (see HISTORY.md's Hermes section).
 *
 * A second, independent daemon process from bridge.js/HidBridge.qml on purpose: this one
 * shells out to much slower, heavier, more experimental things (an LLM CLI call can take
 * several seconds) and must never be able to block or destabilize the HID/touch daemon
 * everything else in this app depends on.
 *
 * MIT-licensed: pure process/IPC orchestration, no device protocol.
 *
 * stdout: one JSON object per line, mirroring bridge.js's own shape:
 *   {"t":"state","state":{"status":"idle"|"listening"|"transcribing"|"thinking"|"speaking","continuous":bool}}
 *   {"t":"transcript","text":"..."}
 *   {"t":"reply","text":"..."}
 *   {"t":"error","message":"..."}
 *
 * stdin: one JSON command per line:
 *   {"cmd":"startTurn"} | {"cmd":"endTurn"} | {"cmd":"cancelTurn"} | {"cmd":"resetSession"}
 *   {"cmd":"startContinuous"} | {"cmd":"stopContinuous"}
 *
 * Voxtype integration deliberately uses its file-based, scriptable path rather than its
 * normal type-into-focused-window dictation behavior: `record start --file=<path>`
 * writes the transcript to a plain text file, and `record stop --wait --json` blocks
 * until transcription is final. No keyboard-injection interception needed. Uses a
 * PA-scoped Voxtype config (~/.config/voxtype/pa.toml, see ops/voxtype/pa.example.toml)
 * so this pins the panel's own mic explicitly rather than inheriting the user's everyday
 * dictation config's device/output settings.
 *
 * Continuous mode (paTools/wakeword.py, Python + nanowakeword) spots the wake phrase on
 * the SAME mic and then exits immediately — it never runs at the same time as Voxtype's
 * own recording, sidestepping any question of whether this machine's ALSA setup actually
 * lets two processes capture the same device at once. The wake word is a real
 * custom-trained "Hey Foxy" model (see HISTORY.md §33 for the training story, and why
 * nanowakeword rather than openWakeWord's own training tooling).
 */
const readline = require('readline');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn, execFile, execFileSync } = require('child_process');

function out(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }

const VOXTYPE_CONFIG = path.join(os.homedir(), '.config', 'voxtype', 'pa.toml');
const TRANSCRIPT_FILE = path.join(os.tmpdir(), 'omarchy-quake-panel-pa-transcript.txt');
const MCP_CONFIG_FILE = path.join(os.tmpdir(), 'omarchy-quake-panel-pa-mcp.json');
const MCP_SERVER_SCRIPT = path.join(__dirname, 'paTools', 'server.js');
const CLAUDE_MODEL = process.env.OQP_PA_MODEL || 'claude-haiku-4-5';

// Piper (piper1-gpl, AUR package "piper-tts") — its binary is installed as `piper-tts`,
// not `piper`, specifically to avoid colliding with the unrelated GTK gaming-mouse
// config tool already in the official repos also named "piper" (confirmed live: that
// exact collision is why the AUR PKGBUILD renames its own binary at package time).
// Voice model downloaded once via `python -m piper.download_voices en_US-lessac-medium
// --download-dir ~/.local/share/piper/voices` (see README) — not fetched automatically
// here, same reasoning as Voxtype's whisper models: a multi-hundred-MB model download
// has no business happening silently inside a daemon's normal startup path.
const PIPER_BIN = process.env.OQP_PA_PIPER_BIN || 'piper-tts';
const PIPER_MODEL = process.env.OQP_PA_PIPER_MODEL
  || path.join(os.homedir(), '.local', 'share', 'piper', 'voices', 'en_US-lessac-medium.onnx');
const TTS_WAV_FILE = path.join(os.tmpdir(), 'omarchy-quake-panel-pa-reply.wav');
// Pinned explicitly rather than trusting PipeWire's current default sink, same
// reasoning as VOXTYPE_CONFIG pinning the mic: a plugged-in HDMI display can silently
// change the system default output, which would make Foxy go inaudibly "speak" into a
// monitor nobody has speakers on. This exact name is THIS machine's laptop speaker
// (`pactl list short sinks`) — a different machine needs its own value, either via
// OQP_PA_SPEAKER_SINK or by editing this default.
const SPEAKER_SINK = process.env.OQP_PA_SPEAKER_SINK
  || 'alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink';

// Wake-word listener (paTools/wakeword.py). A wake-triggered turn has no manual
// "release" to end it (unlike the button/knob), so it just records for a fixed window
// instead — simpler and more robust than trying to run real silence/VAD endpointing on
// the same mic the listener was just using, at the cost of either a little dead air or
// occasionally cutting off a long request. Voxtype's own config has no auto-stop-on-
// silence option at all (checked its `config schema` — only a hard max-duration safety
// cap), so this isn't a corner that was cut in favor of something better Voxtype
// already offered.
const WAKEWORD_SCRIPT = path.join(__dirname, 'paTools', 'wakeword.py');
const WAKEWORD_PYTHON = process.env.OQP_PA_WAKEWORD_PYTHON || 'python3';
const CONTINUOUS_TURN_MS = parseInt(process.env.OQP_PA_CONTINUOUS_TURN_MS || '6000', 10);

// Foxy's primary brain: Stefan's own self-hosted agent harness, "Hermes," reached over
// Tailscale via plain SSH + the `hermes` CLI — not a new network protocol. Hermes is
// CLI-driven and structurally close to `claude` itself (profiles, sessions, one-shot
// invocation), so this mirrors askClaude() below almost exactly, just a different binary/
// host. Hermes also documents a WebSocket "connector" protocol for platform integrations,
// but it's marked experimental with no accessible reference implementation (its own repo,
// NousResearch/gateway-gateway, isn't public — confirmed 404) — SSH+CLI sidesteps
// reverse-engineering that from a doc description alone.
const HERMES_SSH_HOST = process.env.OQP_PA_HERMES_HOST || 'hermes';
const HERMES_SSH_USER = process.env.OQP_PA_HERMES_SSH_USER || 'stefan';
const HERMES_BIN = process.env.OQP_PA_HERMES_BIN || '/home/stefan/.local/bin/hermes';
// A dedicated profile (not "default") so Foxy's own conversation history/config is
// isolated from whatever else Hermes is used for (its own Discord/Telegram gateway, the
// user's own direct `hermes chat` use). Foxy's voice-friendly persona (formerly this
// file's own SYSTEM_PROMPT below, now Hermes-side) lives in this profile's own SOUL.md —
// see HISTORY.md for the exact wording ported over.
const HERMES_PROFILE = process.env.OQP_PA_HERMES_PROFILE || 'foxy';
const HERMES_CONNECT_TIMEOUT_S = parseInt(process.env.OQP_PA_HERMES_CONNECT_TIMEOUT_S || '8', 10);
const HERMES_TIMEOUT_MS = parseInt(process.env.OQP_PA_HERMES_TIMEOUT_MS || '60000', 10);

// Same file paTools/server.js's remember_fact/forget_fact tools write to — no shared
// module between this process and that one, just an agreed-upon path/shape, matching
// this project's existing style. Read fresh on every turn (not cached) so a fact saved
// moments ago by the same conversation is already visible on the very next call.
const MEMORY_FILE = path.join(os.homedir(), '.local', 'state', 'omarchy-quake-panel', 'foxy-memory.json');

// Passive recall: baked into every turn's system prompt rather than requiring the model
// to spend a tool call fetching it first. Returns '' when there's nothing remembered
// yet, so callers can just concatenate without a conditional.
function loadMemoryForPrompt() {
  let entries;
  try { entries = JSON.parse(fs.readFileSync(MEMORY_FILE, 'utf8')); } catch (e) { return ''; }
  if (!Array.isArray(entries) || entries.length === 0) return '';
  const lines = entries.map(e => '- ' + e.text).join('\n');
  return '\n\nKnown facts about the user, remembered from earlier conversations:\n' + lines;
}

// Every tool the "quake-panel" MCP server exposes (paTools/server.js), fully qualified
// as `mcp__<serverName>__<toolName>` — confirmed live to be the exact name Claude Code's
// permission system wants (see HISTORY.md). Passed to --allowedTools below: without it,
// a non-interactive `-p` call has no human to click "allow" for, and the tool call is
// silently permission-denied instead of executed — confirmed live the hard way. Add the
// new tool's qualified name here as later phases add more.
const ALLOWED_TOOLS = [
  'mcp__quake-panel__start_pomodoro',
  'mcp__quake-panel__remember_fact',
  'mcp__quake-panel__forget_fact',
  'mcp__quake-panel__list_remembered_facts',
  'mcp__quake-panel__list_ha_entities',
  'mcp__quake-panel__propose_ha_action',
  'mcp__quake-panel__confirm_pending_action',
  'mcp__quake-panel__cancel_pending_action',
];

// Full REPLACEMENT of Claude Code's own default system prompt (--system-prompt), not
// --append-system-prompt: appending only adds to "you are Claude Code, a software
// engineering assistant", and confirmed live that a model told to be "Foxy" via append
// still introduced itself as a coding assistant and ignored a perfectly good tool for a
// pomodoro request, reaching for Bash to fake one with `sleep` instead. A full replace
// fixed it immediately.
const SYSTEM_PROMPT = [
  "You are Foxy, a concise voice assistant embedded in a small touchscreen control",
  "panel next to the user's desk. You hear the user through local speech-to-text, so",
  "expect occasional mishearings. Replies are read aloud, so keep them short — one or",
  "two sentences unless asked for more. When a request is missing information you",
  "genuinely need, ask a brief clarifying question instead of guessing. Use your tools",
  "to actually perform actions rather than just describing them or writing code/shell",
  "commands as text. Never use markdown formatting — no asterisks, bullet points,",
  "headers, or backticks. Your replies are read aloud by a speech synthesizer, not",
  "displayed as text, so write plain spoken sentences only.",
  "",
  "For smart-home requests: look up the real device first with list_ha_entities, then",
  "call propose_ha_action to record what you intend to do — this does not perform the",
  "action. Tell the user what you are about to do and wait. Only call",
  "confirm_pending_action after the user clearly says yes/go ahead/confirmed in a later",
  "message; if they say no or change the subject, call cancel_pending_action instead.",
  "Never call propose_ha_action and confirm_pending_action in the same response — the",
  "user must have an actual chance to say yes first. This applies even if you are very",
  "confident about the request.",
  "",
  "If the user tells you something worth remembering for later — a preference, a fact",
  "about their routine or home — call remember_fact to save it. No need to ask",
  "permission first for ordinary personal facts. If they correct something you got",
  "wrong or ask you to forget it, call forget_fact.",
].join(' ');

// Written once at startup rather than checked into the repo: the MCP server's absolute
// path depends on where this checkout lives (a dev repo, or an installed plugin under
// ~/.config/omarchy/plugins/), which a static JSON file can't know.
function writeMcpConfig() {
  const config = { mcpServers: { 'quake-panel': { command: 'node', args: [MCP_SERVER_SCRIPT] } } };
  fs.writeFileSync(MCP_CONFIG_FILE, JSON.stringify(config, null, 2));
}

let claudeSessionId = null; // fallback-path session id — see askClaude()'s own comment
let turnInFlight = false;
let continuousMode = false;
let currentStatus = 'idle';
let wakeProc = null;
// The one long-running child process representing "the thing currently in flight" for
// the transcribing/thinking/speaking phases — set right before each spawn/execFile call,
// cleared (only if it still points at that same child, avoiding a race with whatever the
// next turn already started) the moment that call's own completion callback fires.
// cancelTurn() kills whatever's here for those phases; "listening" doesn't use this at
// all (see cancelTurn()'s own comment on why).
let activeChild = null;
// Set by cancelTurn() right before it kills activeChild, so that killed process's own
// completion callback — which still fires, just as an error/non-zero exit — recognizes
// the turn was already deliberately ended and skips re-processing (no double
// finishTurn(), no spurious "failed" error for an intentional cancel). Cleared at the
// start of every fresh turn.
let turnWasCancelled = false;
// Hermes' own session id (its "session_id: <id>" line, read off stderr — see askHermes()),
// analogous to claudeSessionId above but for the primary/Hermes path. Passing it back as
// --resume continues that conversation; omitting it (after a reset) starts fresh. Hermes
// keeps the actual conversation history on its own side — this file only tracks the id.
let hermesSessionId = null;
// Given to each `claude -p` invocation as OQP_PA_TURN_ID (see askClaude), and checked by
// paTools/server.js's confirm_pending_action against the turn ID stored at propose time
// — see this file's own header comment on why a code-enforced check exists here at all
// rather than trusting the system prompt alone: a single `claude -p` call can make
// several tool calls back-to-back before ever returning text to the human, so nothing
// about MCP's own mechanics stops the model proposing AND confirming an action inside
// one turn, before the user has actually said yes to anything. Comparing turn IDs makes
// that combination fail closed instead of silently working.
let turnCounter = 0;
let continuousTurnTimer = null;
// Set right before speak() in askClaude()'s success path when Foxy's own reply reads as
// a question (see its own comment there) — consumed exactly once by the very next
// finishTurn(), so only the turn immediately following a question skips the wake word;
// if the user doesn't respond (or responds with something that isn't itself a
// question), the turn after that goes back to normal wake-word-gated listening rather
// than leaving the mic hot indefinitely.
let autoListenAfterReply = false;
// A long-lived `--resume` session only ever grows — every turn re-sends its whole
// history, so an old conversation left running for hours is a real, untuned cost/
// latency concern (see NEXT_STEPS.md). Reset on two triggers: explicitly turning Foxy
// off (stopContinuous — the transcript already visually resets then, PaState.qml's
// setContinuousMode(false); this makes the actual conversation memory match that),
// and this idle timer, re-armed at the end of every turn while continuousMode is on.
// Safe to reset aggressively now that persistent memory (paTools/server.js's
// remember_fact) exists separately — anything the user actually wanted kept survives
// in foxy-memory.json regardless of what happens to the raw session.
const SESSION_IDLE_RESET_MS = parseInt(process.env.OQP_PA_SESSION_IDLE_RESET_MS || String(30 * 60 * 1000), 10);
let sessionIdleTimer = null;
function _armSessionIdleReset() {
  if (sessionIdleTimer) clearTimeout(sessionIdleTimer);
  if (SESSION_IDLE_RESET_MS <= 0) return; // 0 or negative disables the idle reset entirely
  sessionIdleTimer = setTimeout(() => {
    console.error(`Session idle-reset after ${SESSION_IDLE_RESET_MS}ms of inactivity`);
    resetSession();
  }, SESSION_IDLE_RESET_MS);
}
function _clearSessionIdleReset() {
  if (sessionIdleTimer) { clearTimeout(sessionIdleTimer); sessionIdleTimer = null; }
}

function emitState() { out({ t: 'state', state: { status: currentStatus, continuous: continuousMode } }); }
function setStatus(status) { currentStatus = status; emitState(); }

// The one place every turn — however it started — ends up, success or failure, so the
// wake-word listener reliably comes back if continuous mode is still on. Anything that
// used to call setStatus('idle') as its terminal step calls this instead.
// However quickly one process closes its capture stream, ALSA doesn't necessarily make
// the device available to the next opener instantly — confirmed live: without this gap,
// the wake-word listener's very next restart intermittently failed with "Invalid sample
// rate [PaErrorCode -9997]", a transient PortAudio error from probing the device before
// the previous consumer had fully released it. wakeword.py also retries its own device
// open a few times as a second line of defense, but avoiding the race here is cheaper
// than needing that retry to fire.
const MIC_HANDOFF_DELAY_MS = 400;

function finishTurn() {
  turnInFlight = false;
  setStatus('idle');
  if (!continuousMode) return;
  _armSessionIdleReset();
  if (autoListenAfterReply) {
    // Skip the wake word entirely — reuse the exact fixed-window recording mechanics
    // the wake handler itself uses (startTurn() + a timer that force-ends it), just
    // without waiting for "Hey Foxy" first.
    autoListenAfterReply = false;
    setTimeout(() => {
      startTurn();
      continuousTurnTimer = setTimeout(() => { if (turnInFlight) endTurn(); }, CONTINUOUS_TURN_MS);
    }, MIC_HANDOFF_DELAY_MS);
  } else {
    setTimeout(startListener, MIC_HANDOFF_DELAY_MS);
  }
}

function startTurn() {
  if (turnInFlight) return;
  stopListener(); // never share the mic with the wake-word listener mid-turn
  turnInFlight = true;
  turnWasCancelled = false;
  autoListenAfterReply = false; // defensive — a fresh turn should never carry over a stale intent from before
  try { fs.unlinkSync(TRANSCRIPT_FILE); } catch (e) { /* fine if it didn't exist yet */ }
  setStatus('listening');
  const proc = spawn('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'start', `--file=${TRANSCRIPT_FILE}`], { stdio: 'ignore' });
  proc.on('error', err => {
    out({ t: 'error', message: `voxtype record start failed: ${err.message}` });
    finishTurn();
  });
}

function endTurn() {
  if (!turnInFlight) return;
  if (continuousTurnTimer) { clearTimeout(continuousTurnTimer); continuousTurnTimer = null; }
  setStatus('transcribing');
  const child = execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'stop', '--wait', '--json', '--timeout', '20'], (err, stdout, stderr) => {
    if (activeChild === child) activeChild = null;
    if (turnWasCancelled) return; // cancelTurn() already killed this and called finishTurn()
    // Exit codes 3 (nothing to transcribe) and 4 (timed out) are documented, ordinary
    // outcomes for "the user didn't actually say anything" — most often a continuous-
    // mode turn whose fixed recording window caught only silence after the wake word.
    // Only exit code 1 ("failed") or a launch failure (no err.code at all — the binary
    // itself didn't run) is a genuine error worth a scary message; the rest fall through
    // to the same "Nothing transcribed" handling an empty transcript file already gets.
    if (err && err.code !== 3 && err.code !== 4) {
      out({ t: 'error', message: `voxtype record stop failed: ${err.message}${stderr ? ' - ' + stderr.trim() : ''}` });
      finishTurn();
      return;
    }
    let outcome = null;
    try { outcome = JSON.parse(stdout); } catch (e) { /* keep null, not fatal */ }
    let text = '';
    try { text = fs.readFileSync(TRANSCRIPT_FILE, 'utf8').trim(); } catch (e) { /* nothing transcribed */ }
    if (!text) {
      // Silence after the wake word (or Foxy's own auto-follow-up) is the routine case
      // now, not a surprise worth a chat-visible error — there's no more manual "I
      // meant to say something" push-to-talk button (removed, see HISTORY.md's FOXY
      // redesign); every turn today starts from the wake word or the auto-follow-up.
      // Still logged to stderr (reaches the daemon's own debug log via PaBridge.qml's
      // "[paBridge:stderr]" echo) so it stays diagnosable without cluttering the
      // transcript.
      console.error('Nothing transcribed' + (outcome ? ` (${JSON.stringify(outcome)})` : ''));
      finishTurn();
      return;
    }
    out({ t: 'transcript', text });
    askHermes(text);
  });
  activeChild = child;
}

function cancelTurn() {
  if (!turnInFlight) return; // idle — nothing to cancel
  if (continuousTurnTimer) { clearTimeout(continuousTurnTimer); continuousTurnTimer = null; }
  autoListenAfterReply = false; // a cancelled turn never reaches a reply — nothing to auto-follow-up on
  if (currentStatus === 'listening') {
    // Voxtype's own recording is a background service, not tied to any child-process
    // handle of ours (see this file's header comment) — an explicit cancel command is
    // the only thing that actually stops it, not killing a process on our side.
    execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'cancel'], () => finishTurn());
    return;
  }
  // transcribing/thinking/speaking: activeChild is a real child process we hold a handle
  // to — kill it directly. turnWasCancelled stops its own completion callback (which
  // still fires after a kill, just as an error/non-zero exit) from re-processing a turn
  // this has already finished.
  turnWasCancelled = true;
  if (currentStatus === 'speaking') stopAudioLevelPlayback(); // settle the visualizer immediately rather than waiting on the killed player's own callback
  if (activeChild) { activeChild.kill('SIGKILL'); activeChild = null; }
  finishTurn();
}

// --- continuous "wake word" mode (Phase C) ---------------------------------------

// wakeword.py already retries its own device open a few times internally (see its own
// comment on why), but confirmed live that isn't always enough — an ALSA handoff can
// occasionally still lose the race and the whole process exits with an error. Rather
// than trying to out-guess every possible timing, this is the second, outer line of
// defense: if the listener dies WITHOUT having fired a wake event, and continuous mode
// is still meant to be on, just try spinning up a fresh one again after a beat. Without
// this, one transient failure would silently leave "continuous mode" on in name only —
// the toggle stays lit, nothing is actually listening — until the user notices and
// re-toggles it by hand.
const LISTENER_RETRY_MS = 2000;

function startListener() {
  if (wakeProc || turnInFlight || !continuousMode) return;
  const proc = spawn(WAKEWORD_PYTHON, [WAKEWORD_SCRIPT]);
  wakeProc = proc;
  let gotWake = false;
  const listenerLines = readline.createInterface({ input: proc.stdout, terminal: false });
  listenerLines.on('line', line => {
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return; }
    if (msg.event === 'wake') {
      gotWake = true;
      // The listener is already on its way out right after printing this (see
      // wakeword.py's own header comment) — no need to kill it, just drop the
      // reference so startListener() doesn't think one is still running. The actual
      // process exit (and ALSA releasing the device) still takes a moment — see
      // MIC_HANDOFF_DELAY_MS.
      wakeProc = null;
      setTimeout(() => {
        startTurn();
        continuousTurnTimer = setTimeout(() => { if (turnInFlight) endTurn(); }, CONTINUOUS_TURN_MS);
      }, MIC_HANDOFF_DELAY_MS);
    } else if (msg.event === 'error') {
      out({ t: 'error', message: `wake-word listener: ${msg.message}` });
    }
  });
  proc.stderr.on('data', () => { /* onnxruntime's harmless "no CUDA provider" warning lives here */ });
  proc.on('error', err => {
    out({ t: 'error', message: `wake-word listener failed to start: ${err.message}` });
    if (wakeProc === proc) wakeProc = null;
  });
  proc.on('exit', () => {
    if (wakeProc !== proc) return; // already handled (wake fired, or stopListener() ran)
    wakeProc = null;
    if (!gotWake && continuousMode && !turnInFlight) setTimeout(startListener, LISTENER_RETRY_MS);
  });
}

function stopListener() {
  // SIGKILL, not SIGTERM — see the startup cleanup's own comment on why: a process
  // blocked in an ALSA/PortAudio wait can simply not notice SIGTERM until it exits that
  // call on its own, which defeats the entire point of stopping it promptly before the
  // next mic consumer (Voxtype, or a fresh listener) tries to open the device. Nothing
  // here has state worth flushing on the way out.
  if (wakeProc) { wakeProc.kill('SIGKILL'); wakeProc = null; }
}

function startContinuous() {
  continuousMode = true;
  emitState();
  if (!turnInFlight) startListener();
}

function stopContinuous() {
  continuousMode = false;
  stopListener();
  _clearSessionIdleReset();
  resetSession(); // a fresh conversation next time Foxy turns on — see SESSION_IDLE_RESET_MS's own comment
  emitState();
}

// Confirmed live: killing the LOCAL ssh client (SIGKILL — what cancelTurn() does to
// activeChild) does NOT kill the REMOTE hermes process. SSH without a pseudo-tty doesn't
// propagate the hangup, so the remote `hermes chat` invocation just keeps running,
// abandoned, burning the Pi's CPU/GPU on a reply nobody will ever hear. This is the
// fix: a best-effort, fire-and-forget second SSH call targeting exactly this turn's own
// unique remote prompt-file path (never ambiguous with any other turn, past or
// concurrent). Nothing reacts to its result either way — a cancel has already ended the
// turn locally regardless of whether this cleanup actually lands.
function killRemoteHermesTurn(remoteTmpPath) {
  execFile('ssh', [
    '-o', 'BatchMode=yes', '-o', `ConnectTimeout=${HERMES_CONNECT_TIMEOUT_S}`,
    `${HERMES_SSH_USER}@${HERMES_SSH_HOST}`,
    'pkill', '-9', '-f', remoteTmpPath,
  ], () => { /* best-effort cleanup only */ });
}

// Foxy's primary brain. promptText is written to a remote temp file rather than ever
// being interpolated into the SSH command string — confirmed live that hermes chat's own
// --query-file "is safe for arbitrary text: nothing is shell-interpreted, so quotes,
// $(...), and backticks are preserved verbatim," which matters here because promptText is
// real speech-to-text output the user doesn't control the shape of. The file itself is
// written by piping promptText over this SAME ssh connection's stdin to `cat >
// <remoteTmpPath>` — one round trip, and the prompt's bytes never appear on any command
// line, local or remote.
function askHermes(promptText) {
  setStatus('thinking');
  const remoteTmpPath = `/tmp/oqp-hermes-turn-${Date.now()}.txt`;
  // hermesSessionId only ever comes from Hermes' own stderr (see below), never from user
  // input — but it still gets validated before being concatenated into the remote command
  // string, on principle, rather than trusted just because today's observed format
  // (e.g. "20260917_193541_f98de1") happens to look safe.
  const resumeArg = (hermesSessionId && /^[A-Za-z0-9_.:-]+$/.test(hermesSessionId))
    ? ` --resume ${hermesSessionId}`
    : '';
  const remoteCommand = `cat > ${remoteTmpPath} && ${HERMES_BIN} chat --query-file ${remoteTmpPath} `
    + `--oneshot -Q -p ${HERMES_PROFILE} --source tool${resumeArg}; rm -f ${remoteTmpPath}`;
  const child = execFile('ssh', [
    '-o', 'BatchMode=yes', '-o', `ConnectTimeout=${HERMES_CONNECT_TIMEOUT_S}`,
    `${HERMES_SSH_USER}@${HERMES_SSH_HOST}`,
    remoteCommand,
  ], { timeout: HERMES_TIMEOUT_MS, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
    if (activeChild === child) activeChild = null;
    if (turnWasCancelled) { killRemoteHermesTurn(remoteTmpPath); return; }
    if (err) {
      // Anything here — a down Pi, a dead tailnet link, ssh's own ConnectTimeout firing,
      // hermes itself erroring — looks the same from this side: unreachable. Falls back
      // to the exact same claude CLI path this file used exclusively before Hermes
      // existed, so pomodoro/memory/HA tools even keep working during a fallback.
      console.error(`Hermes unreachable, falling back to Claude: ${err.message}${stderr ? ' - ' + stderr.trim() : ''}`);
      askClaude(promptText, true);
      return;
    }
    // Confirmed live: hermes chat -Q's plain-text stdout is exactly the reply and nothing
    // else — the "session_id: <id>" line (and everything else: banners, warnings, "session
    // found but has no messages" notices) rides stderr instead.
    const m = /session_id:\s*(\S+)/.exec(stderr);
    if (m) hermesSessionId = m[1];
    const replyText = stdout.trim();
    autoListenAfterReply = /\?["')\]]*$/.test(replyText.trim());
    out({ t: 'reply', text: replyText });
    speak(replyText);
  });
  child.stdin.write(promptText);
  child.stdin.end();
  activeChild = child;
}

// The original brain, kept exactly as it was — now doubling as Foxy's fallback whenever
// Hermes (askHermes() above) is unreachable. isFallback prepends a short spoken note so a
// fallback is never silent, per the user's own explicit requirement ("use wrapped Claude
// as fallback, but mention so").
function askClaude(promptText, isFallback) {
  setStatus('thinking');
  turnCounter += 1;
  const args = [
    '-p', promptText,
    '--mcp-config', MCP_CONFIG_FILE,
    '--strict-mcp-config',
    '--allowedTools', ALLOWED_TOOLS.join(','),
    '--output-format', 'json',
    '--model', CLAUDE_MODEL,
    '--system-prompt', SYSTEM_PROMPT + loadMemoryForPrompt(),
  ];
  if (claudeSessionId) args.push('--resume', claudeSessionId);
  // cwd deliberately NOT this repo: running from inside it pulls in this project's own
  // CLAUDE.md/skills as unrelated context on every turn (confirmed live — a throwaway
  // test call from the repo root cache-primed over 10k tokens of project context it
  // never needed). --strict-mcp-config already scopes tools; this scopes the rest.
  // OQP_PA_TURN_ID flows to the MCP server subprocess (server.js) this invocation spawns
  // — see turnCounter's own comment for what it's for.
  const env = Object.assign({}, process.env, { OQP_PA_TURN_ID: String(turnCounter) });
  const child = execFile('claude', args, { cwd: os.homedir(), env, maxBuffer: 10 * 1024 * 1024, timeout: 60000 }, (err, stdout, stderr) => {
    if (activeChild === child) activeChild = null;
    if (turnWasCancelled) return; // cancelTurn() already killed this and called finishTurn()
    if (err) {
      out({ t: 'error', message: `claude CLI failed: ${err.message}${stderr ? ' - ' + stderr : ''}` });
      finishTurn();
      return;
    }
    let result;
    try { result = JSON.parse(stdout); } catch (e) {
      out({ t: 'error', message: `claude CLI returned unparseable output: ${e.message}` });
      finishTurn();
      return;
    }
    if (result.session_id) claudeSessionId = result.session_id;
    if (result.is_error) {
      out({ t: 'error', message: `claude reported an error: ${result.result || 'unknown'}` });
      finishTurn();
      return;
    }
    // "mention so" — a fallback reply is never silent about being one (the user's own
    // explicit requirement). Only the SPOKEN/shown reply gets the note; it doesn't touch
    // the autoListenAfterReply heuristic below (checked against Claude's own text first).
    const replyText = (isFallback ? "My usual brain's unreachable, so this is backup Claude. " : '') + (result.result || '');
    // A simple, deterministic heuristic — "does the reply end in a question mark" — not
    // a second model call or structured-output plumbing to have Claude explicitly flag
    // it. Matches this project's existing preference for honest, simple scope over more
    // machinery (the fixed-duration recording window instead of real VAD, HISTORY.md
    // §26, is the precedent). Consumed once by finishTurn(), after Foxy's spoken reply
    // actually finishes playing.
    autoListenAfterReply = /\?["')\]]*$/.test(replyText.trim());
    out({ t: 'reply', text: replyText });
    speak(replyText);
  });
  activeChild = child;
}

// The system prompt already asks Claude not to use markdown, but a model can still slip
// (habit from its usual text-formatting context) — this is the code-level guarantee: no
// literal "asterisk"/markdown punctuation ever reaches Piper, regardless of what the
// model actually wrote. Deliberately only touches what's sent to Piper, not the
// on-screen transcript (out({t:'reply',...}) below already ran before speak() is
// called) or the autoListenAfterReply question-detection heuristic — those keep
// operating on Claude's original text.
function stripMarkdownForSpeech(text) {
  return text
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/\*(.+?)\*/g, '$1')
    .replace(/__(.+?)__/g, '$1')
    .replace(/_(.+?)_/g, '$1')
    .replace(/[*_]/g, '') // leftover unpaired markers
    .replace(/`([^`]*)`/g, '$1')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/^[-*]\s+/gm, '')
    .trim();
}

// Piper writes a WAV file (not streamed raw to stdout — avoids having to know/match the
// voice model's exact sample format on the paplay side; a WAV header carries that for
// us), then paplay plays that file to the pinned speaker sink. Text goes to Piper over
// stdin rather than a CLI arg — arbitrary-length model replies have no business being
// squeezed through argv.
function speak(text) {
  const clean = String(text || '').trim();
  if (!clean) { finishTurn(); return; }
  const spoken = stripMarkdownForSpeech(clean);
  setStatus('speaking');
  const synth = spawn(PIPER_BIN, ['-m', PIPER_MODEL, '-f', TTS_WAV_FILE]);
  activeChild = synth;
  let synthErr = '';
  synth.stderr.on('data', chunk => { synthErr += chunk; });
  synth.on('error', err => {
    if (activeChild === synth) activeChild = null;
    if (turnWasCancelled) return;
    out({ t: 'error', message: `piper failed to start: ${err.message}` });
    finishTurn();
  });
  synth.on('exit', code => {
    if (activeChild === synth) activeChild = null;
    if (turnWasCancelled) return; // cancelTurn() already killed this and called finishTurn()
    if (code !== 0) {
      out({ t: 'error', message: `piper exited with code ${code}${synthErr ? ': ' + synthErr.trim() : ''}` });
      finishTurn();
      return;
    }
    // The particle visualizer (Ui/FoxyVisualizer.qml) reacts to Foxy's own reply audio
    // by replaying its precomputed volume envelope in time with playback — not a live
    // tap on the output stream. Piper writes the whole file before playback starts
    // anyway (it isn't a streaming synthesizer), so the exact envelope is already known
    // up front; this avoids running yet another audio-consuming process alongside
    // paplay for something a one-time file read already answers exactly.
    let envelope = [];
    try { envelope = computeAudioEnvelope(TTS_WAV_FILE, AUDIO_LEVEL_FPS); } catch (e) {
      out({ t: 'error', message: `audio envelope extraction failed: ${e.message}` });
      // Not fatal to the reply itself — Foxy still speaks, the visualizer just won't
      // react to this particular line.
    }
    const player = execFile('paplay', ['--device', SPEAKER_SINK, TTS_WAV_FILE], err => {
      if (activeChild === player) activeChild = null;
      stopAudioLevelPlayback();
      if (turnWasCancelled) return; // cancelTurn() already stopped playback and called finishTurn()
      if (err) out({ t: 'error', message: `paplay failed: ${err.message}` });
      finishTurn();
    });
    activeChild = player;
    startAudioLevelPlayback(envelope);
  });
  synth.stdin.write(spoken);
  synth.stdin.end();
}

// --- Foxy's speech reactivity (FoxyVisualizer.qml) ------------------------------

const AUDIO_LEVEL_FPS = 30;
let audioLevelTimer = null;

// Minimal hand-rolled RIFF/WAVE reader — good enough for Piper's own output (confirmed
// live: mono 16-bit PCM, see HISTORY.md), and avoids a new dependency for something
// this small. Computes RMS amplitude over fixed windows, normalized against this
// specific clip's own peak (not a fixed reference level) so a quiet reply and a loud
// one both read as comparably lively rather than the quiet one barely registering.
function computeAudioEnvelope(wavPath, fps) {
  const buf = fs.readFileSync(wavPath);
  if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error('not a RIFF/WAVE file');
  }
  let offset = 12;
  let fmt = null;
  let dataOffset = -1, dataLength = 0;
  while (offset + 8 <= buf.length) {
    const chunkId = buf.toString('ascii', offset, offset + 4);
    const chunkSize = buf.readUInt32LE(offset + 4);
    const chunkStart = offset + 8;
    if (chunkId === 'fmt ') {
      fmt = {
        numChannels: buf.readUInt16LE(chunkStart + 2),
        sampleRate: buf.readUInt32LE(chunkStart + 4),
        bitsPerSample: buf.readUInt16LE(chunkStart + 14),
      };
    } else if (chunkId === 'data') {
      dataOffset = chunkStart;
      dataLength = chunkSize;
    }
    offset = chunkStart + chunkSize + (chunkSize % 2); // chunks are word-aligned
  }
  if (!fmt || dataOffset < 0) throw new Error('missing fmt or data chunk');
  if (fmt.bitsPerSample !== 16) throw new Error(`unsupported bits per sample: ${fmt.bitsPerSample}`);

  const bytesPerFrame = 2 * fmt.numChannels;
  const totalSamples = Math.floor(dataLength / bytesPerFrame);
  const windowSamples = Math.max(1, Math.round(fmt.sampleRate / fps));
  const envelope = [];
  let peak = 0;
  for (let i = 0; i < totalSamples; i += windowSamples) {
    const end = Math.min(i + windowSamples, totalSamples);
    let sumSquares = 0, count = 0;
    for (let s = i; s < end; s++) {
      const sampleOffset = dataOffset + s * bytesPerFrame; // channel 0 only — Piper's output is mono anyway
      if (sampleOffset + 2 > buf.length) break;
      const sample = buf.readInt16LE(sampleOffset) / 32768;
      sumSquares += sample * sample;
      count++;
    }
    const rms = count > 0 ? Math.sqrt(sumSquares / count) : 0;
    envelope.push(rms);
    if (rms > peak) peak = rms;
  }
  const norm = Math.max(peak, 0.02); // floor avoids amplifying near-silent clips into noise
  return envelope.map(v => Math.min(1, v / norm));
}

function startAudioLevelPlayback(envelope) {
  stopAudioLevelPlayback();
  if (!envelope.length) return;
  let i = 0;
  audioLevelTimer = setInterval(() => {
    if (i >= envelope.length) { stopAudioLevelPlayback(); return; }
    out({ t: 'audioLevel', value: envelope[i] });
    i += 1;
  }, 1000 / AUDIO_LEVEL_FPS);
}

function stopAudioLevelPlayback() {
  if (audioLevelTimer) { clearInterval(audioLevelTimer); audioLevelTimer = null; }
  out({ t: 'audioLevel', value: 0 }); // settle the visualizer back to idle immediately, not on whatever the last frame happened to be
}

function resetSession() { claudeSessionId = null; hermesSessionId = null; }

const COMMANDS = { startTurn, endTurn, cancelTurn, resetSession, startContinuous, stopContinuous };

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', line => {
  line = line.trim();
  if (!line) return;
  let cmd;
  try { cmd = JSON.parse(line); } catch (e) { return out({ t: 'error', message: `bad command JSON: ${e.message}` }); }
  const fn = cmd && COMMANDS[cmd.cmd];
  if (!fn) return out({ t: 'error', message: `unknown command: ${cmd && cmd.cmd}` });
  try { fn(); } catch (e) { out({ t: 'error', message: e.message }); }
});

process.on('SIGINT', () => { stopListener(); process.exit(0); });
process.on('SIGTERM', () => { stopListener(); process.exit(0); });

// Confirmed live: `omarchy-restart-shell` killing the old quickshell/daemon tree does
// NOT reliably reach this daemon's own grandchild processes — an old wakeword.py can
// survive a full shell restart as an orphan, competing with the new listener for the
// same mic and producing exactly the intermittent "Invalid sample rate" errors
// startListener()'s own retry logic exists for (see HISTORY.md's Phase C section for
// the full diagnostic trail). Belt-and-suspenders: every fresh daemon boot clears out
// any stray instance of this exact script before doing anything else, so a leftover
// from a previous generation can never linger into this one. Harmless if none exist
// (pkill's own exit code for "nothing matched" isn't a real error here).
// -9/SIGKILL, not a plain SIGTERM: confirmed live that an orphan can be sitting in an
// ALSA/PortAudio wait that simply ignores SIGTERM until it exits that call on its own —
// exactly the stuck state this cleanup exists to guarantee doesn't linger.
try { execFileSync('pkill', ['-9', '-f', WAKEWORD_SCRIPT], { stdio: 'ignore' }); } catch (e) { /* nothing to kill */ }

writeMcpConfig();
setStatus('idle');
