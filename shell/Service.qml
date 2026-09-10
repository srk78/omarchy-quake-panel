import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "Services"
import "Ui"

// Omarchy Quake Panel — the real Omarchy shell plugin entry point (see manifest.json:
// kinds: ["service"], entryPoints.service). Loaded once, at startup, inside the single
// long-running `omarchy-shell` process — mirrors plugins/background/Background.qml's own
// shape (a plain Item that owns its own PanelWindow(s) with full WlrLayershell control),
// which is the closest first-party precedent for "an always-on service that also draws a
// pinned, layer-shell-anchored window."
//
// This plugin owns one persisted mode flag, "kiosk" or "desktop":
//   - "kiosk": mounts a PanelWindow pinned to the DK-QUAKE output (Overlay layer +
//     ignored exclusion zone, exactly as before) running the Dashboard/Self Care pages.
//   - "desktop": mounts nothing. Omarchy's own bar and background already render on
//     every connected output today, including this one (confirmed live, underneath the
//     kiosk window, before this plugin existed) — removing our own window is the entire
//     mechanism, no extra code needed to make the output behave like an ordinary second
//     screen Hyprland can place windows on.
//
// The daemon connection (knob + touch JSON) and PersonalCareState/SystemStats keep
// running in BOTH modes — this is what lets the knob's long-hold gesture toggle back
// into kiosk mode with no window present to read it from, and what lets pomodoro/water/
// stand timers keep counting while the screen is a desktop.
//
// The /dev/uinput virtual touchscreen (daemon's setVirtualTouch command) is the one
// exception — it's only ever turned ON in "desktop" mode. This app's own kiosk UI never
// needed it: TouchRouter.qml reads touch directly from the same daemon JSON, bypassing
// the OS input path entirely, which is the whole reason it exists (see its own header
// comment). Only "desktop" mode's ordinary windows need a real kernel touch device.
// Confirmed live (2026-09-10) that this virtual device's touch was reaching the WRONG
// output — the primary/laptop screen, not the panel — despite every Hyprland-level fix
// attempted (per-device and global `touchdevice:output` binding, both verified active
// via `hyprctl getoption`; multiple fresh device reconnects; a full session restart).
// Turning it off for the mode that never needed it removes the actively disruptive
// symptom without depending on ever tracking down the Hyprland-side root cause — see
// HISTORY.md and NEXT_STEPS.md for the full diagnostic trail before touching this again.
//
// shell/shell.qml is kept alongside this file as a separate, standalone entry point for
// fast dev/screenshot iteration (`quickshell -p shell/shell.qml`, what
// .claude/skills/omarchy-design/scripts/capture-panel.sh drives) — reloading the whole
// omarchy-shell process on every styling tweak would be far slower.
Item {
    id: root

    // Every QML document resolves relative URLs against its OWN location, regardless of
    // which process loaded it — unlike Quickshell.shellDir, which points at the WHOLE
    // process's entry file (Omarchy's own shell/shell.qml once this runs as a plugin, not
    // this file). This is what lets the daemon be found at a fixed relative path no matter
    // where this plugin's checkout lives (a standalone quickshell -p run, or cloned into
    // ~/.config/omarchy/plugins/<id>/ by `omarchy plugin add`).
    readonly property string _selfDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
    readonly property string daemonPath: root._selfDir + "../daemon/src/bridge.js"
    readonly property var panelScreen: Quickshell.screens.find(function (s) {
        return s.name === "DP-1" || s.model === "DK-QUAKE"
    }) || Quickshell.screens[0]

    // ---- Always-on, regardless of mode ----
    property HidBridge hidBridge: HidBridge { daemonPath: root.daemonPath }
    property SystemStats systemStats: SystemStats {}
    property PersonalCareState personalCareState: PersonalCareState {}
    property KnobLighting knobLighting: KnobLighting { hidBridge: root.hidBridge }
    property MicState micState: MicState { hidBridge: root.hidBridge }
    property ScreenBrightness screenBrightness: ScreenBrightness { hidBridge: root.hidBridge }
    property Theme theme: Theme {}

    readonly property string _modePath: Quickshell.env("HOME") + "/.local/state/omarchy-quake-panel/mode.json"
    property string mode: "kiosk" // "kiosk" | "desktop"
    property bool _modeLoaded: false

    function _persistMode() {
        if (!root._modeLoaded) return // don't overwrite a real on-disk mode before the initial load completes
        modeFile.setText(JSON.stringify({ mode: root.mode }))
    }
    function _loadMode(text) {
        try {
            var parsed = JSON.parse(text || "{}")
            if (parsed.mode === "kiosk" || parsed.mode === "desktop") root.mode = parsed.mode
        } catch (e) { /* keep default */ }
        root._modeLoaded = true
    }
    function setMode(next) {
        if (next !== "kiosk" && next !== "desktop") return
        root.mode = next
        root._persistMode()
    }
    function toggleMode() { root.setMode(root.mode === "kiosk" ? "desktop" : "kiosk") }

    // Keep the daemon's virtual touch device in sync with mode — see the header comment
    // above for why this exists at all. Fires on every mode change (however it happens
    // — setMode(), toggleMode(), or loading a persisted value) via QML's own property
    // change notification, and once more as soon as the daemon actually connects, since
    // the very first mode value (the compiled-in "kiosk" default, before _loadMode()
    // even runs) needs to reach a daemon that wasn't listening yet at Component
    // construction time.
    function _syncVirtualTouch() {
        root.hidBridge.sendCommand({ cmd: "setVirtualTouch", on: root.mode === "desktop" })
    }
    onModeChanged: root._syncVirtualTouch()
    property Connections _virtualTouchConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root._syncVirtualTouch() }
    }

    property FileView modeFile: FileView {
        path: root._modePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root._loadMode(text())
        onLoadFailed: function (error) { root._loadMode("") }
    }
    property Process _mkdirProc: Process {
        command: [ "mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy-quake-panel" ]
        running: true
    }

    // Physical mode-toggle gesture: hold the knob for LONG_HOLD_MS — well past the
    // existing short hold (opens the water picker from any page, see KnobRouter.qml,
    // unchanged) — to flip kiosk/desktop from the hardware alone, no keyboard/mouse/menu
    // needed. Runs independently of KnobRouter (which only exists while mode === "kiosk"
    // — see the Loader below), so this is the ONLY way to get back into kiosk mode once
    // the screen is a desktop. If the knob is released before the threshold, nothing
    // extra happens beyond whatever the (mode-dependent) short-hold behavior already did.
    readonly property int longHoldMs: 3000
    property Timer _longHoldTimer: Timer {
        interval: root.longHoldMs
        repeat: false
        onTriggered: root.toggleMode()
    }
    Connections {
        target: root.hidBridge
        function onKnobEvent(event) {
            if (event.type !== "hold") return
            if (event.phase === "start") root._longHoldTimer.restart()
            else if (event.phase === "end") root._longHoldTimer.stop()
        }
    }

    // IPC surface — `omarchy-shell quake-panel status|toggleMode`, or
    // `omarchy-shell quake-panel setMode kiosk`. Mirrors
    // plugins/services/nightlight/Service.qml's status()/enable()/disable()/toggle()
    // shape. All of this project's toggle surfaces (menu entry, Hyprland keybind, the
    // ops/bin CLI wrapper) call through this IPC target — see ops/ for each.
    IpcHandler {
        target: "quake-panel"
        function status(): string { return root.mode }
        function setMode(mode: string): string { root.setMode(mode); return root.mode }
        function toggleMode(): string { root.toggleMode(); return root.mode }
    }

    Component.onCompleted: {
        console.log("=== omarchy-quake-panel === daemonPath=" + root.daemonPath + " panelScreen=" + (root.panelScreen ? root.panelScreen.name : "NONE FOUND"))
    }

    // ---- Kiosk-mode-only: the pinned window and everything that only makes sense while
    // it exists (TouchRouter's registered taps, KnobRouter's page-switch/press table, the
    // water picker, the reminder toast). Recreated fresh each time kiosk mode is
    // (re-)entered — currentPageIndex resetting to Dashboard on re-entry is expected.
    Loader {
        active: root.mode === "kiosk"
        sourceComponent: kioskComponent
    }

    Component {
        id: kioskComponent

        PanelWindow {
            id: panelWindow
            screen: root.panelScreen
            anchors { top: true; bottom: true; left: true; right: true }
            color: root.theme.background
            WlrLayershell.namespace: "omarchy-quake-panel"
            // Overlay + ignored exclusion zone: see shell/shell.qml's own header comment
            // for the full reasoning (Omarchy's bar renders on every screen with no
            // per-monitor exclude, and also reserves an exclusive zone Hyprland shrinks
            // other layers around regardless of layer order) — same fix applies
            // identically whether this window is drawn by a standalone process or, as
            // here, by a plugin inside the same process as that very bar.
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            property TouchRouter touchRouter: TouchRouter {}
            property KnobRouter knobRouter: KnobRouter {
                personalCareState: root.personalCareState
                waterAmountPicker: waterAmountPicker
            }

            Connections {
                target: root.hidBridge
                function onTouchEvent(points) { panelWindow.touchRouter.feed(points) }
                function onKnobEvent(event) { panelWindow.knobRouter.dispatch(event) }
            }
            Connections {
                target: root.personalCareState
                function onReminder(message) { toastOverlay.show(message) }
            }

            PageHost {
                anchors.fill: parent
                knobRouter: panelWindow.knobRouter
                systemStats: root.systemStats
                personalCareState: root.personalCareState
                knobLighting: root.knobLighting
                micState: root.micState
                screenBrightness: root.screenBrightness
                hidBridge: root.hidBridge
                touchRouter: panelWindow.touchRouter
                theme: root.theme
            }

            WaterAmountPicker {
                id: waterAmountPicker
                anchors.fill: parent
                personalCareState: root.personalCareState
                touchRouter: panelWindow.touchRouter
                theme: root.theme
                z: 998
            }

            ToastOverlay {
                id: toastOverlay
                anchors.fill: parent
                theme: root.theme
                touchRouter: panelWindow.touchRouter
                z: 999
            }
        }
    }
}
