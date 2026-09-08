import QtQuick
import Quickshell.Io

// Polls CPU/RAM/network via plain `cat`/`sh` reads on a Timer — no FileView polling API
// exists (it's inotify-watch only), so Timer+Process is the idiomatic Quickshell pattern
// for periodic stats (mirrors Omarchy's own shell, e.g. plugins/panels/power/Panel.qml).
//
// Also tracks rolling history (for Dashboard's btop-style graphs) and per-core CPU load
// (for the per-core bar grid) — /proc/stat has one "cpu" aggregate line plus one "cpuN"
// line per logical core.
QtObject {
    id: root

    readonly property int historyLen: 60

    property real cpuPercent: 0
    property var cpuHistory: []      // last historyLen samples, 0..100, oldest first
    property var corePercents: []    // one entry per logical core, this poll only

    property real memUsedPercent: 0
    property var memHistory: []      // last historyLen samples, 0..100, oldest first
    property real memTotalMb: 0
    property real memUsedMb: 0

    property real netRxKBs: 0
    property real netTxKBs: 0
    property var netHistory: []      // last historyLen samples of (rx+tx) KB/s, oldest first
    property real netHistoryMax: 1   // running max, for graph auto-scaling (KB/s)

    property string clockText: ""

    property var _prevCpuTotal: null      // {idle,total} for the aggregate "cpu" line
    property var _prevCoreCpu: ({})       // "cpuN" -> {idle,total}
    property var _prevNetBytes: null
    property real _prevNetT: 0

    function _pushHistory(arr, value) {
        var next = arr.concat([value])
        if (next.length > root.historyLen) next = next.slice(next.length - root.historyLen)
        return next
    }

    property Timer _pollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { cpuProc.running = true; memProc.running = true; netProc.running = true }
    }

    property Timer _clockTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.clockText = Qt.formatDateTime(new Date(), "dddd, MMMM d — hh:mm:ss")
    }

    function _pctFromDelta(prev, idle, total) {
        if (!prev) return 0
        var dIdle = idle - prev.idle
        var dTotal = total - prev.total
        if (dTotal <= 0) return 0
        return Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
    }

    function _onCpu(text) {
        var lines = text.split("\n")
        var nextCoreMap = {}
        var cores = []
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].trim().match(/^(cpu\d*)\s+(.*)$/)
            if (!m) continue
            var label = m[1]
            var parts = m[2].split(/\s+/).map(Number)
            if (parts.length < 4) continue
            var idle = parts[3] + (parts[4] || 0)
            var total = parts.reduce(function (a, b) { return a + b }, 0)
            if (label === "cpu") {
                var pct = root._pctFromDelta(root._prevCpuTotal, idle, total)
                root.cpuPercent = pct
                root.cpuHistory = root._pushHistory(root.cpuHistory, pct)
                root._prevCpuTotal = { idle: idle, total: total }
            } else {
                var corePct = root._pctFromDelta(root._prevCoreCpu[label], idle, total)
                cores.push(corePct)
                nextCoreMap[label] = { idle: idle, total: total }
            }
        }
        root._prevCoreCpu = nextCoreMap
        root.corePercents = cores
    }

    function _onMem(text) {
        var total = 0, avail = 0
        text.split("\n").forEach(function (line) {
            var m
            if ((m = line.match(/^MemTotal:\s+(\d+)/))) total = parseInt(m[1])
            else if ((m = line.match(/^MemAvailable:\s+(\d+)/))) avail = parseInt(m[1])
        })
        root.memTotalMb = total / 1024
        root.memUsedMb = (total - avail) / 1024
        var pct = total > 0 ? 100 * (total - avail) / total : 0
        root.memUsedPercent = pct
        root.memHistory = root._pushHistory(root.memHistory, pct)
    }

    function _onNet(text) {
        var nums = text.split("\n").map(function (s) { return parseInt(s) }).filter(function (n) { return !isNaN(n) })
        var half = Math.floor(nums.length / 2)
        var rx = nums.slice(0, half).reduce(function (a, b) { return a + b }, 0)
        var tx = nums.slice(half).reduce(function (a, b) { return a + b }, 0)
        var now = Date.now()
        if (root._prevNetBytes) {
            var dt = (now - root._prevNetT) / 1000
            if (dt > 0) {
                root.netRxKBs = Math.max(0, (rx - root._prevNetBytes.rx) / 1024 / dt)
                root.netTxKBs = Math.max(0, (tx - root._prevNetBytes.tx) / 1024 / dt)
                var total = root.netRxKBs + root.netTxKBs
                root.netHistoryMax = Math.max(root.netHistoryMax * 0.98, total, 1) // slow decay so the scale settles rather than jumping every sample
                root.netHistory = root._pushHistory(root.netHistory, total)
            }
        }
        root._prevNetBytes = { rx: rx, tx: tx }
        root._prevNetT = now
    }

    property Process cpuProc: Process {
        command: [ "cat", "/proc/stat" ]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._onCpu(text) }
    }
    property Process memProc: Process {
        command: [ "cat", "/proc/meminfo" ]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._onMem(text) }
    }
    property Process netProc: Process {
        command: [ "sh", "-c", "cat /sys/class/net/*/statistics/rx_bytes /sys/class/net/*/statistics/tx_bytes 2>/dev/null" ]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._onNet(text) }
    }
}
