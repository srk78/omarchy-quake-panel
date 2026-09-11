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
    // Fired ~30x/sec while Foxy's own reply is playing (paBridge.js's speak() streams
    // this from the reply audio's own precomputed volume envelope, not a live mic tap —
    // see Ui/FoxyVisualizer.qml and HISTORY.md). 0..1, normalized.
    signal audioLevel(real value)

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
                else if (msg.t === "audioLevel") root.audioLevel(msg.value)
            }
        }
        stderr: SplitParser {
            onRead: function (line) { console.log("[paBridge:stderr] " + line) }
        }
        onExited: function (code, status) { console.log("PaBridge: daemon process exited, code=" + code) }
    }
}
