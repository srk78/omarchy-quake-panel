import QtQuick

// On-screen touch button — Omarchy's Ui/Button.qml state model (transparent at rest with
// a normal-alpha border, pressed fill when a finger/mouse is down, optional leading icon
// glyph), sized for fingers rather than a pointer.
//
// Registers ITSELF with TouchRouter: real touch does not reach TapHandler on this app's
// layer-shell window (see Services/TouchRouter.qml), so every tappable thing must be
// hit-tested by the router. Putting the registration here means a page can't forget it.
Rectangle {
    id: root
    required property var theme
    property var touchRouter: null
    property string text: ""
    property string icon: ""
    signal activated()

    implicitWidth: Math.max(theme.space(150), row.implicitWidth + theme.spacing.controlPaddingX * 4)
    implicitHeight: theme.spacing.touchControlHeight
    color: tapHandler.pressed ? theme.pressedFill : "transparent"
    border.color: theme.controlBorderColor
    border.width: theme.borderWidth
    radius: theme.cornerRadius

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.theme.spacing.md

        Text {
            visible: root.icon !== ""
            text: root.icon
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.heading
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.text !== ""
            text: root.text
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.subtitle
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    TapHandler { id: tapHandler; onTapped: root.activated() } // mouse (dev/testing only)
    Component.onCompleted: if (root.touchRouter) root.touchRouter.registerTap(root, function () { root.activated() })
    Component.onDestruction: if (root.touchRouter) root.touchRouter.unregisterTap(root)
}
