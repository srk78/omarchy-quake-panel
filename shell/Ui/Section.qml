import QtQuick

// A card column: icon+label header, separator, then arbitrary content, with up to two
// action buttons (`button`/`button2`) pinned to the section's own bottom edge — the
// shape `Pages/PersonalCarePage.qml` (Pomodoro/Water/Stand) and
// `Pages/SettingsPage.qml` (Brightness/Microphone) both need. Promoted here once a
// second page needed the identical shape, matching the pages-can-promote-a-repeated-
// page-local-component convention already established for `Card`/`SectionLabel`/etc.
Item {
    id: section
    required property var theme
    property string icon: ""
    property string label: ""
    default property alias content: sectionBody.data
    property alias button: buttonLoader.sourceComponent
    property alias button2: button2Loader.sourceComponent
    height: parent.height

    Column {
        id: sectionBody
        width: parent.width
        spacing: section.theme.spacing.rowGap
        SectionLabel { theme: section.theme; icon: section.icon; text: section.label }
        SectionSeparator { theme: section.theme }
    }
    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        spacing: section.theme.spacing.sm
        Loader { id: buttonLoader }
        Loader { id: button2Loader }
    }
}
