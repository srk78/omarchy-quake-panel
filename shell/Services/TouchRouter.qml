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
//
// registerDrag(item, onStart, onMove) is the same idea for a control that needs to track
// a finger continuously (Ui/Slider.qml) rather than fire once — see feed() below for
// exactly how a drag session differs from a tap session.
QtObject {
    id: root

    readonly property int screenH: 480
    readonly property int staleMs: 400 // mirrors uinputTouch.js's own release-detection window

    property var _targets: []       // [{item, callback}]      (taps)
    property var _dragTargets: []   // [{item, onStart, onMove}]
    property bool _sessionActive: false
    property real _lastSeen: 0
    property var _activeDrag: null  // the drag target hit at the START of the current session, if any

    function registerTap(item, callback) {
        root._targets = root._targets.concat([{ item: item, callback: callback }])
    }
    function unregisterTap(item) {
        root._targets = root._targets.filter(function (t) { return t.item !== item })
    }
    function registerDrag(item, onStart, onMove) {
        root._dragTargets = root._dragTargets.concat([{ item: item, onStart: onStart, onMove: onMove }])
    }
    function unregisterDrag(item) {
        root._dragTargets = root._dragTargets.filter(function (t) { return t.item !== item })
    }

    function _hitTestIn(list, x, y) {
        for (var i = list.length - 1; i >= 0; i--) {
            var t = list[i]
            if (!t.item || !t.item.visible || t.item.width <= 0 || t.item.height <= 0) continue
            var pos = t.item.mapToItem(null, 0, 0)
            if (x >= pos.x && x <= pos.x + t.item.width && y >= pos.y && y <= pos.y + t.item.height) return t
        }
        return null
    }

    // Feed one Aris68Connector/daemon touch event batch (HidBridge.touchEvent payload).
    // This hardware never sends an explicit "up" report (see uinputTouch.js) — a tap
    // session is debounced by "still recent" rather than a real release, same as there.
    //
    // A tap target still fires exactly once, at the start of a session, same as always.
    // A drag target additionally keeps receiving every subsequent point in that SAME
    // session via onMove — nothing proactively fires an "end": the next touch anywhere
    // (a new tap, or the start of the next drag) naturally resets _sessionActive/
    // _activeDrag via the staleness check below before that next touch is processed, so
    // there's no stuck state to clean up without one. A slider's own settle-timeout
    // (see Ui/Slider.qml) is what treats "no more onMove for a while" as "released".
    function feed(points) {
        var now = Date.now()
        if (root._sessionActive && now - root._lastSeen > root.staleMs) {
            root._sessionActive = false
            root._activeDrag = null
        }
        for (var i = 0; i < points.length; i++) {
            var p = points[i]
            if (p.action !== 1) continue
            root._lastSeen = now
            var x = p.x
            var y = (root.screenH - 1) - p.y // bottom-left -> top-left, matches uinputTouch.js
            if (root._sessionActive) {
                if (root._activeDrag) root._activeDrag.onMove(x, y)
                continue // taps debounce to one fire per session; a non-drag session ignores repeats, same as before
            }
            root._sessionActive = true
            var dragHit = root._hitTestIn(root._dragTargets, x, y)
            if (dragHit) {
                root._activeDrag = dragHit
                dragHit.onStart(x, y)
                continue
            }
            var hit = root._hitTestIn(root._targets, x, y)
            if (hit) hit.callback()
        }
    }
}
