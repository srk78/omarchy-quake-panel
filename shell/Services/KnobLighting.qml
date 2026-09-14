import QtQuick
import Quickshell
import Quickshell.Io

// Owns the knob's RGB ring lighting (daemon/src/Aris68Connector.js's QMK VIA lighting
// commands: setLedEffect/setLedColor/setLedBrightness/saveLighting/getLighting — see
// that file's own comments for the exact wire protocol).
//
// The device is queried at startup (getLighting) as the primary source of truth for
// display (Settings page swatches/slider) — but NOT the sole source of truth anymore.
// `saveLighting()` (VIA 0x09, "save to flash") does not reliably survive a real power
// cycle on this exact firmware — confirmed live, twice, on real hardware (2026-09-14):
// neither an immediate save nor a save gated on the device's own getLighting()
// confirming the new value had already taken effect internally (ruling out a timing
// race — the RAM-resident value was always correct; only the "flash" part didn't
// stick) made a chosen color survive an actual power-off. A sibling project driving
// the same hardware (bedrock-panel) independently confirms the same command bytes but
// never actually exercises this exact save-then-power-cycle path either — plausibly a
// firmware-level gap in this board's VIA implementation, not something fixable from
// software. Worked around instead of endlessly chased: this file now ALSO keeps its
// own persisted preference (`~/.local/state/omarchy-quake-panel/knob-lighting.json`,
// same pattern as Service.qml's mode.json / PersonalCareState.qml's own state file)
// and re-applies it whenever the daemon reconnects if the device's own reported state
// doesn't match — so a post-power-cycle boot default gets corrected automatically
// within moments of the app reconnecting, without depending on the device's own flash
// working at all.
//
// EFFECT INDEX CAVEAT: this device's exact RGB-Matrix effect list isn't documented —
// Aris68Connector.js's own comment only says "0=All Off … 43 (RGB-Matrix list)", no
// names. `solidColorEffect` below (1) is the conventional first non-off entry in QMK's
// stock rgb_matrix_effects enum, not something verified against this exact firmware. If
// a chosen preset doesn't render as a stable solid color on the real ring (e.g. it
// animates/cycles instead), this is the constant to revisit — see NEXT_STEPS.md.
QtObject {
    id: root
    required property var hidBridge

    readonly property int offEffect: 0     // "All Off" per Aris68Connector.js's own comment
    readonly property int solidColorEffect: 1 // see EFFECT INDEX CAVEAT above

    // True once a real getLighting() reply has updated hue/sat/effect/brightness below —
    // until then, the Settings page can't know which preset (if any) is actually active.
    property bool loaded: false
    property int hue: 0
    property int sat: 255
    property int effect: -1 // -1 = unknown until the first real reply
    property int brightness: 0 // 0..brightnessMax; see setLedBrightness's own comment below

    // setLedBrightness's own comment: "device quantizes; max ~247" — the slider stays
    // under that ceiling rather than assuming the full 0-255 byte range is usable.
    readonly property int brightnessMin: 0
    readonly property int brightnessMax: 247

    // A handful of well-separated hues at full saturation, a desaturated white, and
    // "None" to turn the ring off entirely (a different effect, not just black/sat=0 —
    // see setOff()). hue/sat are QMK's 0-255 byte range, not degrees/percent.
    readonly property var presets: [
        { name: "Red", hue: 0, sat: 255 },
        { name: "Orange", hue: 28, sat: 255 },
        { name: "Yellow", hue: 43, sat: 255 },
        { name: "Green", hue: 85, sat: 255 },
        { name: "Cyan", hue: 128, sat: 255 },
        { name: "Blue", hue: 170, sat: 255 },
        { name: "Purple", hue: 191, sat: 255 },
        { name: "Pink", hue: 224, sat: 255 },
        { name: "White", hue: 0, sat: 0 },
        { name: "None", off: true },
    ]

    // A color preset only reads as "current" if the ring is actually in solid-color mode
    // — otherwise a ring that's currently off but remembers an old hue/sat internally
    // would wrongly highlight whatever color it happens to still be holding.
    function isCurrent(hue, sat) {
        return root.loaded && root.effect === root.solidColorEffect
            && Math.abs(root.hue - hue) < 4 && Math.abs(root.sat - sat) < 4
    }
    function isOff() {
        return root.loaded && root.effect === root.offEffect
    }

    // setColor()/setOff() used to fire saveLighting() immediately after setLedEffect/
    // setLedColor, back to back with no gap — confirmed live (2026-09-14, the first time
    // this project ever tested a real power cycle rather than just a software restart)
    // that this doesn't reliably persist: the ring came back cycling through colors
    // (a firmware boot default) instead of the chosen solid color, even though the
    // effect index itself was confirmed fine (settled into the correct static color as
    // soon as the app re-sent it). Every earlier "verified" round-trip in this project
    // only ever restarted the *software* (`omarchy-restart-shell`), which never actually
    // powers the device off — so a save that raced ahead of the color/effect actually
    // being applied internally, and therefore flashed stale data, was completely masked:
    // the device's own RAM-resident state was never lost, so it kept looking right.
    // A fixed short delay before saveLighting() (matching previewBrightness()'s own
    // debounce) did NOT fix it either — confirmed live a second time — ruling out a
    // simple race that any small constant wait would paper over.
    //
    // Fixed properly instead of guessing a bigger number: wait for the device's own
    // getLighting() reply to actually confirm the new effect/color took effect
    // internally before persisting it — "verify, don't guess," this project's own
    // standing discipline, applied to timing instead of just glyphs/APIs this time.
    // A sibling project driving the same hardware (bedrock-panel, see its
    // DEVICE_PROTOCOL.md §10 — independently confirms 0x07/0x08/0x09 set/get/save) never
    // chains save right after set at all; it's a fully separate, user-triggered action,
    // which is a much more natural (if implicit) version of the same "give it time"
    // idea. This makes that wait explicit and bounded by a real confirmation instead of
    // an arbitrary gap or a manual button.
    property var _pendingSave: null // {effect, hue, sat} (hue/sat null when irrelevant, e.g. setOff) to match before saving
    property Timer _pendingSaveTimeout: Timer {
        interval: 5000 // generous: getLighting()'s own 4 sequential field reads can take up to ~2.8s worst case
        repeat: false
        onTriggered: {
            // No confirmation arrived in time — save anyway rather than silently never
            // persisting at all; one possibly-stale save beats none.
            root._pendingSave = null
            root.hidBridge.sendCommand({ cmd: "saveLighting" })
        }
    }
    function _armSaveOnConfirm(effect, hue, sat) {
        root._pendingSave = { effect: effect, hue: hue === undefined ? null : hue, sat: sat === undefined ? null : sat }
        root._pendingSaveTimeout.restart()
        root.refresh()
    }

    function setColor(hue, sat) {
        root.hue = hue
        root.sat = sat
        root.effect = root.solidColorEffect
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedEffect", index: root.solidColorEffect })
        root.hidBridge.sendCommand({ cmd: "setLedColor", hue: hue, sat: sat })
        root._persistPreference(root.solidColorEffect, hue, sat, root.brightness)
        root._armSaveOnConfirm(root.solidColorEffect, hue, sat)
    }

    function setOff() {
        root.effect = root.offEffect
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedEffect", index: root.offEffect })
        root._persistPreference(root.offEffect, root.hue, root.sat, root.brightness)
        root._armSaveOnConfirm(root.offEffect, null, null) // color is irrelevant once off
    }

    // Brightness applies regardless of effect — harmless to set while the ring is off,
    // it just takes effect whenever a color is picked again.
    //
    // Called on every Ui/Slider "settled" tick while dragging (throttled there, but
    // still potentially several times a second) — sends the live brightness write every
    // time, but only arms a confirm-then-save for the final value once dragging
    // actually stops (each new call re-arms, so a mid-drag value is never the one
    // waited on). Flash writes have real endurance limits; a slider shouldn't spend one
    // on every intermediate position during one drag.
    function previewBrightness(value) {
        root.brightness = value
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedBrightness", value: value })
        root._persistPreference(root.effect, root.hue, root.sat, value)
        root._armSaveOnConfirm(root.effect, root.hue, root.sat) // brightness isn't itself matched below; just needs *a* fresh confirm round-trip
    }

    function refresh() {
        root.hidBridge.sendCommand({ cmd: "getLighting" })
    }

    // ---- local persisted preference (see this file's own header comment for why) ----
    readonly property string _statePath: Quickshell.env("HOME") + "/.local/state/omarchy-quake-panel/knob-lighting.json"
    property var _savedPreference: null // {effect, hue, sat, brightness}, or null before the first load/save
    property bool _preferenceLoaded: false

    function _persistPreference(effect, hue, sat, brightness) {
        root._savedPreference = { effect: effect, hue: hue, sat: sat, brightness: brightness }
        root._preferenceLoaded = true
        _preferenceFile.setText(JSON.stringify(root._savedPreference))
    }
    function _loadPreference(text) {
        try {
            var parsed = JSON.parse(text || "null")
            if (parsed && typeof parsed.effect === "number") root._savedPreference = parsed
        } catch (e) { /* keep null, nothing to reconcile against yet */ }
        root._preferenceLoaded = true
    }
    property FileView _preferenceFile: FileView {
        path: root._statePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root._loadPreference(text())
        onLoadFailed: function (error) { root._loadPreference("") }
    }

    // Whenever a fresh device reading arrives and it disagrees with what we last chose
    // — e.g. a real power cycle reverted the ring to its firmware boot default — push
    // our own remembered preference back onto the device and (re-)arm a save. Skipped
    // while a save the USER just requested is still in flight (_pendingSave) so this
    // never fights an in-progress, deliberate change with a now-stale comparison.
    function _reconcileWithSavedPreference(l) {
        if (!root._preferenceLoaded || !root._savedPreference || root._pendingSave) return
        var p = root._savedPreference
        var colorRelevant = p.effect === root.solidColorEffect
        var effectMismatch = l.effect !== undefined && l.effect !== p.effect
        var colorMismatch = colorRelevant && l.hue !== undefined && l.sat !== undefined
            && (Math.abs(l.hue - p.hue) >= 4 || Math.abs(l.sat - p.sat) >= 4)
        if (!effectMismatch && !colorMismatch) return
        root.hidBridge.sendCommand({ cmd: "setLedEffect", index: p.effect })
        if (colorRelevant) root.hidBridge.sendCommand({ cmd: "setLedColor", hue: p.hue, sat: p.sat })
        if (p.brightness !== undefined) root.hidBridge.sendCommand({ cmd: "setLedBrightness", value: p.brightness })
        root._armSaveOnConfirm(p.effect, colorRelevant ? p.hue : null, colorRelevant ? p.sat : null)
    }

    // Bare Connections {} would fail here — QtObject (unlike Item) has no default
    // property to assign an unnamed child to, so every non-visual child in this file
    // (matching PersonalCareState.qml's own Timer/FileView/Process pattern) needs an
    // explicit property name.
    property Connections _stateConn: Connections {
        target: root.hidBridge
        function onStateEvent(state) {
            if (!state || !state.lighting) return
            var l = state.lighting
            if (l.hue !== undefined && l.sat !== undefined) {
                root.hue = l.hue
                root.sat = l.sat
                root.loaded = true
            }
            if (l.effect !== undefined) {
                root.effect = l.effect
                root.loaded = true
            }
            if (l.brightness !== undefined) {
                // The device reports a raw, unclamped byte (0-255) — confirmed live: a
                // stale/factory value above brightnessMax showed as 103% on the Settings
                // page. Clamped here, at the source, so no consumer (the percentage
                // label, the Slider's own position) can ever see an out-of-range value.
                // Deliberately doesn't write a corrected value back to the device — that
                // would be an unrequested hardware action; only the display is corrected.
                root.brightness = Math.min(root.brightnessMax, Math.max(root.brightnessMin, l.brightness))
                root.loaded = true
            }

            if (root._pendingSave) {
                var p = root._pendingSave
                var effectOk = l.effect === undefined || l.effect === p.effect
                var hueOk = p.hue === null || l.hue === undefined || Math.abs(l.hue - p.hue) < 4
                var satOk = p.sat === null || l.sat === undefined || Math.abs(l.sat - p.sat) < 4
                if (effectOk && hueOk && satOk) {
                    root._pendingSave = null
                    root._pendingSaveTimeout.stop()
                    root.hidBridge.sendCommand({ cmd: "saveLighting" })
                }
            } else {
                root._reconcileWithSavedPreference(l)
            }
        }
    }

    // Query the ring's actual current color once the daemon is up, so the Settings page
    // reflects hardware truth instead of a guessed default.
    property Connections _connectedConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root.refresh() }
    }
}
