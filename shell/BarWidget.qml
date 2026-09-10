import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar-widget half of this plugin — a top-bar icon + dropdown for the same
// kiosk/desktop mode shell/Service.qml already owns (persisted mode flag,
// IpcHandler, knob long-hold). This file only reads and writes that state; it
// never duplicates it, exactly the split omarchy.media uses for its own
// two-kind manifest (Service.qml does the work and is always loaded,
// BarWidget.qml is only mounted while a bar is on screen).
//
// `bar.shell.serviceFor(pluginId)` is shell.qml's own generic lookup for ANY
// enabled "service"-kind plugin, not just first-party ones (see
// firstPartyServiceFor(), a thin alias over the same function) — it returns
// Service.qml's root Item directly, so `service.mode`/`service.setMode()`
// read/write the exact same properties/functions the knob long-hold and
// `omarchy-shell quake-panel` IPC already use. No new IPC surface needed:
// this is just another caller of the one that already existed.
//
// This only works once the service half is actually loaded (it's declared
// `kinds: ["service", "bar-widget"]` in the same manifest, so enabling this
// plugin at all starts both) — while that hasn't happened yet (e.g. a stale
// cache mid-reload) `service` is null and the icon/dropdown fall back to
// "kiosk" without erroring.
BarWidget {
  id: root
  moduleName: "srk78.quake-panel"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property string mode: service ? service.mode : "kiosk"
  readonly property bool isKiosk: mode === "kiosk"

  // Nerd Font glyphs, verified by actually rendering each candidate
  // codepoint with the real live font (JetBrainsMono Nerd Font — confirmed
  // via `fc-match monospace`, NOT the CaskaydiaMono this repo's other pages
  // happen to have installed) and looking at the result: a codepoint's
  // *name* in the Material Design Icons set does not reliably predict what
  // it renders as in a given Nerd Font patch revision (0xF0F26, nominally
  // "tablet", actually renders as a media skip-forward glyph here — caught
  // only by rendering it, not by a cmap presence check). "cellphone"
  // (0xF011C) renders as an actual small handheld-touchscreen silhouette —
  // a good visual match for "dedicated panel device". desktop-classic
  // (0xF0379) is the exact glyph Omarchy's own Display/omarchy.monitor
  // bar-widget uses for an ordinary screen, confirmed correct the same way.
  readonly property string kioskIcon: "󰄜"
  readonly property string desktopIcon: "󰍹"

  readonly property var modeOptions: [
    { key: "kiosk", label: "Kiosk", detail: "Dashboard & Self Care", icon: root.kioskIcon },
    { key: "desktop", label: "Second screen", detail: "Ordinary desktop output", icon: root.desktopIcon }
  ]

  property bool popupOpen: false
  function close() { popupOpen = false }

  implicitWidth: barSize
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.isKiosk ? root.kioskIcon : root.desktopIcon
    tooltipText: "Quake Panel: " + (root.isKiosk ? "Kiosk" : "Second screen")
    onPressed: function (b) { root.popupOpen = !root.popupOpen }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(240))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      PanelSectionHeader {
        text: "QUAKE PANEL"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Repeater {
        model: root.modeOptions

        delegate: BorderSurface {
          id: optionRow
          required property var modelData
          readonly property bool selected: root.mode === optionRow.modelData.key

          width: column.width
          height: rowInner.implicitHeight + Style.space(12)
          radius: Style.spacing.labelGap
          color: optionRow.selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
          borderSpec: optionRow.selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

          Row {
            id: rowInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: optionRow.borderLeft + Style.space(8)
            anchors.rightMargin: optionRow.borderRight + Style.space(8)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: optionRow.modelData.icon
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              width: Style.space(18)
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              width: parent.width - Style.space(26)
              spacing: Style.space(1)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                textFormat: Text.PlainText
                text: optionRow.modelData.label
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: optionRow.selected
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: optionRow.modelData.detail
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.service) root.service.setMode(optionRow.modelData.key)
              root.close()
            }
          }
        }
      }
    }
  }
}
