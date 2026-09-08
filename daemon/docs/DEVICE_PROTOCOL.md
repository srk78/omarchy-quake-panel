# DK-QUAKE / ARIS-68 protocol — see the source spec

The full reverse-engineered protocol (HID interfaces, frame format, opcodes,
checksums, touch/knob/RGB-ring semantics, validated hex frames from real
hardware) lives in **Bedrock Panel's `docs/DEVICE_PROTOCOL.md`**:

https://github.com/TeeJS/bedrock-panel/blob/main/docs/DEVICE_PROTOCOL.md

`../src/Aris68Connector.js` in this repo is a straight port of that project's
`src/Aris68Connector.js` (same file, adapted for Linux/`uinput` instead of
Windows/Electron — see `../src/uinputTouch.js`). Do not fork-and-drift this
document; if the protocol spec needs updating, update it upstream and re-port.

Licensing: this protocol is PolyForm Noncommercial 1.0.0 — see `../LICENSE`.
