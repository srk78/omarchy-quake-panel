import QtQuick
import "../Ui"

// Page 1 — system dashboard, btop-styled: live history graphs (Sparkline) for CPU/RAM/
// network throughput, plus a per-core load bar grid for CPU — btop's signature visual
// idioms, adapted to this panel's card language (see Services/Theme.qml's header comment
// for the sharp-corners/bordered-card/restrained-bold conventions this follows).
Rectangle {
    id: root
    required property var systemStats
    required property var theme
    color: root.theme.background

    component Card: Rectangle {
        color: root.theme.background
        border.color: root.theme.controlBorderColor
        border.width: root.theme.borderWidth
        radius: root.theme.cornerRadius
    }

    // Matches Ui/PanelSectionHeader.qml exactly: darkened foreground, bold, caption
    // size — no letter-spacing (the real component doesn't set any; an earlier version
    // of this page added 1.2 as decoration not present in the verified source).
    component SectionLabel: Text {
        color: root.theme.secondaryForeground
        font.pixelSize: 12
        font.bold: true
    }

    component SectionSeparator: Rectangle {
        width: parent.width
        height: 1
        color: root.theme.separatorColor
    }

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        Text {
            text: root.systemStats.clockText
            color: root.theme.foreground
            font.pixelSize: 22
            font.bold: true
        }

        Row {
            width: parent.width
            height: parent.height - 34
            spacing: 18

            // ---- CPU: hero % + history graph + per-core bar grid ----
            Card {
                width: (parent.width - 36) / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    SectionLabel { text: "CPU" }
                    SectionSeparator {}
                    Text { text: root.systemStats.cpuPercent.toFixed(0) + "%"; color: root.theme.foreground; font.pixelSize: 30; font.bold: true }

                    Sparkline {
                        width: parent.width
                        height: 90
                        values: root.systemStats.cpuHistory
                        maxValue: 100
                        lineColor: root.theme.accent
                        fillColor: root.theme.withAlpha(root.theme.accent, 0.18)
                    }

                    SectionLabel { text: "PER CORE" }
                    Row {
                        id: coreBars
                        width: parent.width
                        height: 34
                        spacing: 2
                        Repeater {
                            model: root.systemStats.corePercents
                            delegate: Item {
                                id: coreSlot
                                required property real modelData
                                width: (coreBars.width - coreBars.spacing * Math.max(0, root.systemStats.corePercents.length - 1)) / Math.max(1, root.systemStats.corePercents.length)
                                height: coreBars.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.height * Math.max(0.03, coreSlot.modelData / 100)
                                    color: root.theme.accent
                                }
                            }
                        }
                    }
                }
            }

            // ---- RAM: hero % + history graph + used/total ----
            Card {
                width: (parent.width - 36) / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    SectionLabel { text: "RAM" }
                    SectionSeparator {}
                    Text { text: root.systemStats.memUsedPercent.toFixed(0) + "%"; color: root.theme.foreground; font.pixelSize: 30; font.bold: true }

                    Sparkline {
                        width: parent.width
                        height: 90
                        values: root.systemStats.memHistory
                        maxValue: 100
                        lineColor: root.theme.accent
                        fillColor: root.theme.withAlpha(root.theme.accent, 0.18)
                    }

                    Text {
                        text: root.systemStats.memUsedMb.toFixed(0) + " / " + root.systemStats.memTotalMb.toFixed(0) + " MB"
                        color: root.theme.secondaryForeground; font.pixelSize: 13
                    }
                }
            }

            // ---- NETWORK: rx/tx + combined-throughput history graph ----
            Card {
                width: (parent.width - 36) / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    SectionLabel { text: "NETWORK" }
                    SectionSeparator {}
                    Row {
                        spacing: 16
                        Text { text: "↓ " + root.systemStats.netRxKBs.toFixed(0) + " KB/s"; color: root.theme.foreground; font.pixelSize: 16 }
                        Text { text: "↑ " + root.systemStats.netTxKBs.toFixed(0) + " KB/s"; color: root.theme.foreground; font.pixelSize: 16 }
                    }

                    Sparkline {
                        width: parent.width
                        height: 90
                        values: root.systemStats.netHistory
                        maxValue: root.systemStats.netHistoryMax
                        lineColor: root.theme.accent
                        fillColor: root.theme.withAlpha(root.theme.accent, 0.18)
                    }
                }
            }
        }
    }
}
