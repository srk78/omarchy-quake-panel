import QtQuick

// Drives our OWN QML tap targets directly from the daemon's raw touch JSON, bypassing
// Wayland/Hyprland's layer-shell entirely.
//
// Why this exists: Hyprland has a confirmed, unresolved upstream bug where a layer-shell
// surface (which is what every Quickshell PanelWindow is) never receives wl_touch events
// unless the mouse pointer happens to already be on the same output
// (https://github.com/hyprwm/Hyprland/discussions/12221) — reproduced live here: real
// touches never reached any QML TapHandler at all, while mouse clicks on the exact same
// window worked immediately. The virtual /dev/uinput touchscreen (uinputTouch.js) still
// gets real compositor-level touch delivery to OTHER clients (proven: it correctly
// switched focus between two real terminal windows) — it's specifically Quickshell's own
// layer-shell surface that the compositor won't route touch to. Since this build no
// longer needs a WebEngineView (the one thing that would have required real kernel input),
// routing touch ourselves for our own QML pages sidesteps the bug entirely.
//
// Usage: a page registers a tappable Item with registerTap(item, callback) in
// Component.onCompleted and unregisterTap(item) in Component.onDestruction. Hit-testing
// uses the item's live position (mapToItem), so it's correct even if things move/resize.
QtObject {
    id: root

    readonly property int screenH: 480
    readonly property int staleMs: 400 // mirrors uinputTouch.js's own release-detection window

    property var _targets: []       // [{item, callback}]
    property bool _sessionActive: false
    property real _lastSeen: 0

    function registerTap(item, callback) {
        root._targets = root._targets.concat([{ item: item, callback: callback }])
    }
    function unregisterTap(item) {
        root._targets = root._targets.filter(function (t) { return t.item !== item })
    }

    function _hitTest(x, y) {
        for (var i = root._targets.length - 1; i >= 0; i--) {
            var t = root._targets[i]
            if (!t.item || !t.item.visible || t.item.width <= 0 || t.item.height <= 0) continue
            var pos = t.item.mapToItem(null, 0, 0)
            if (x >= pos.x && x <= pos.x + t.item.width && y >= pos.y && y <= pos.y + t.item.height) return t
        }
        return null
    }

    // Feed one Aris68Connector/daemon touch event batch (HidBridge.touchEvent payload).
    // This hardware never sends an explicit "up" report (see uinputTouch.js) — a tap
    // session is debounced by "still recent" rather than a real release, same as there.
    function feed(points) {
        var now = Date.now()
        if (root._sessionActive && now - root._lastSeen > root.staleMs) root._sessionActive = false
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            if (p.action !== 1) continue
            root._lastSeen = now
            if (root._sessionActive) continue // debounce: one fire per physical tap, not per repeated frame
            root._sessionActive = true
            var x = p.x
            var y = (root.screenH - 1) - p.y // bottom-left -> top-left, matches uinputTouch.js
            var hit = root._hitTest(x, y)
            if (hit) hit.callback()
        }
    }
}
