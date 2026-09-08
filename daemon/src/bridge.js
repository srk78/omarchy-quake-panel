#!/usr/bin/env node
'use strict';
/*
 * bridge.js — CLI adapter around Aris68Connector, for Quickshell (or anything else) to
 * drive over stdio instead of requiring node-hid in-process.
 *
 * MIT-licensed: this file is pure process/IPC orchestration and embeds no device protocol
 * itself (see ../LICENSE and ../../NOTICE) — Aris68Connector.js is the PolyForm-scoped file.
 *
 * stdout: one JSON object per line, e.g.
 *   {"t":"touch","points":[{"action":1,"x":812,"y":301}]}
 *   {"t":"knob","event":{"type":"rotate","dir":1}}
 *   {"t":"knob","event":{"type":"press","index":1}}
 *   {"t":"knob","event":{"type":"hold","phase":"start"}}
 *   {"t":"state","state":{"firmware":"1.0.19"}}
 *   {"t":"connect","iface":"control"} | {"t":"disconnect","iface":"touch"}
 *   {"t":"error","message":"..."}
 *
 * stdin: one JSON command per line, e.g.
 *   {"cmd":"screenOn"} | {"cmd":"screenOff"} | {"cmd":"ping"}
 *   {"cmd":"queryFirmware"} | {"cmd":"queryMic"} | {"cmd":"queryLuminance"}
 *   {"cmd":"setMic","on":true} | {"cmd":"buzzer","tone":100} | {"cmd":"setKnobLed","on":true}
 *   {"cmd":"setLedBrightness","value":200} | {"cmd":"setLedEffect","index":3}
 *   {"cmd":"setLedSpeed","value":128} | {"cmd":"setLedColor","hue":128,"sat":255}
 *   {"cmd":"saveLighting"}
 * ("enterDfu" is intentionally NOT wired to a command — see Aris68Connector.js's own
 * warning; sending it puts the device into firmware-flash mode and can brick it.)
 */
const readline = require('readline');
const Aris68Connector = require('./Aris68Connector');
const UinputTouch = require('./uinputTouch');

const dev = new Aris68Connector();

function out(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }

// Real touch delivery: a virtual /dev/uinput touchscreen (see uinputTouch.js for why —
// the panel's touch HID report is vendor-defined, not a standard digitizer). Best-effort:
// if /dev/uinput isn't accessible, log it and keep running in JSON-only debug mode rather
// than crash the whole daemon (knob still works either way).
const uinputTouch = new UinputTouch();
try { uinputTouch.start(); out({ t: 'state', state: { uinput: true } }); }
catch (e) { out({ t: 'error', message: `uinput unavailable, touch will be JSON-only: ${e.message}` }); }

dev.on('touch', points => {
  try { uinputTouch.feed(points); } catch (e) { out({ t: 'error', message: `uinput feed failed: ${e.message}` }); }
  out({ t: 'touch', points });
});
dev.on('knob', event => out({ t: 'knob', event }));
dev.on('key', event => out({ t: 'key', event }));
dev.on('state', state => out({ t: 'state', state }));
dev.on('connect', info => out({ t: 'connect', iface: info.iface }));
dev.on('disconnect', info => out({ t: 'disconnect', iface: info.iface }));
dev.on('error', err => out({ t: 'error', message: err && err.message ? err.message : String(err) }));

const COMMANDS = {
  screenOn: () => dev.screenOn(),
  screenOff: () => dev.screenOff(),
  ping: () => dev.ping(),
  queryFirmware: () => dev.queryFirmware(),
  queryMic: () => dev.queryMic(),
  queryLuminance: () => dev.queryLuminance(),
  setMic: c => dev.setMic(!!c.on),
  buzzer: c => dev.buzzer(c.tone),
  setKnobLed: c => dev.setKnobLed(!!c.on),
  setBrightness: c => dev.setBrightness(c.value),
  setLedBrightness: c => dev.setLedBrightness(c.value),
  setLedEffect: c => dev.setLedEffect(c.index),
  setLedSpeed: c => dev.setLedSpeed(c.value),
  setLedColor: c => dev.setLedColor(c.hue, c.sat),
  saveLighting: () => dev.saveLighting(),
  getLighting: async () => out({ t: 'state', state: { lighting: await dev.getLighting() } }),
};

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', line => {
  line = line.trim();
  if (!line) return;
  let cmd;
  try { cmd = JSON.parse(line); } catch (e) { return out({ t: 'error', message: `bad command JSON: ${e.message}` }); }
  const fn = cmd && COMMANDS[cmd.cmd];
  if (!fn) return out({ t: 'error', message: `unknown command: ${cmd && cmd.cmd}` });
  try { fn(cmd); } catch (e) { out({ t: 'error', message: e.message }); }
});

process.on('SIGINT', () => { dev.stop(); uinputTouch.stop(); process.exit(0); });
process.on('SIGTERM', () => { dev.stop(); uinputTouch.stop(); process.exit(0); });

dev.start();
