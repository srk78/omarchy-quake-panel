import QtQuick

// Page hero — Omarchy's Ui/PanelHero.qml: display-size glyph, bold title, uppercase
// letter-spaced dim caption; on the trailing edge, the clock and a page indicator (the
// knob switches pages, so the indicator is read-only — it just shows where you are).
Item {
    id: root
    required property var theme
    property string icon: ""
    property string title: ""
    property string meta: ""
    property string clock: ""
    property var pageNames: []
    property int pageIndex: 0
    // PA's continuous "wake word" mode (Services/PaState.qml) — shown here, not on
    // PaPage.qml itself, specifically because it keeps listening no matter which page
    // is on screen; this is the one piece of chrome every page already shares.
    property bool continuousListening: false

    readonly property color dim: theme.secondaryForeground
    implicitHeight: Math.max(iconText.implicitHeight, labels.implicitHeight, trailing.implicitHeight)

    Text {
        id: iconText
        text: root.icon
        textFormat: Text.PlainText
        color: root.theme.foreground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.display
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        id: labels
        anchors.left: iconText.right
        anchors.leftMargin: root.theme.space(14)
        anchors.right: trailing.left
        anchors.rightMargin: root.theme.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.space(2)

        Text {
            width: parent.width
            text: root.title
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.title
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.meta.toUpperCase()
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.caption
            font.bold: true
            font.letterSpacing: root.theme.font.heroCaptionSpacing
            elide: Text.ElideRight
        }
    }

    Row {
        id: trailing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.space(12)

        // Page indicator: selected = foreground @ 0.18 fill + bold (Ui/Button.qml's
        // `selected` state), the rest dim text with no fill.
        Row {
            spacing: root.theme.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: root.pageNames
                delegate: Rectangle {
                    id: tab
                    required property int index
                    required property string modelData
                    readonly property bool current: index === root.pageIndex
                    implicitWidth: tabText.implicitWidth + root.theme.spacing.controlPaddingX * 2
                    implicitHeight: tabText.implicitHeight + root.theme.spacing.controlPaddingY * 2
                    color: current ? root.theme.selectedFill : "transparent"
                    radius: root.theme.cornerRadius
                    Text {
                        id: tabText
                        anchors.centerIn: parent
                        text: tab.modelData.toUpperCase()
                        textFormat: Text.PlainText
                        color: tab.current ? root.theme.foreground : root.dim
                        font.family: root.theme.font.family
                        font.pixelSize: root.theme.font.caption
                        font.bold: true
                        font.letterSpacing: root.theme.font.heroCaptionSpacing
                    }
                }
            }
        }

        // Deliberately subtle, per the brief: a small dim dot, not a bright badge — you
        // should be able to notice it if you look, not have it fight for attention on a
        // panel that's mostly meant to be glanced at.
        Rectangle {
            id: continuousDot
            visible: root.continuousListening
            width: root.theme.space(7); height: width
            radius: width / 2
            color: root.dim
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation on opacity {
                running: continuousDot.visible
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.25; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.25; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }

        Text {
            visible: root.clock !== ""
            text: root.clock
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.heading
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
