import QtQuick

// Owns the knob's RGB ring lighting (daemon/src/Aris68Connector.js's QMK VIA lighting
// commands: setLedEffect/setLedColor/setLedBrightness/saveLighting/getLighting — see
// that file's own comments for the exact wire protocol). The device is the source of
// truth: this queries it once at startup (getLighting) rather than keeping its own
// persisted preference file, and saveLighting() flashes a chosen color so it survives a
// power cycle without this app's help.
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

    function setColor(hue, sat) {
        root.hue = hue
        root.sat = sat
        root.effect = root.solidColorEffect
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedEffect", index: root.solidColorEffect })
        root.hidBridge.sendCommand({ cmd: "setLedColor", hue: hue, sat: sat })
        root.hidBridge.sendCommand({ cmd: "saveLighting" })
    }

    function setOff() {
        root.effect = root.offEffect
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedEffect", index: root.offEffect })
        root.hidBridge.sendCommand({ cmd: "saveLighting" })
    }

    // Brightness applies regardless of effect — harmless to set while the ring is off,
    // it just takes effect whenever a color is picked again.
    //
    // Called on every Ui/Slider "settled" tick while dragging (throttled there, but
    // still potentially several times a second) — sends the live brightness write every
    // time, but flash-persists (saveLighting) only once the dragging actually stops, via
    // a separate, longer debounce. Flash writes have real endurance limits; a slider
    // shouldn't spend them on every intermediate position during one drag.
    function previewBrightness(value) {
        root.brightness = value
        root.loaded = true
        root.hidBridge.sendCommand({ cmd: "setLedBrightness", value: value })
        root._saveBrightnessDebounce.restart()
    }
    property Timer _saveBrightnessDebounce: Timer {
        interval: 700
        repeat: false
        onTriggered: root.hidBridge.sendCommand({ cmd: "saveLighting" })
    }

    function refresh() {
        root.hidBridge.sendCommand({ cmd: "getLighting" })
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
                root.brightness = l.brightness
                root.loaded = true
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
