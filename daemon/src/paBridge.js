#!/usr/bin/env node
'use strict';
/*
 * paBridge.js — orchestrates the "PA" voice-agent turn loop: Voxtype (local speech-to-
 * text) -> `claude` CLI (a real agent, given tools via paTools/server.js) -> Piper
 * (local text-to-speech) -> a spoken/shown reply. See HISTORY.md for the design
 * brainstorm this implements — Phase A (manual push-to-talk), Phase B (spoken replies),
 * and Phase C (this file's continuous "wake word" mode) are done; Home Assistant control
 * (Phase D) is not.
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
 * Continuous mode (paTools/wakeword.py, Python + openWakeWord) spots the wake phrase on
 * the SAME mic and then exits immediately — it never runs at the same time as Voxtype's
 * own recording, sidestepping any question of whether this machine's ALSA setup actually
 * lets two processes capture the same device at once. The wake word itself is the stock
 * "Hey Jarvis" model, not a trained "Hey Foxy" — see HISTORY.md for why (custom wake-word
 * training needs Google Colab, a whole separate manual undertaking); "Foxy" is still the
 * spoken persona, only the trigger phrase differs for now.
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

// Every tool the "quake-panel" MCP server exposes (paTools/server.js), fully qualified
// as `mcp__<serverName>__<toolName>` — confirmed live to be the exact name Claude Code's
// permission system wants (see HISTORY.md). Passed to --allowedTools below: without it,
// a non-interactive `-p` call has no human to click "allow" for, and the tool call is
// silently permission-denied instead of executed — confirmed live the hard way. Add the
// new tool's qualified name here as later phases add more.
const ALLOWED_TOOLS = [
  'mcp__quake-panel__start_pomodoro',
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
  "commands as text.",
  "",
  "For smart-home requests: look up the real device first with list_ha_entities, then",
  "call propose_ha_action to record what you intend to do — this does not perform the",
  "action. Tell the user what you are about to do and wait. Only call",
  "confirm_pending_action after the user clearly says yes/go ahead/confirmed in a later",
  "message; if they say no or change the subject, call cancel_pending_action instead.",
  "Never call propose_ha_action and confirm_pending_action in the same response — the",
  "user must have an actual chance to say yes first. This applies even if you are very",
  "confident about the request.",
].join(' ');

// Written once at startup rather than checked into the repo: the MCP server's absolute
// path depends on where this checkout lives (a dev repo, or an installed plugin under
// ~/.config/omarchy/plugins/), which a static JSON file can't know.
function writeMcpConfig() {
  const config = { mcpServers: { 'quake-panel': { command: 'node', args: [MCP_SERVER_SCRIPT] } } };
  fs.writeFileSync(MCP_CONFIG_FILE, JSON.stringify(config, null, 2));
}

let sessionId = null;
let turnInFlight = false;
let continuousMode = false;
let currentStatus = 'idle';
let wakeProc = null;
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
  if (continuousMode) setTimeout(startListener, MIC_HANDOFF_DELAY_MS);
}

function startTurn() {
  if (turnInFlight) return;
  stopListener(); // never share the mic with the wake-word listener mid-turn
  turnInFlight = true;
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
  execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'stop', '--wait', '--json', '--timeout', '20'], (err, stdout, stderr) => {
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
      out({ t: 'error', message: 'Nothing transcribed' + (outcome ? ` (${JSON.stringify(outcome)})` : '') });
      finishTurn();
      return;
    }
    out({ t: 'transcript', text });
    askClaude(text);
  });
}

function cancelTurn() {
  if (continuousTurnTimer) { clearTimeout(continuousTurnTimer); continuousTurnTimer = null; }
  execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'cancel'], () => finishTurn());
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
  emitState();
}

function askClaude(promptText) {
  setStatus('thinking');
  turnCounter += 1;
  const args = [
    '-p', promptText,
    '--mcp-config', MCP_CONFIG_FILE,
    '--strict-mcp-config',
    '--allowedTools', ALLOWED_TOOLS.join(','),
    '--output-format', 'json',
    '--model', CLAUDE_MODEL,
    '--system-prompt', SYSTEM_PROMPT,
  ];
  if (sessionId) args.push('--resume', sessionId);
  // cwd deliberately NOT this repo: running from inside it pulls in this project's own
  // CLAUDE.md/skills as unrelated context on every turn (confirmed live — a throwaway
  // test call from the repo root cache-primed over 10k tokens of project context it
  // never needed). --strict-mcp-config already scopes tools; this scopes the rest.
  // OQP_PA_TURN_ID flows to the MCP server subprocess (server.js) this invocation spawns
  // — see turnCounter's own comment for what it's for.
  const env = Object.assign({}, process.env, { OQP_PA_TURN_ID: String(turnCounter) });
  execFile('claude', args, { cwd: os.homedir(), env, maxBuffer: 10 * 1024 * 1024, timeout: 60000 }, (err, stdout, stderr) => {
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
    if (result.session_id) sessionId = result.session_id;
    if (result.is_error) {
      out({ t: 'error', message: `claude reported an error: ${result.result || 'unknown'}` });
      finishTurn();
      return;
    }
    out({ t: 'reply', text: result.result || '' });
    speak(result.result || '');
  });
}

// Piper writes a WAV file (not streamed raw to stdout — avoids having to know/match the
// voice model's exact sample format on the paplay side; a WAV header carries that for
// us), then paplay plays that file to the pinned speaker sink. Text goes to Piper over
// stdin rather than a CLI arg — arbitrary-length model replies have no business being
// squeezed through argv.
function speak(text) {
  const clean = String(text || '').trim();
  if (!clean) { finishTurn(); return; }
  setStatus('speaking');
  const synth = spawn(PIPER_BIN, ['-m', PIPER_MODEL, '-f', TTS_WAV_FILE]);
  let synthErr = '';
  synth.stderr.on('data', chunk => { synthErr += chunk; });
  synth.on('error', err => {
    out({ t: 'error', message: `piper failed to start: ${err.message}` });
    finishTurn();
  });
  synth.on('exit', code => {
    if (code !== 0) {
      out({ t: 'error', message: `piper exited with code ${code}${synthErr ? ': ' + synthErr.trim() : ''}` });
      finishTurn();
      return;
    }
    execFile('paplay', ['--device', SPEAKER_SINK, TTS_WAV_FILE], err => {
      if (err) out({ t: 'error', message: `paplay failed: ${err.message}` });
      finishTurn();
    });
  });
  synth.stdin.write(clean);
  synth.stdin.end();
}

function resetSession() { sessionId = null; }

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
