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
  // Whether the panel's real HID device is connected (Service.qml mirrors
  // HidBridge's own connect/disconnect signals, which already reflect real hot-plug —
  // see its own comment). Picking either mode option does nothing useful without a
  // real device, so this hides them and shows a disconnected state instead.
  readonly property bool deviceConnected: service ? service.deviceConnected : false

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
    tooltipText: "Quake Panel: " + (root.deviceConnected ? (root.isKiosk ? "Kiosk" : "Second screen") : "Disconnected")
    onPressed: function (b) { root.popupOpen = !root.popupOpen }
  }

  // A diagonal strike-through over the mode icon when the panel hardware isn't
  // connected — the same "crossed" technique Omarchy's own TailscaleIcon.qml uses for
  // its disconnected state, reused here instead of introducing a brand-new
  // "disconnected" glyph: a plain Rectangle has no font-rendering risk at all (see
  // this file's own header comment on why glyph choices here get verified by actually
  // rendering them, not guessed from a codepoint name). Confirmed live: renders
  // correctly over the icon when deviceConnected is false.
  Rectangle {
    visible: !root.deviceConnected
    anchors.centerIn: button
    width: button.width * 0.62
    height: Math.max(2, button.height * 0.08)
    radius: height / 2
    color: root.bar.foreground
    rotation: -45
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

      // Picking either mode does nothing useful without a real device connected, so
      // this whole option list is replaced by a plain "Disconnected" line below when
      // it isn't. Bound through the model, not a `visible: false` on the Repeater
      // itself — a Repeater's instantiated delegates are reparented to its own parent
      // for layout, so toggling the Repeater's own `visible` does NOT hide them; an
      // empty model creates none at all, which is what's actually wanted here.
      Repeater {
        model: root.deviceConnected ? root.modeOptions : []

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

      Text {
        visible: !root.deviceConnected
        textFormat: Text.PlainText
        text: "Disconnected"
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        width: parent.width
      }
    }
  }
}
