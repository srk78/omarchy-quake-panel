import QtQuick
import Quickshell.Io

// Wraps the paBridge.js daemon child process — same shape as HidBridge.qml (JSON-lines
// stdout, JSON-command stdin), but a SEPARATE process/connection. Kept apart from
// HidBridge on purpose: a `claude` CLI call can take several seconds, and this process
// must never be able to block or destabilize the HID/touch daemon everything else in
// this app depends on. See daemon/src/paBridge.js's own header for the wire protocol.
QtObject {
    id: root

    required property string daemonPath

    signal stateEvent(var state)
    signal transcript(string text)
    signal reply(string text)
    signal daemonError(string message)

    function sendCommand(cmdObj) {
        proc.write(JSON.stringify(cmdObj) + "\n")
    }

    property Process proc: Process {
        command: [ "node", root.daemonPath ]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function (line) {
                var msg
                try { msg = JSON.parse(line) } catch (e) { console.log("PaBridge: bad JSON from daemon: " + line); return }
                if (msg.t === "state") root.stateEvent(msg.state)
                else if (msg.t === "transcript") root.transcript(msg.text)
                else if (msg.t === "reply") root.reply(msg.text)
                else if (msg.t === "error") root.daemonError(msg.message)
            }
        }
        stderr: SplitParser {
            onRead: function (line) { console.log("[paBridge:stderr] " + line) }
        }
        onExited: function (code, status) { console.log("PaBridge: daemon process exited, code=" + code) }
    }
}
