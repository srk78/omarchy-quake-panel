import QtQuick

// Section caption — Omarchy's Ui/PanelSectionHeader.qml (darkened foreground, bold,
// caption size, NO letter-spacing), with an optional leading Nerd Font glyph the way the
// Wi-Fi/bluetooth rows lead with one.
Row {
    id: root
    required property var theme
    property string icon: ""
    property string text: ""
    spacing: theme.spacing.md

    Text {
        visible: root.icon !== ""
        text: root.icon
        textFormat: Text.PlainText
        color: root.theme.secondaryForeground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.title
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        text: root.text
        textFormat: Text.PlainText
        color: root.theme.secondaryForeground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.caption
        font.bold: true
        // PanelSectionHeader reserves the Nerd Font's ascent overshoot so a glyph at the
        // top of a clipped area isn't beheaded.
        topPadding: Math.ceil(root.theme.font.caption * 0.15)
        anchors.verticalCenter: parent.verticalCenter
    }
}
