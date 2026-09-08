import QtQuick
import "../Ui"

// Page 1 — system dashboard, btop-styled: live history graphs (Sparkline) for CPU/RAM/
// network throughput, plus a per-core load bar grid for CPU. Three cards across the
// panel's full width, each led by a glyph section label, a hero number, and a graph that
// takes whatever height is left (see Services/Theme.qml for the token sources).
Item {
    id: root
    required property var systemStats
    required property var theme

    function fmtRate(kbs) {
        if (kbs >= 1024) return (kbs / 1024).toFixed(1) + " MB/s"
        return kbs.toFixed(0) + " KB/s"
    }
    function fmtGb(mb) { return (mb / 1024).toFixed(1) }

    readonly property int gap: theme.spacing.huge
    readonly property real cardWidth: (width - gap * 2) / 3

    // Hero value with a secondary detail sitting on its baseline — the same "big number,
    // small context" pairing each section of this panel leads with.
    component HeroRow: Row {
        id: heroRow
        property string value: ""
        property string detail: ""
        spacing: root.theme.spacing.xl
        Text {
            text: heroRow.value
            textFormat: Text.PlainText
            color: root.theme.foreground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.hero
            font.bold: true
        }
        Text {
            visible: heroRow.detail !== ""
            text: heroRow.detail
            textFormat: Text.PlainText
            color: root.theme.secondaryForeground
            font.family: root.theme.font.family
            font.pixelSize: root.theme.font.subtitle
            anchors.baseline: parent.children[0].baseline
        }
    }

    component Graph: Sparkline {
        lineColor: root.theme.accent
        fillColor: root.theme.withAlpha(root.theme.accent, 0.18)
    }

    Row {
        anchors.fill: parent
        spacing: root.gap

        // ---- CPU: hero % + history graph + per-core bar grid ----
        Card {
            theme: root.theme
            width: root.cardWidth
            height: parent.height

            Item {
                anchors.fill: parent
                anchors.margins: root.theme.space(16)

                Column {
                    id: cpuTop
                    width: parent.width
                    spacing: root.theme.spacing.rowGap
                    SectionLabel { theme: root.theme; icon: "󰻠"; text: "CPU" }
                    SectionSeparator { theme: root.theme }
                    HeroRow {
                        value: root.systemStats.cpuPercent.toFixed(0) + "%"
                        detail: root.systemStats.corePercents.length + " cores"
                    }
                }

                Graph {
                    anchors.top: cpuTop.bottom
                    anchors.topMargin: root.theme.spacing.rowGap
                    anchors.bottom: cpuBottom.top
                    anchors.bottomMargin: root.theme.spacing.rowGap
                    width: parent.width
                    values: root.systemStats.cpuHistory
                    maxValue: 100
                }

                Column {
                    id: cpuBottom
                    width: parent.width
                    anchors.bottom: parent.bottom
                    spacing: root.theme.spacing.sm
                    SectionLabel { theme: root.theme; text: "PER CORE" }
                    Row {
                        id: coreBars
                        width: parent.width
                        height: root.theme.space(28)
                        spacing: root.theme.spacing.xs
                        Repeater {
                            model: root.systemStats.corePercents
                            delegate: Rectangle {
                                id: coreSlot
                                required property real modelData
                                width: (coreBars.width - coreBars.spacing * Math.max(0, root.systemStats.corePercents.length - 1)) / Math.max(1, root.systemStats.corePercents.length)
                                height: coreBars.height
                                color: root.theme.controlFillHover // track, so the grid reads at idle too
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
        }

        // ---- MEMORY: hero % + history graph, used/total on the baseline ----
        Card {
            theme: root.theme
            width: root.cardWidth
            height: parent.height

            Item {
                anchors.fill: parent
                anchors.margins: root.theme.space(16)

                Column {
                    id: memTop
                    width: parent.width
                    spacing: root.theme.spacing.rowGap
                    SectionLabel { theme: root.theme; icon: "󰍛"; text: "MEMORY" }
                    SectionSeparator { theme: root.theme }
                    HeroRow {
                        value: root.systemStats.memUsedPercent.toFixed(0) + "%"
                        detail: root.fmtGb(root.systemStats.memUsedMb) + " / " + root.fmtGb(root.systemStats.memTotalMb) + " GB"
                    }
                }

                Graph {
                    anchors.top: memTop.bottom
                    anchors.topMargin: root.theme.spacing.rowGap
                    anchors.bottom: parent.bottom
                    width: parent.width
                    values: root.systemStats.memHistory
                    maxValue: 100
                }
            }
        }

        // ---- NETWORK: rx/tx + combined-throughput history graph ----
        Card {
            theme: root.theme
            width: root.cardWidth
            height: parent.height

            Item {
                anchors.fill: parent
                anchors.margins: root.theme.space(16)

                Column {
                    id: netTop
                    width: parent.width
                    spacing: root.theme.spacing.rowGap
                    SectionLabel { theme: root.theme; icon: "󰛳"; text: "NETWORK" }
                    SectionSeparator { theme: root.theme }
                    Row {
                        spacing: root.theme.space(24)
                        Repeater {
                            model: [
                                { icon: "󰇚", rate: root.systemStats.netRxKBs },
                                { icon: "󰕒", rate: root.systemStats.netTxKBs },
                            ]
                            delegate: Row {
                                id: rateRow
                                required property var modelData
                                spacing: root.theme.spacing.md
                                Text {
                                    text: rateRow.modelData.icon
                                    textFormat: Text.PlainText
                                    color: root.theme.secondaryForeground
                                    font.family: root.theme.font.family
                                    font.pixelSize: root.theme.font.display
                                    anchors.baseline: parent.children[1].baseline
                                }
                                Text {
                                    text: root.fmtRate(rateRow.modelData.rate)
                                    textFormat: Text.PlainText
                                    color: root.theme.foreground
                                    font.family: root.theme.font.family
                                    font.pixelSize: root.theme.font.displayLarge
                                    font.bold: true
                                }
                            }
                        }
                    }
                }

                Graph {
                    anchors.top: netTop.bottom
                    anchors.topMargin: root.theme.spacing.rowGap
                    anchors.bottom: parent.bottom
                    width: parent.width
                    values: root.systemStats.netHistory
                    maxValue: root.systemStats.netHistoryMax
                }
            }
        }
    }
}
