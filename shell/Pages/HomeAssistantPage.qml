import QtQuick
import QtWebEngine
import Quickshell
import Quickshell.Io

// Home Assistant dashboard — NOT currently wired into the page rotation (see
// Services/KnobRouter.qml). Embedding WebEngineView directly inside a Quickshell scene
// crashes hard: QQuickWebEngineView's constructor aborts with "the program name is not
// passed to QCoreApplication. base::CommandLine cannot be properly initialized." —
// confirmed live. Chromium needs `QtWebEngineQuick::initialize()` called before
// QGuiApplication is constructed, which Quickshell's own binary does not do, so this is
// not fixable from QML alone. Kept here for when this page comes back as an external
// kiosk browser window that our shell yields to (rather than an embedded WebEngineView).
// Reads url/token from ~/.config/omarchy-quake-panel/config.json.
Item {
    id: root

    property string haUrl: ""
    property string haToken: ""

    FileView {
        id: configFile
        path: Quickshell.env("HOME") + "/.config/omarchy-quake-panel/config.json"
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                var cfg = JSON.parse(text())
                var ha = cfg.homeAssistant || {}
                root.haUrl = ha.url || ""
                root.haToken = ha.token || ""
            } catch (e) { console.log("HomeAssistantPage: bad config.json: " + e) }
        }
        onLoadFailed: function (error) { /* no config yet — show the placeholder below */ }
    }

    WebEngineView {
        anchors.fill: parent
        visible: root.haUrl !== ""
        url: root.haUrl || "about:blank"
    }

    Column {
        anchors.centerIn: parent
        visible: root.haUrl === ""
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No Home Assistant URL configured"
            color: "#8a94a3"
            font.pixelSize: 22
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Edit ~/.config/omarchy-quake-panel/config.json"
            color: "#5a6472"
            font.pixelSize: 16
            font.family: "monospace"
        }
    }
}
