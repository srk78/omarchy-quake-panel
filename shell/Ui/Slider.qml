import QtQuick

// A touch-drag level slider — the first continuous (not tap) touch control in this app.
// Uses TouchRouter.registerDrag, not registerTap: a tap fires once at touch-down, but a
// slider needs the finger's position for the whole drag. See TouchRouter.qml's own
// registerDrag/feed() comments for exactly how a drag session differs from a tap one.
//
// `settled(value)` is throttled, not fired on every touch report: real callers of this
// slider (Services/KnobLighting.qml, ScreenBrightness.qml) end up writing to a real USB
// HID device on every emission, and a fast drag can produce touch reports far faster
// than that's sensible to do — see settleIntervalMs below. It still emits roughly every
// interval while dragging (not just once at release), so the control feels live.
Item {
    id: root
    required property var theme
    required property var touchRouter
    property real minValue: 0
    property real maxValue: 255
    property real value: 0 // bind this from the caller's own real (device) value
    // Trailing-edge throttle: emits immediately if it's been at least this long since
    // the last emission, otherwise schedules exactly one emission at that mark carrying
    // whatever the latest value was — bounds the hardware write rate during a drag
    // without dropping the final position when the finger stops.
    property int settleIntervalMs: 90
    signal settled(real value)

    implicitHeight: theme.spacing.touchControlHeight
    readonly property real _trackHeight: theme.space(10)
    readonly property real _thumbSize: theme.space(32)
    readonly property real _fraction: root.maxValue > root.minValue
        ? Math.max(0, Math.min(1, (root.value - root.minValue) / (root.maxValue - root.minValue)))
        : 0

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root._trackHeight
        radius: height / 2
        color: root.theme.controlFill
        border.color: root.theme.controlBorderColor
        border.width: root.theme.borderWidth

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            radius: height / 2
            width: Math.max(height, parent.width * root._fraction)
            color: root.theme.accent
        }
    }

    Rectangle {
        id: thumb
        width: root._thumbSize; height: root._thumbSize
        radius: width / 2
        color: root.theme.foreground
        border.color: root.theme.background
        border.width: root.theme.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.width * root._fraction - width / 2))
    }

    function _valueForLocalX(localX) {
        var frac = Math.max(0, Math.min(1, localX / root.width))
        return Math.round(root.minValue + frac * (root.maxValue - root.minValue))
    }

    property real _lastEmitAt: 0
    property var _pendingValue: null
    property Timer _throttleTimer: Timer {
        interval: root.settleIntervalMs
        repeat: false
        onTriggered: {
            if (root._pendingValue === null) return
            root._lastEmitAt = Date.now()
            root.settled(root._pendingValue)
            root._pendingValue = null
        }
    }
    function _emit(value) {
        root.value = value
        var now = Date.now()
        if (now - root._lastEmitAt >= root.settleIntervalMs) {
            root._lastEmitAt = now
            root._pendingValue = null
            root._throttleTimer.stop()
            root.settled(value)
        } else {
            root._pendingValue = value
            root._throttleTimer.restart()
        }
    }

    // Real touch: registerDrag's onStart/onMove both receive GLOBAL (screen) coordinates
    // — same convention TouchRouter._hitTest itself uses — so map back into this item's
    // local space before turning an X position into a value.
    function _fromGlobal(gx, gy) {
        var local = root.mapFromItem(null, gx, gy)
        root._emit(root._valueForLocalX(local.x))
    }
    Component.onCompleted: root.touchRouter.registerDrag(root,
        function (x, y) { root._fromGlobal(x, y) },
        function (x, y) { root._fromGlobal(x, y) })
    Component.onDestruction: root.touchRouter.unregisterDrag(root)

    // Mouse (dev/testing only) — MouseArea's own coordinates are already local, unlike
    // the global ones TouchRouter's registerDrag callbacks receive.
    MouseArea {
        anchors.fill: parent
        onPressed: function (mouse) { root._emit(root._valueForLocalX(mouse.x)) }
        onPositionChanged: function (mouse) { if (pressed) root._emit(root._valueForLocalX(mouse.x)) }
    }
}
