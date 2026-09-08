import QtQuick

// Global reminder banner, layered above whatever page is active. Deliberately has NO knob
// wiring at all — see KnobRouter.qml's header comment for why that's what actually
// guarantees reminders can never interfere with the pomodoro or page-switching.
// Colors follow the active Omarchy theme (see Services/Theme.qml).
Item {
    id: root
    required property var theme
    property var touchRouter: null // optional: real-touch dismiss, see TouchRouter.qml

    property string message: ""
    readonly property bool shown: message.length > 0

    function show(msg) {
        root.message = msg
        dismissTimer.restart()
    }
    function dismiss() { root.message = "" }

    Timer { id: dismissTimer; interval: 15000; onTriggered: root.dismiss() }

    Rectangle {
        id: toast
        visible: root.shown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        width: Math.min(parent.width - 32, toastText.implicitWidth + 48)
        height: toastText.implicitHeight + 28
        radius: root.theme.cornerRadius
        color: root.theme.background
        border.color: root.theme.surfaceBorder
        border.width: root.theme.borderWidth

        Text {
            id: toastText
            anchors.centerIn: parent
            text: root.message
            color: root.theme.foreground
            font.pixelSize: 20
        }

        TapHandler { onTapped: root.dismiss() } // mouse; see TouchRouter.qml for touch
        Component.onCompleted: if (root.touchRouter) root.touchRouter.registerTap(toast, function () { root.dismiss() })
        Component.onDestruction: if (root.touchRouter) root.touchRouter.unregisterTap(toast)
    }
}
