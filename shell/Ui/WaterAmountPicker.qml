import QtQuick

// Global "how much water?" popup — triggered by PersonalCareState.requestWaterAmount()
// (knob hold, or the on-screen water button), from any page. Pre-selects whatever amount
// was logged last time. Fully knob-drivable while open (KnobRouter redirects rotate to
// cycle the highlighted option and press to confirm — see KnobRouter.qml), and each
// option is also directly tappable via TouchRouter.
//
// Options follow Omarchy's Ui/Button.qml states: bordered + transparent at rest, the
// selected one gets the foreground @ 0.18 selected fill and bold text (no accent border —
// Style.selectedBorderWidth is 0 by default).
Item {
    id: root
    required property var personalCareState
    required property var touchRouter
    required property var theme

    property bool shown: false
    property int selectedIndex: 0
    readonly property var presets: personalCareState ? personalCareState.mlPresets : []

    function open() {
        var idx = root.presets.indexOf(root.personalCareState.lastAmountMl)
        root.selectedIndex = idx >= 0 ? idx : Math.floor(root.presets.length / 2)
        root.shown = true
        dismissTimer.restart()
    }
    function moveSelection(dir) {
        if (!root.shown || root.presets.length === 0) return
        root.selectedIndex = (root.selectedIndex + (dir > 0 ? 1 : -1) + root.presets.length) % root.presets.length
        dismissTimer.restart()
    }
    function confirm() {
        if (!root.shown) return
        root.personalCareState.logWater(root.presets[root.selectedIndex])
        root.shown = false
        dismissTimer.stop()
    }
    function cancel() {
        root.shown = false
        dismissTimer.stop()
    }

    Timer { id: dismissTimer; interval: 12000; onTriggered: root.cancel() } // no choice made — don't log anything

    Connections {
        target: root.personalCareState
        function onRequestWaterAmount() { root.open() }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.shown
        color: Qt.rgba(0, 0, 0, 0.55)

        TapHandler { onTapped: root.cancel() } // tapping the scrim (mouse-only, given the touch bug — see TouchRouter.qml)

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: cardColumn.implicitWidth + root.theme.spacing.popupPadding * 2
            height: cardColumn.implicitHeight + root.theme.spacing.popupPadding * 2
            radius: root.theme.cornerRadius
            color: root.theme.background
            border.color: root.theme.controlBorderColor
            border.width: root.theme.borderWidth

            Column {
                id: cardColumn
                anchors.centerIn: parent
                spacing: root.theme.space(12)

                Row {
                    spacing: root.theme.space(10)
                    Text {
                        text: "󰖌"
                        textFormat: Text.PlainText
                        color: root.theme.foreground
                        font.family: root.theme.font.family
                        font.pixelSize: root.theme.font.display
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "How much water?"
                        textFormat: Text.PlainText
                        color: root.theme.foreground
                        font.family: root.theme.font.family
                        font.pixelSize: root.theme.font.title
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    spacing: root.theme.space(8)
                    Repeater {
                        model: root.presets
                        delegate: Rectangle {
                            id: option
                            required property int index
                            required property int modelData
                            readonly property bool current: index === root.selectedIndex
                            width: root.theme.space(64); height: root.theme.space(64)
                            radius: root.theme.cornerRadius
                            color: current ? root.theme.selectedFill : "transparent"
                            border.color: root.theme.controlBorderColor
                            border.width: root.theme.borderWidth
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: root.theme.spacing.xs
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: option.modelData
                                    textFormat: Text.PlainText
                                    color: root.theme.foreground
                                    font.family: root.theme.font.family
                                    font.pixelSize: root.theme.font.heading
                                    font.bold: option.current
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "ML"
                                    textFormat: Text.PlainText
                                    color: root.theme.secondaryForeground
                                    font.family: root.theme.font.family
                                    font.pixelSize: root.theme.font.caption
                                    font.bold: true
                                    font.letterSpacing: root.theme.font.heroCaptionSpacing
                                }
                            }

                            TapHandler { onTapped: { root.selectedIndex = option.index; root.confirm() } } // mouse-only, see TouchRouter note

                            Component.onCompleted: root.touchRouter.registerTap(option, function () { root.selectedIndex = option.index; root.confirm() })
                            Component.onDestruction: root.touchRouter.unregisterTap(option)
                        }
                    }
                }

                Text {
                    text: "Turn the knob to pick, press to confirm · or tap an amount"
                    textFormat: Text.PlainText
                    color: root.theme.secondaryForeground
                    font.family: root.theme.font.family
                    font.pixelSize: root.theme.font.bodySmall
                }
            }
        }
    }
}
