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
    readonly property string paDaemonPath: root._selfDir + "../daemon/src/paBridge.js"
    // Split into "the real panel, if actually present" and "what to use if not" —
    // deliberately NOT the same property, after a real regression: an earlier version
    // of the reconnect-recovery fix below (see its own comment) reacted to *any* change
    // in the fallback-inclusive value, which also fires the moment the real panel
    // disconnects and the fallback (Quickshell.screens[0], normally the laptop's own
    // screen) kicks in — confirmed live (2026-09-14) that this dragged the kiosk
    // window onto the main screen on unplug, exactly the leak this app's whole
    // per-output design (see this file's own top-of-file comment) exists to prevent.
    // The recovery logic below now watches _realPanelScreen specifically, so it only
    // ever fires when reconnecting to an actual DK-QUAKE panel, never when falling
    // back to some other screen because the real one is genuinely gone.
    readonly property var _realPanelScreen: Quickshell.screens.find(function (s) {
        return s.name === "DP-1" || s.model === "DK-QUAKE"
    })
    readonly property var panelScreen: root._realPanelScreen || Quickshell.screens[0]

    // Quickshell.screens has a real screensChanged notify (confirmed via its own
    // qmltypes), so _realPanelScreen's binding above does correctly re-evaluate to a
    // fresh Screen object whenever the panel's output disconnects and reconnects (e.g.
    // a real power cycle of the panel hardware, not just this software restarting).
    // What does NOT happen on its own: the already-created PanelWindow below noticing
    // that its own `screen:` binding now points at a different object and re-homing
    // itself there — confirmed live (2026-09-14) that after a real panel power cycle,
    // `mode` and `panelScreen` were both still correct, but nothing was actually
    // rendering on the panel (Hyprland's ordinary desktop showed through instead,
    // looking exactly like "desktop mode" even though the app never left "kiosk").
    // Toggling mode off and back on fixed it — which works only because that
    // destroys and recreates the whole PanelWindow via the Loader below, forcing a
    // fresh `screen:` binding against whatever panelScreen currently is. A Wayland
    // layer-shell surface is created against a specific output at protocol level, so
    // this isn't really a Quickshell bug to work around so much as an expected
    // consequence of that: reassigning `screen:` on an already-mapped surface was never
    // going to move it. Forcing the same teardown+rebuild automatically whenever the
    // real panel reconnects, instead of requiring the manual toggle — and doing
    // nothing at all when it disconnects, leaving whatever window already exists
    // alone rather than ever rebuilding it against the fallback screen.
    // Not a direct `kioskLoader.active = false/true` — imperatively assigning a
    // property that already has a declarative binding (active: root.mode === "kiosk"
    // below) would permanently replace that binding with a plain static value,
    // silently breaking the real mode toggle for the rest of the session. Routing
    // through this extra reactive flag instead means the Loader's `active` binding
    // itself never gets touched — only one of its own inputs does.
    property bool _forceKioskReload: false
    on_RealPanelScreenChanged: {
        if (!root._realPanelScreen) return // the real panel just disconnected — leave things as they are, never rebuild against the fallback
        if (root.mode !== "kiosk") return // Loader isn't active; nothing to recreate
        root._forceKioskReload = true
        Qt.callLater(function () { root._forceKioskReload = false })
    }

    // ---- Always-on, regardless of mode ----
    property HidBridge hidBridge: HidBridge { daemonPath: root.daemonPath }
    property SystemStats systemStats: SystemStats {}
    property PersonalCareState personalCareState: PersonalCareState {}
    property KnobLighting knobLighting: KnobLighting { hidBridge: root.hidBridge }
    property MicState micState: MicState { hidBridge: root.hidBridge }
    property ScreenBrightness screenBrightness: ScreenBrightness { hidBridge: root.hidBridge }
    property PaBridge paBridge: PaBridge { daemonPath: root.paDaemonPath }
    property PaState paState: PaState { paBridge: root.paBridge }
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

    // The physical microphone is gated by Foxy's own on/off state, not a separate manual
    // Settings-page toggle (removed — see HISTORY.md's FOXY redesign) — off by default,
    // live only while Foxy is actually armed to listen. Same dual-trigger pattern as
    // _syncVirtualTouch just above: fires on every continuousMode change however it
    // happens (the on-screen button, the knob, or the daemon's own state push), and once
    // more as soon as the daemon actually connects, since the compiled-in "off" default
    // never fires a change signal on its own but the real hardware could still be
    // sitting in whatever state a previous session left it in.
    function _syncMic() {
        root.micState.setOn(root.paState.continuousMode)
    }
    property Connections _micSyncConn: Connections {
        target: root.paState
        function onContinuousModeChanged() { root._syncMic() }
    }
    property Connections _micSyncConnectedConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root._syncMic() }
    }

    // Whether the panel's real HID device is actually connected — read by
    // BarWidget.qml to hide the kiosk/desktop mode options (picking either does
    // nothing useful without a real device) and show a disconnected state instead.
    // hidBridge's connected/disconnected signals already reflect real hot-plug
    // (Aris68Connector.js's own rescan loop reconnects automatically if the device
    // drops), so this is just a persisted mirror of them, not new detection logic.
    property bool deviceConnected: false
    property Connections _deviceConnectedConn: Connections {
        target: root.hidBridge
        function onConnected(iface) { if (iface === "control") root.deviceConnected = true }
        function onDisconnected(iface) { if (iface === "control") root.deviceConnected = false }
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
    //
    // startPomodoro() exists here specifically for the PA's MCP tool
    // (daemon/src/paTools/server.js) to call via `omarchy-shell quake-panel
    // startPomodoro` — the same shape as every other external toggle surface, not a
    // separate code path invented for the agent.
    IpcHandler {
        target: "quake-panel"
        function status(): string { return root.mode }
        function setMode(mode: string): string { root.setMode(mode); return root.mode }
        function toggleMode(): string { root.toggleMode(); return root.mode }
        function startPomodoro(): string { root.personalCareState.startPomodoro(); return "ok" }
    }

    Component.onCompleted: {
        console.log("=== omarchy-quake-panel === daemonPath=" + root.daemonPath + " panelScreen=" + (root.panelScreen ? root.panelScreen.name : "NONE FOUND"))
    }

    // ---- Kiosk-mode-only: the pinned window and everything that only makes sense while
    // it exists (TouchRouter's registered taps, KnobRouter's page-switch/press table, the
    // water picker, the reminder toast). Recreated fresh each time kiosk mode is
    // (re-)entered — currentPageIndex resetting to Dashboard on re-entry is expected.
    Loader {
        id: kioskLoader
        active: root.mode === "kiosk" && !root._forceKioskReload
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
                paState: root.paState
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
                screenBrightness: root.screenBrightness
                hidBridge: root.hidBridge
                paState: root.paState
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
