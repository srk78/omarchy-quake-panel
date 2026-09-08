import QtQuick

// Bordered surface in the page's own background color — Omarchy's Ui/PopupCard.qml idiom
// (definition comes from the border, not from a lightened fill).
Rectangle {
    required property var theme
    color: theme.background
    border.color: theme.controlBorderColor
    border.width: theme.borderWidth
    radius: theme.cornerRadius
}
