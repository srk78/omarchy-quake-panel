import QtQuick
import "../Ui"

// Page 3 — Settings: the knob's RGB ring color and light brightness
// (Services/KnobLighting.qml), and the panel's own screen brightness
// (Services/ScreenBrightness.qml — a genuinely separate hardware control, not the same
// thing, hence "KNOB LIGHT BRIGHTNESS" rather than plain "BRIGHTNESS" as the section
// label). Its own page rather than folded into Self Care or the System page: settings
// are a distinct category from either, and this gives room to grow without cramming
// unrelated controls into an existing page's card.
//
// The built-in microphone (Services/MicState.qml) used to have its own manual toggle
// here too — removed (see HISTORY.md's FOXY redesign): the mic is now gated entirely by
// Foxy's own on/off state (Service.qml/shell.qml wire this directly), off by default
// and live only while Foxy is actually armed to listen, so a separate manual switch that
// could disagree with that was just a confusing extra degree of freedom.
//
// Layout: the color row needs the full page width (ten swatches), so it gets its own
// full-width block up top; the other two controls each need much less, so they share a
// second row split into two Ui/Section columns (the same section shape
// Pages/PersonalCarePage.qml uses) — this fills the page's height instead of leaving a
// large empty area below a single top-aligned block. Ui/Slider.qml is this app's first
// continuous (not tap) touch control — see its own header comment and
// TouchRouter.qml's registerDrag for why that needed a real (if small) TouchRouter
// extension, not just a wider button.
//
// Color swatches are NOT Ui/PanelButton (they're circular chips, not text buttons) —
// each registers itself with TouchRouter directly, mirroring
// Ui/WaterAmountPicker.qml's preset options. The Repeater delegate is its own inline
// Column (not a shared sub-component): a shared one needs `modelData` forwarded through
// an extra property, and doing that via a default-property-alias silently breaks it —
// the alias redirects children into a wrapper Item, so `parent` inside the swatch is
// that wrapper, not the delegate holding `modelData`. Duplicating the ~15-line shape
// would be simpler than fighting that; see HISTORY.md for how this was actually caught.
Item {
    id: root
    required property var knobLighting
    required property var screenBrightness
    required property var touchRouter
    required property var theme

    readonly property string heroMeta: "Knob ring & brightness"

    Card {
        theme: root.theme
        anchors.fill: parent

        Column {
            id: colorBlock
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.theme.space(16) }
            spacing: root.theme.spacing.rowGap

            SectionLabel { theme: root.theme; icon: "󰩶"; text: "KNOB COLOR" }
            SectionSeparator { theme: root.theme }

            Row {
                spacing: root.theme.space(14)
                Repeater {
                    model: root.knobLighting.presets
                    delegate: Column {
                        id: colorItem
                        required property var modelData
                        readonly property bool isOffPreset: colorItem.modelData.off === true
                        readonly property bool current: colorItem.isOffPreset
                            ? root.knobLighting.isOff()
                            : root.knobLighting.isCurrent(colorItem.modelData.hue, colorItem.modelData.sat)
                        spacing: root.theme.spacing.xs

                        Rectangle {
                            id: swatch
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.theme.space(48); height: root.theme.space(48)
                            radius: width / 2
                            color: colorItem.isOffPreset ? root.theme.controlFill
                                : Qt.hsva(colorItem.modelData.hue / 255, colorItem.modelData.sat / 255, 1.0, 1.0)
                            border.color: colorItem.current ? root.theme.foreground : root.theme.controlBorderColor
                            border.width: colorItem.current ? root.theme.borderWidth * 2 : root.theme.borderWidth

                            Text {
                                visible: colorItem.isOffPreset
                                anchors.centerIn: parent
                                text: "󱈑"
                                textFormat: Text.PlainText
                                color: root.theme.secondaryForeground
                                font.family: root.theme.font.family
                                font.pixelSize: root.theme.font.heading
                            }
                            Text {
                                visible: colorItem.current && !colorItem.isOffPreset
                                anchors.centerIn: parent
                                text: "󰄬"
                                textFormat: Text.PlainText
                                // Fixed dark, not theme.foreground: must read against
                                // every preset color, not just a dark surface.
                                color: "#1a1a1a"
                                font.family: root.theme.font.family
                                font.pixelSize: root.theme.font.heading
                            }

                            function activate() {
                                if (colorItem.isOffPreset) root.knobLighting.setOff()
                                else root.knobLighting.setColor(colorItem.modelData.hue, colorItem.modelData.sat)
                            }
                            TapHandler { onTapped: swatch.activate() } // mouse (dev/testing only)
                            Component.onCompleted: root.touchRouter.registerTap(swatch, function () { swatch.activate() })
                            Component.onDestruction: root.touchRouter.unregisterTap(swatch)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: colorItem.modelData.name
                            textFormat: Text.PlainText
                            color: root.theme.secondaryForeground
                            font.family: root.theme.font.family
                            font.pixelSize: root.theme.font.caption
                        }
                    }
                }
            }
        }

        SectionSeparator {
            id: midSeparator
            theme: root.theme
            anchors {
                left: parent.left; right: parent.right
                top: colorBlock.bottom
                topMargin: root.theme.spacing.lg
                leftMargin: root.theme.space(16); rightMargin: root.theme.space(16)
            }
        }

        Row {
            id: lowerRow
            anchors {
                left: parent.left; right: parent.right; bottom: parent.bottom
                top: midSeparator.bottom
                margins: root.theme.space(16)
                topMargin: root.theme.spacing.lg
            }
            spacing: root.theme.space(24)
            readonly property real halfWidth: (width - spacing) / 2

            Section {
                theme: root.theme
                icon: "󰃿"; label: "KNOB LIGHT BRIGHTNESS"
                width: lowerRow.halfWidth

                Text {
                    width: parent.width
                    text: root.knobLighting.loaded
                        ? Math.round(100 * root.knobLighting.brightness / root.knobLighting.brightnessMax) + "%"
                        : "…"
                    textFormat: Text.PlainText
                    color: root.theme.foreground
                    font.family: root.theme.font.family
                    font.pixelSize: root.theme.font.title
                    font.bold: true
                }
                Slider {
                    width: parent.width
                    theme: root.theme
                    touchRouter: root.touchRouter
                    minValue: root.knobLighting.brightnessMin
                    maxValue: root.knobLighting.brightnessMax
                    value: root.knobLighting.brightness
                    onSettled: function (v) { root.knobLighting.previewBrightness(v) }
                }
            }

            SectionSeparator { theme: root.theme; vertical: true }

            Section {
                theme: root.theme
                icon: "󰃞"; label: "SCREEN BRIGHTNESS"
                width: lowerRow.halfWidth

                Text {
                    width: parent.width
                    text: root.screenBrightness.loaded
                        ? Math.round(100 * root.screenBrightness.value / root.screenBrightness.valueMax) + "%"
                        : "…"
                    textFormat: Text.PlainText
                    color: root.theme.foreground
                    font.family: root.theme.font.family
                    font.pixelSize: root.theme.font.title
                    font.bold: true
                }
                Slider {
                    width: parent.width
                    theme: root.theme
                    touchRouter: root.touchRouter
                    minValue: root.screenBrightness.valueMin
                    maxValue: root.screenBrightness.valueMax
                    value: root.screenBrightness.value
                    onSettled: function (v) { root.screenBrightness.setValue(v) }
                }
            }
        }
    }
}
