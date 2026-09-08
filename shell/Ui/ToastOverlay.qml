import QtQuick

// Global reminder banner, layered above whatever page is active. Deliberately has NO knob
// wiring at all — see KnobRouter.qml's header comment for why that's what actually
// guarantees reminders can never interfere with the pomodoro or page-switching.
// Styled as an Omarchy popup card (Services/Theme.qml): background fill, control border.
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
        anchors.topMargin: root.theme.spacing.panelPadding
        width: Math.min(parent.width - root.theme.spacing.panelPadding * 2, toastRow.implicitWidth + root.theme.spacing.popupPadding * 2)
        height: toastRow.implicitHeight + root.theme.spacing.popupPadding * 2
        radius: root.theme.cornerRadius
        color: root.theme.background
        border.color: root.theme.controlBorderColor
        border.width: root.theme.borderWidth

        Row {
            id: toastRow
            anchors.centerIn: parent
            spacing: root.theme.spacing.xl
            Text {
                text: "󰂚"
                textFormat: Text.PlainText
                color: root.theme.secondaryForeground
                font.family: root.theme.font.family
                font.pixelSize: root.theme.font.display
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.message
                textFormat: Text.PlainText
                color: root.theme.foreground
                font.family: root.theme.font.family
                font.pixelSize: root.theme.font.heading
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        TapHandler { onTapped: root.dismiss() } // mouse; see TouchRouter.qml for touch
        Component.onCompleted: if (root.touchRouter) root.touchRouter.registerTap(toast, function () { root.dismiss() })
        Component.onDestruction: if (root.touchRouter) root.touchRouter.unregisterTap(toast)
    }
}
