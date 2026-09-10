#!/usr/bin/env node
'use strict';
/*
 * paBridge.js — orchestrates the "PA" voice-agent turn loop: Voxtype (local speech-to-
 * text) -> `claude` CLI (a real agent, given tools via paTools/server.js) -> a spoken/
 * shown reply. See HISTORY.md for the design brainstorm this implements (Phase A: manual
 * push-to-talk, one tool, text reply only — no TTS yet, no wake word yet).
 *
 * A second, independent daemon process from bridge.js/HidBridge.qml on purpose: this one
 * shells out to much slower, heavier, more experimental things (an LLM CLI call can take
 * several seconds) and must never be able to block or destabilize the HID/touch daemon
 * everything else in this app depends on.
 *
 * MIT-licensed: pure process/IPC orchestration, no device protocol.
 *
 * stdout: one JSON object per line, mirroring bridge.js's own shape:
 *   {"t":"state","state":{"status":"idle"|"listening"|"transcribing"|"thinking"}}
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
    setStatus('idle');
  });
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
