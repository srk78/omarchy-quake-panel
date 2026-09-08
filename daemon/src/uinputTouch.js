'use strict';
/*
 * uinputTouch — synthesizes a real kernel touchscreen from the panel's raw touch reports.
 *
 * The panel's touch HID interface uses a vendor-defined usage page (0xFF73), not the
 * standard Digitizer/Touchscreen usage — so it never shows up as a genuine input device
 * to the OS on its own (see ../docs/DEVICE_PROTOCOL.md). This module creates a virtual
 * multitouch device via /dev/uinput fed from Aris68Connector's decoded touch points, so
 * Hyprland/libinput — and anything a Quickshell window embeds, e.g. a WebEngineView —
 * get ordinary touch input with no custom hit-testing. Validated live: the device shows
 * up in /proc/bus/input/devices and in `hyprctl devices` as a real Touch Device.
 *
 * No native compilation: uses `koffi` (prebuilt-binary FFI) to call the handful of libc
 * `ioctl()` setup calls, and the classic `uinput_user_dev` write-based setup API (not the
 * newer UI_DEV_SETUP/UI_ABS_SETUP ioctls, which encode struct size into the ioctl request
 * number and are more fragile to hand-derive) — this avoids needing a native addon or a
 * node-gyp build, which the unmaintained `uinput` npm package requires and which fails to
 * build against modern Node (V8 API changes; confirmed failing on Node 24).
 *
 * Coordinate handling: device reports x:0..1920, y:0..480 with origin BOTTOM-LEFT; the
 * screen is top-left origin, so Y is flipped here: yOut = (SCREEN_H - 1) - y.
 *
 * Touch-ID tracking: raw reports carry no persistent per-finger ID (the vendor's own
 * DK-Suite did its own nearest-neighbour tracking, per ../docs/DEVICE_PROTOCOL.md §4) —
 * this module does the same so the kernel's MT protocol (which needs a stable
 * ABS_MT_TRACKING_ID per contact across frames) gets sensible slot assignment.
 *
 * PolyForm Noncommercial 1.0.0 — see ../LICENSE. Derives from the reverse-engineered
 * touch report's coordinate system/orientation.
 */
const fs = require('fs');
const koffi = require('koffi');

const libc = koffi.load('libc.so.6');
const ioctl = libc.func('int ioctl(int fd, unsigned long request, int arg)');

// uinput ioctl constants (stable kernel ABI, linux/uinput.h)
const UI_SET_EVBIT = 0x40045564;
const UI_SET_ABSBIT = 0x40045567;
const UI_SET_PROPBIT = 0x4004556e;
const UI_DEV_CREATE = 0x5501;
const UI_DEV_DESTROY = 0x5502;

const EV_SYN = 0, EV_ABS = 3;
const ABS_MT_SLOT = 0x2f, ABS_MT_TRACKING_ID = 0x39, ABS_MT_POSITION_X = 0x35, ABS_MT_POSITION_Y = 0x36;
const SYN_REPORT = 0;
const INPUT_PROP_DIRECT = 0x01;
const ABS_CNT = 64;

const SCREEN_W = 1920, SCREEN_H = 480;
const MAX_SLOTS = 4;          // generous for a kiosk touchscreen (realistically 1-2 fingers)
const MATCH_DIST = 99;        // mirrors the vendor's own nearest-neighbour threshold (§4)
const STALE_MS = 400;         // a slot with no down/move refresh in this long is assumed abandoned

function buildUserDev(name) {
  const buf = Buffer.alloc(80 + 8 + 4 + ABS_CNT * 4 * 4);
  buf.write(name, 0, 'ascii');
  buf.writeUInt16LE(0x03, 80);      // bustype BUS_USB
  buf.writeUInt16LE(0x1209, 82);    // vendor: pid.codes shared block, matches the Bedrock knob's own convention
  buf.writeUInt16LE(0x0001, 84);    // product
  buf.writeUInt16LE(1, 86);         // version
  buf.writeUInt32LE(0, 88);         // ff_effects_max
  const absmaxOff = 92;
  buf.writeInt32LE(SCREEN_W - 1, absmaxOff + ABS_MT_POSITION_X * 4);
  buf.writeInt32LE(SCREEN_H - 1, absmaxOff + ABS_MT_POSITION_Y * 4);
  buf.writeInt32LE(MAX_SLOTS - 1, absmaxOff + ABS_MT_SLOT * 4);
  buf.writeInt32LE(65535, absmaxOff + ABS_MT_TRACKING_ID * 4);
  return buf;
}

