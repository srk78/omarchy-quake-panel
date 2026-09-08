import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "Services"
import "Ui"

// Omarchy Quake Panel — kiosk shell entry point. Run with:
//   quickshell -p shell/shell.qml
//
// A single fullscreen Wayland layer-shell window pinned to the DK-QUAKE panel's output,
// hosting the kiosk UI. See ../PLAN.md / README.md for the full architecture.
//
// Touch does NOT go through Qt/Wayland's normal input path here — see TouchRouter.qml for
// why (a confirmed, unresolved Hyprland bug means layer-shell surfaces never receive
// wl_touch unless the mouse cursor happens to be on the same output). HidBridge's raw
// touch JSON is fed directly into TouchRouter, which drives our own registered buttons.
ShellRoot {
    id: root

    readonly property string daemonPath: Quickshell.shellDir + "/../daemon/src/bridge.js"
    readonly property var panelScreen: Quickshell.screens.find(function (s) {
        return s.name === "DP-1" || s.model === "DK-QUAKE"
    }) || Quickshell.screens[0]

    property HidBridge hidBridge: HidBridge { daemonPath: root.daemonPath }
    property SystemStats systemStats: SystemStats {}
    property PersonalCareState personalCareState: PersonalCareState {}
    property TouchRouter touchRouter: TouchRouter {}
    property Theme theme: Theme {}
    property KnobRouter knobRouter: KnobRouter {
        personalCareState: root.personalCareState
        waterAmountPicker: panelWindow.waterPicker
    }

    Component.onCompleted: {
        console.log("=== omarchy-quake-panel === daemonPath=" + root.daemonPath + " panelScreen=" + (root.panelScreen ? root.panelScreen.name : "NONE FOUND"))
        root.hidBridge.knobEvent.connect(root.knobRouter.dispatch)
        root.hidBridge.touchEvent.connect(root.touchRouter.feed)
        root.hidBridge.daemonError.connect(function (message) { console.log("[daemon error] " + message) })
        root.personalCareState.reminder.connect(function (message) { panelWindow.toast.show(message) })
    }

    PanelWindow {
        id: panelWindow
        screen: root.panelScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.theme.background
        WlrLayershell.namespace: "omarchy-quake-panel"
        // Overlay, not Top: Omarchy's own bar (plugins/bar/Bar.qml) renders one instance
        // per connected screen at the Top layer with no way to exclude a specific monitor
        // (its Variants { model: Quickshell.screens } has no filter, and shell.json has no
        // per-monitor bar setting) — so on this dedicated kiosk output it was drawing over
        // part of our own Top-layer window. Overlay sits one level above Top in the
        // wlr-layer-shell stack, so we fully cover it here without touching the bar on any
        // other monitor.
        WlrLayershell.layer: WlrLayer.Overlay
        // The bar also reserves an exclusive zone (confirmed: `hyprctl monitors` showed
        // "reserved": [0, 26, 0, 0] for this output) that Hyprland shrinks OTHER layer
        // surfaces around even at a higher layer — so being on top of the bar wasn't
        // enough, our own window was being squeezed to leave that strip empty. Ignore
        // exclusion zones entirely so we truly fill the whole output edge-to-edge.
        exclusionMode: ExclusionMode.Ignore

        property alias toast: toastOverlay
        property alias waterPicker: waterAmountPicker

        PageHost {
            anchors.fill: parent
            knobRouter: root.knobRouter
            systemStats: root.systemStats
            personalCareState: root.personalCareState
            hidBridge: root.hidBridge
            touchRouter: root.touchRouter
            theme: root.theme
        }

        WaterAmountPicker {
            id: waterAmountPicker
            anchors.fill: parent
            personalCareState: root.personalCareState
            touchRouter: root.touchRouter
            theme: root.theme
            z: 998
        }

        ToastOverlay {
            id: toastOverlay
            anchors.fill: parent
            theme: root.theme
            touchRouter: root.touchRouter
            z: 999
        }
    }
}
