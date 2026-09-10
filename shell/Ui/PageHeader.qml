import QtQuick
import QtQuick.Effects

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

    // FOXY's icon is a real color emoji (see PageHost.qml's own comment on why), which
    // plain Text.color has no effect on — a color-emoji glyph carries its own baked-in
    // color table (COLR/CBDT) that overrides the text color property entirely,
    // confirmed live (set to theme.foreground, rendered orange regardless). Desaturating
    // via MultiEffect operates on the actually-rendered pixels instead, so it works
    // regardless of how the glyph itself is painted — every other page's icon is a
    // plain monochrome Nerd Font glyph already unaffected by this (saturation -1 on an
    // already-gray image is a no-op), so this wrapping applies uniformly rather than
    // needing an if-FOXY special case.
    Text {
        id: iconText
        text: root.icon
        textFormat: Text.PlainText
        color: root.theme.foreground
        font.family: root.theme.font.family
        font.pixelSize: root.theme.font.display
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        layer.enabled: true
        visible: false
    }
    MultiEffect {
        anchors.fill: iconText
        source: iconText
        saturation: -1.0
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

        // A plain gap between the page tabs and the clock/dot group — Row's own
        // `spacing` already puts 12px around every child uniformly, so this adds to
        // that rather than replacing it, deliberately separating "where you are" from
        // "what time it is" as two distinct clusters instead of one continuous run.
        Item { width: root.theme.space(16); height: 1 }

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