class UinputTouch {
  constructor(opts = {}) {
    this.devicePath = opts.devicePath || '/dev/uinput';
    this.name = opts.name || 'omarchy-quake-panel-touch';
    this.fd = null;
    this.slots = new Array(MAX_SLOTS).fill(null); // {x,y,trackingId} or null when free
    this._nextTrackingId = 1;
    this._currentSlot = -1; // mirrors the kernel MT-B protocol's "current slot" cursor
  }

  start() {
    if (this.fd !== null) return;
    const fd = fs.openSync(this.devicePath, 'w');
    const chk = (name, r) => { if (r < 0) { fs.closeSync(fd); throw new Error(`uinput ${name} ioctl failed`); } };
    // Pure MT-B protocol only — no EV_KEY/BTN_TOUCH, no legacy single-touch ABS_X/ABS_Y.
    // Declaring those turns this into something libinput can treat as a generic pointer
    // (not scoped to the panel's output), so a missed release doesn't just break the next
    // touch on this device — it can look like a mouse button stuck down system-wide.
    // Reproduced live: text selection broke everywhere, not just on the panel, after a
    // missed release. INPUT_PROP_DIRECT + ABS_MT_* alone is the correct way to declare a
    // touchscreen and keeps libinput from ever treating this as a pointer device.
    chk('EVBIT ABS', ioctl(fd, UI_SET_EVBIT, EV_ABS));
    chk('ABSBIT MT_SLOT', ioctl(fd, UI_SET_ABSBIT, ABS_MT_SLOT));
    chk('ABSBIT MT_TRACKING_ID', ioctl(fd, UI_SET_ABSBIT, ABS_MT_TRACKING_ID));
    chk('ABSBIT MT_POSITION_X', ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_X));
    chk('ABSBIT MT_POSITION_Y', ioctl(fd, UI_SET_ABSBIT, ABS_MT_POSITION_Y));
    chk('PROPBIT DIRECT', ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_DIRECT));
    fs.writeSync(fd, buildUserDev(this.name));
    chk('DEV_CREATE', ioctl(fd, UI_DEV_CREATE, 0));
    this.fd = fd;
    return this;
  }

  stop() {
    if (this.fd === null) return;
    try { ioctl(this.fd, UI_DEV_DESTROY, 0); } catch (e) {}
    try { fs.closeSync(this.fd); } catch (e) {}
    this.fd = null;
  }

  _emit(type, code, value) {
    const ev = Buffer.alloc(24); // struct input_event on 64-bit: timeval(16) + type/code/value(8)
    ev.writeUInt16LE(type, 16);
    ev.writeUInt16LE(code, 18);
    ev.writeInt32LE(value, 20);
    fs.writeSync(this.fd, ev);
  }
  _selectSlot(i) { if (this._currentSlot !== i) { this._emit(EV_ABS, ABS_MT_SLOT, i); this._currentSlot = i; } }
  _findNearestSlot(x, y) {
    let best = -1, bestDist = Infinity;
    for (let i = 0; i < this.slots.length; i++) {
      const s = this.slots[i];
      if (!s) continue;
      const d = Math.hypot(s.x - x, s.y - y);
      if (d <= MATCH_DIST && d < bestDist) { bestDist = d; best = i; }
    }
    return best;
  }
  _freeSlot() { return this.slots.findIndex(s => s === null); }
  _activeCount() { return this.slots.reduce((n, s) => n + (s ? 1 : 0), 0); }
  _release(slot) {
    this._selectSlot(slot);
    this._emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
    this.slots[slot] = null;
  }

  // A held finger keeps re-reporting (we saw this live: rapid repeated identical touch
  // lines while a finger stays down) — anything that hasn't been refreshed in STALE_MS is
  // safe to assume abandoned. Guards against any missed/malformed "up" report leaving a
  // slot stuck forever, which — since MAX_SLOTS is small — silently breaks ALL future
  // touches once every slot is wedged (reproduced live: worked a few taps, then stopped).
  // Confirmed live: this hardware appears to never send an explicit "up" report at all
  // (every capture across this whole bring-up showed action=1 only) — so this timeout is
  // the ONLY release mechanism in practice, not just a backstop for a rare missed report.
  // Returns true if anything was released, so the caller can flush a SYN_REPORT for it.
  _reapStale(now) {
    let released = false;
    for (let i = 0; i < this.slots.length; i++) {
      const s = this.slots[i];
      if (s && now - s.lastSeen > STALE_MS) { this._release(i); released = true; }
    }
    return released;
  }

  /** Feed one Aris68Connector 'touch' event batch: [{action(1=down,0=up), x(0..1920), y(0..480, origin bottom-left)}, ...] */
  feed(points) {
    if (this.fd === null) return;
    const now = Date.now();
    // A release and the press that follows it must land in SEPARATE sync frames — bundling
    // "slot N released, slot N (re)pressed" into one SYN_REPORT is an edge case libinput's
    // touch-tracking may not handle as two distinct contacts (reproduced live: switching
    // between two spots on this panel worked exactly once, then stopped, which stopped
    // reproducing once every release got its own flushed sync frame here).
    if (this._reapStale(now)) this._emit(EV_SYN, SYN_REPORT, 0);
    for (const p of points) {
      const x = Math.max(0, Math.min(SCREEN_W - 1, Math.round(p.x)));
      const y = (SCREEN_H - 1) - Math.max(0, Math.min(SCREEN_H - 1, Math.round(p.y))); // bottom-left -> top-left
      if (p.action === 1) {
        let slot = this._findNearestSlot(x, y);
        if (slot === -1) {
          // A genuinely new, distant contact. This hardware is realistically single-touch
          // (validated: "no physical keys... one big touchscreen + a knob", no intentional
          // multi-touch UI) — release any other still-active slot first rather than allow
          // two simultaneous contacts to coexist. Reproduced live: an incompletely-released
          // prior tap left a phantom slot active elsewhere on screen, so the next distant
          // tap became an unintended 2-finger gesture instead of a click, and didn't
          // register until the phantom timed out.
          let releasedAny = false;
          for (let i = 0; i < this.slots.length; i++) if (this.slots[i]) { this._release(i); releasedAny = true; }
          if (releasedAny) this._emit(EV_SYN, SYN_REPORT, 0); // own sync frame — see note above
          slot = this._freeSlot();
          if (slot === -1) continue; // unreachable now that the loop above frees everything, kept for safety
          this._selectSlot(slot);
          const id = this._nextTrackingId++;
          this.slots[slot] = { x, y, trackingId: id, lastSeen: now };
          this._emit(EV_ABS, ABS_MT_TRACKING_ID, id);
        } else {
          this._selectSlot(slot);
          this.slots[slot].x = x; this.slots[slot].y = y; this.slots[slot].lastSeen = now;
        }
        this._emit(EV_ABS, ABS_MT_POSITION_X, x);
        this._emit(EV_ABS, ABS_MT_POSITION_Y, y);
      } else {
        let slot = this._findNearestSlot(x, y);
        // Fallback: an "up" report's coordinates aren't guaranteed to land within
        // MATCH_DIST of the slot's last known position (this hardware has never actually
        // been observed sending an "up" report at all in bring-up testing — see _reapStale
        // — so this branch is speculative, kept in case some firmware/mode does send one).
        // With only one contact down, there's no ambiguity about which slot it must be.
        if (slot === -1 && this._activeCount() === 1) slot = this.slots.findIndex(s => s !== null);
        if (slot === -1) continue;
        this._release(slot);
      }
    }
    this._emit(EV_SYN, SYN_REPORT, 0);
  }
}

module.exports = UinputTouch;
