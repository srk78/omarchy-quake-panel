import QtQuick

// A card column: icon+label header, separator, then arbitrary content, with up to two
// action buttons (`button`/`button2`) pinned to the section's own bottom edge — the
// shape `Pages/PersonalCarePage.qml` (Pomodoro/Water/Stand) and
// `Pages/SettingsPage.qml` (Brightness/Microphone) both need. Promoted here once a
// second page needed the identical shape, matching the pages-can-promote-a-repeated-
// page-local-component convention already established for `Card`/`SectionLabel`/etc.
//
// `content` lives in its own Column, anchored between the header and the button row —
// NOT just appended after the header in one big intrinsic-sized Column, which is what
// this had until Pages/PaPage.qml's transcript needed a real, non-zero viewport height
// to scroll within (a ListView with no explicit height has nothing to scroll). This
// also fixes, at the root, a real bug HISTORY.md §26 already hit: unbounded content
// (an early long reply) visually overlapping the bottom-anchored button row, since
// content now always stops exactly at the buttons' top edge instead of growing past it.
// Existing consumers (PersonalCarePage/SettingsPage) pass plain Text/HeroText/DetailText
// content with no anchors of their own, so this is a no-op for them — Column positioners
// only forbid *children* from anchoring, not the Column itself, and none of those items
// do; they still stack immediately below the separator exactly as before.
Item {
    id: section
    required property var theme
    property string icon: ""
    property string label: ""
    default property alias content: contentColumn.data
    property alias button: buttonLoader.sourceComponent
    property alias button2: button2Loader.sourceComponent
    height: parent.height

    Column {
        id: header
        width: parent.width
        spacing: section.theme.spacing.rowGap
        SectionLabel { theme: section.theme; icon: section.icon; text: section.label }
        SectionSeparator { theme: section.theme }
    }
    Column {
        id: contentColumn
        anchors.top: header.bottom
        anchors.topMargin: section.theme.spacing.rowGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: buttonRow.top
        anchors.bottomMargin: section.theme.spacing.rowGap
        spacing: section.theme.spacing.rowGap
    }
    Row {
        id: buttonRow
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        spacing: section.theme.spacing.sm
        Loader { id: buttonLoader }
        Loader { id: button2Loader }
    }
}
