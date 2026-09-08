import QtQuick
import Quickshell.Io

// Wraps the daemon child process: parses its stdout JSON-lines protocol into signals, and
// exposes sendCommand() for the stdin JSON-command protocol (see daemon/src/bridge.js).
//
// Not a `pragma Singleton` — Omarchy's own shell.qml notes relative-path imports don't
// share singleton state in Quickshell, silently leaving each importer its own empty copy.
// Instantiate ONE HidBridge in shell.qml and pass it down to pages as a property instead.
QtObject {
    id: root

    required property string daemonPath

    signal touchEvent(var points)
    signal knobEvent(var event)
    signal keyEvent(var event)
    signal stateEvent(var state)
    signal connected(string iface)
    signal disconnected(string iface)
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
                try { msg = JSON.parse(line) } catch (e) { console.log("HidBridge: bad JSON from daemon: " + line); return }
                if (msg.t === "touch") root.touchEvent(msg.points)
                else if (msg.t === "knob") root.knobEvent(msg.event)
                else if (msg.t === "key") root.keyEvent(msg.event)
                else if (msg.t === "state") root.stateEvent(msg.state)
                else if (msg.t === "connect") root.connected(msg.iface)
                else if (msg.t === "disconnect") root.disconnected(msg.iface)
                else if (msg.t === "error") root.daemonError(msg.message)
            }
        }
        stderr: SplitParser {
            onRead: function (line) { console.log("[daemon:stderr] " + line) }
        }
        onExited: function (code, status) { console.log("HidBridge: daemon process exited, code=" + code) }
    }
}
