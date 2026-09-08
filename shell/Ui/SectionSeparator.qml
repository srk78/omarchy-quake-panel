import QtQuick

// 1px divider, foreground @ 0.12 — Omarchy's Ui/PanelSeparator.qml. `vertical` for
// splitting side-by-side sections inside one card (this panel is 4:1 wide).
Rectangle {
    required property var theme
    property bool vertical: false
    width: vertical ? 1 : (parent ? parent.width : 1)
    height: vertical ? (parent ? parent.height : 1) : 1
    color: theme.separatorColor
}
