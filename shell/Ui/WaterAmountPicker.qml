import QtQuick

// Global "how much water?" popup — triggered by PersonalCareState.requestWaterAmount()
// (knob hold, or the on-screen water button), from any page. Pre-selects whatever amount
// was logged last time. Fully knob-drivable while open (KnobRouter redirects rotate to
// cycle the highlighted option and press to confirm — see KnobRouter.qml), and each
// option is also directly tappable via TouchRouter.
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
            width: Math.min(parent.width - 80, 760)
            height: 220
            radius: root.theme.cornerRadius
            color: root.theme.background
            border.color: root.theme.surfaceBorder
            border.width: root.theme.borderWidth

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                Text { text: "How much water?"; color: root.theme.foreground; font.pixelSize: 22; font.bold: true }

                Row {
                    spacing: 12
                    Repeater {
                        model: root.presets
                        delegate: Rectangle {
                            id: option
                            required property int index
                            required property int modelData
                            width: 74; height: 74
                            radius: root.theme.cornerRadius
                            color: index === root.selectedIndex ? root.theme.selectedFill : root.theme.controlFill
                            border.color: index === root.selectedIndex ? root.theme.accent : root.theme.surfaceBorder
                            border.width: index === root.selectedIndex ? 2 : root.theme.borderWidth

                            Text {
                                anchors.centerIn: parent
                                text: option.modelData + "\nml"
                                horizontalAlignment: Text.AlignHCenter
                                color: option.index === root.selectedIndex ? root.theme.accent : root.theme.foreground
                                font.pixelSize: 15
                            }

                            TapHandler { onTapped: { root.selectedIndex = option.index; root.confirm() } } // mouse-only, see TouchRouter note

                            Component.onCompleted: root.touchRouter.registerTap(option, function () { root.selectedIndex = option.index; root.confirm() })
                            Component.onDestruction: root.touchRouter.unregisterTap(option)
                        }
                    }
                }

                Text { text: "Turn the knob to pick, press to confirm — or tap an amount"; color: root.theme.muted; font.pixelSize: 13 }
            }
        }
    }
}
