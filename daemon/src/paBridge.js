#!/usr/bin/env node
'use strict';
/*
 * paBridge.js — orchestrates the "PA" voice-agent turn loop: Voxtype (local speech-to-
 * text) -> `claude` CLI (a real agent, given tools via paTools/server.js) -> Piper
 * (local text-to-speech) -> a spoken/shown reply. See HISTORY.md for the design
 * brainstorm this implements — Phase A (manual push-to-talk, one tool, text reply) and
 * Phase B (this file's speak() — spoken replies) are both done; continuous "Hey Foxy"
 * mode (Phase C) and Home Assistant control (Phase D) are not.
 *
 * A second, independent daemon process from bridge.js/HidBridge.qml on purpose: this one
 * shells out to much slower, heavier, more experimental things (an LLM CLI call can take
 * several seconds) and must never be able to block or destabilize the HID/touch daemon
 * everything else in this app depends on.
 *
 * MIT-licensed: pure process/IPC orchestration, no device protocol.
 *
 * stdout: one JSON object per line, mirroring bridge.js's own shape:
 *   {"t":"state","state":{"status":"idle"|"listening"|"transcribing"|"thinking"|"speaking"}}
 *   {"t":"transcript","text":"..."}
 *   {"t":"reply","text":"..."}
 *   {"t":"error","message":"..."}
 *
 * stdin: one JSON command per line:
 *   {"cmd":"startTurn"} | {"cmd":"endTurn"} | {"cmd":"cancelTurn"} | {"cmd":"resetSession"}
 *
 * Voxtype integration deliberately uses its file-based, scriptable path rather than its
 * normal type-into-focused-window dictation behavior: `record start --file=<path>`
 * writes the transcript to a plain text file, and `record stop --wait --json` blocks
 * until transcription is final. No keyboard-injection interception needed. Uses a
 * PA-scoped Voxtype config (~/.config/voxtype/pa.toml, see ops/voxtype/pa.example.toml)
 * so this pins the panel's own mic explicitly rather than inheriting the user's everyday
 * dictation config's device/output settings.
 */
const readline = require('readline');
const path = require('path');
const os = require('os');
const fs = require('fs');
const { spawn, execFile } = require('child_process');

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

// Every tool the "quake-panel" MCP server exposes (paTools/server.js), fully qualified
// as `mcp__<serverName>__<toolName>` — confirmed live to be the exact name Claude Code's
// permission system wants (see HISTORY.md). Passed to --allowedTools below: without it,
// a non-interactive `-p` call has no human to click "allow" for, and the tool call is
// silently permission-denied instead of executed — confirmed live the hard way. Add the
// new tool's qualified name here as later phases add more.
const ALLOWED_TOOLS = ['mcp__quake-panel__start_pomodoro'];

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

function setStatus(status) { out({ t: 'state', state: { status } }); }

function startTurn() {
  if (turnInFlight) return;
  turnInFlight = true;
  try { fs.unlinkSync(TRANSCRIPT_FILE); } catch (e) { /* fine if it didn't exist yet */ }
  setStatus('listening');
  const proc = spawn('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'start', `--file=${TRANSCRIPT_FILE}`], { stdio: 'ignore' });
  proc.on('error', err => {
    turnInFlight = false;
    out({ t: 'error', message: `voxtype record start failed: ${err.message}` });
    setStatus('idle');
  });
}

function endTurn() {
  if (!turnInFlight) return;
  setStatus('transcribing');
  execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'stop', '--wait', '--json', '--timeout', '20'], (err, stdout) => {
    turnInFlight = false;
    if (err) {
      out({ t: 'error', message: `voxtype record stop failed: ${err.message}` });
      setStatus('idle');
      return;
    }
    let outcome = null;
    try { outcome = JSON.parse(stdout); } catch (e) { /* keep null, not fatal */ }
    let text = '';
    try { text = fs.readFileSync(TRANSCRIPT_FILE, 'utf8').trim(); } catch (e) { /* nothing transcribed */ }
    if (!text) {
      out({ t: 'error', message: 'Nothing transcribed' + (outcome ? ` (${JSON.stringify(outcome)})` : '') });
      setStatus('idle');
      return;
    }
    out({ t: 'transcript', text });
    askClaude(text);
  });
}

function cancelTurn() {
  turnInFlight = false;
  execFile('voxtype', ['-c', VOXTYPE_CONFIG, 'record', 'cancel'], () => setStatus('idle'));
}

function askClaude(promptText) {
  setStatus('thinking');
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
  execFile('claude', args, { cwd: os.homedir(), maxBuffer: 10 * 1024 * 1024, timeout: 60000 }, (err, stdout, stderr) => {
    if (err) {
      out({ t: 'error', message: `claude CLI failed: ${err.message}${stderr ? ' - ' + stderr : ''}` });
      setStatus('idle');
      return;
    }
    let result;
    try { result = JSON.parse(stdout); } catch (e) {
      out({ t: 'error', message: `claude CLI returned unparseable output: ${e.message}` });
      setStatus('idle');
      return;
    }
    if (result.session_id) sessionId = result.session_id;
    if (result.is_error) {
      out({ t: 'error', message: `claude reported an error: ${result.result || 'unknown'}` });
      setStatus('idle');
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
  if (!clean) { setStatus('idle'); return; }
  setStatus('speaking');
  const synth = spawn(PIPER_BIN, ['-m', PIPER_MODEL, '-f', TTS_WAV_FILE]);
  let synthErr = '';
  synth.stderr.on('data', chunk => { synthErr += chunk; });
  synth.on('error', err => {
    out({ t: 'error', message: `piper failed to start: ${err.message}` });
    setStatus('idle');
  });
  synth.on('exit', code => {
    if (code !== 0) {
      out({ t: 'error', message: `piper exited with code ${code}${synthErr ? ': ' + synthErr.trim() : ''}` });
      setStatus('idle');
      return;
    }
    execFile('paplay', ['--device', SPEAKER_SINK, TTS_WAV_FILE], err => {
      if (err) out({ t: 'error', message: `paplay failed: ${err.message}` });
      setStatus('idle');
    });
  });
  synth.stdin.write(clean);
  synth.stdin.end();
}

function resetSession() { sessionId = null; }

const COMMANDS = { startTurn, endTurn, cancelTurn, resetSession };

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

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));

writeMcpConfig();
setStatus('idle');
