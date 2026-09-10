import QtQuick
import Quickshell
import Quickshell.Io

// Pomodoro + water + stand-reminder state machine, persisted to
// ~/.local/state/omarchy-quake-panel/personal-care.json.
//
// Properties are flattened (rather than one nested JS `state` object) so QML bindings on
// PersonalCarePage react automatically to every change — mutating a field on a plain JS
// object does not fire QML property-change notifications on its own.
QtObject {
    id: root

    signal reminder(string message)
    // Emitted when the user wants to log water but hasn't picked an amount yet (knob hold,
    // or the on-screen button) — the UI shows WaterAmountPicker and calls logWater(ml)
    // once a choice is made. Kept separate from logWater() itself so both the knob and
    // touch paths funnel through one picker instead of each guessing an amount.
    signal requestWaterAmount()

    // ---- config (hardcode defaults for v1; move to config.json later) ----
    readonly property int waterThresholdMs: 50 * 60 * 1000
    readonly property int standIntervalMs: 50 * 60 * 1000
    readonly property int pomodoroWorkMs: 25 * 60 * 1000
    readonly property int pomodoroBreakMs: 5 * 60 * 1000
    readonly property var mlPresets: [100, 150, 200, 250, 300, 400, 500, 750]

    // ---- reactive state (persisted) ----
    property string day: ""
    property real lastDrinkAt: 0
    property int todayWaterCount: 0
    property real todayWaterMl: 0
    property int lastAmountMl: 250
    property var waterLog: [] // [{t, ml}, ...]
    property int todayPomodoroCount: 0
    property bool pomodoroRunning: false
    property string pomodoroPhase: "work" // "work" | "break"
    property real pomodoroPhaseEndsAt: 0
    property real lastStandAt: 0

    readonly property string _statePath: Quickshell.env("HOME") + "/.local/state/omarchy-quake-panel/personal-care.json"
    property bool _loaded: false

    function _todayKey() {
        var d = new Date()
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    // Lazy/pull-based rollover: checked on every mutation entry point rather than an
    // always-on midnight timer, so a shell that was asleep/restarted across midnight can't
    // miss it.
    function _rollOverIfNeeded() {
        var key = root._todayKey()
        if (root.day !== key) {
            root.day = key
            root.todayWaterCount = 0
            root.todayWaterMl = 0
            root.waterLog = []
            root.todayPomodoroCount = 0
        }
    }

    function _load(text) {
        var parsed = {}
        try { if (text) parsed = JSON.parse(text) } catch (e) { console.log("PersonalCareState: bad state JSON, starting fresh: " + e) }
        root.day = parsed.day || root._todayKey()
        var water = parsed.water || {}
        root.lastDrinkAt = water.lastDrinkAt || 0
        root.todayWaterCount = water.todayCount || 0
        root.todayWaterMl = water.todayMl || 0
        root.lastAmountMl = water.lastAmountMl || 250
        root.waterLog = water.log || []
        var pomodoro = parsed.pomodoro || {}
        root.todayPomodoroCount = pomodoro.todayCompleted || 0
        root.pomodoroRunning = false // never resume a "running" state across a restart
        root.pomodoroPhase = pomodoro.phase || "work"
        root.pomodoroPhaseEndsAt = 0
        var stand = parsed.stand || {}
        root.lastStandAt = stand.lastStandAt || 0
        root._loaded = true
        root._rollOverIfNeeded()
    }

    function _persist() {
        if (!root._loaded) return // never overwrite on-disk state with defaults before the initial load completes
        var payload = {
            day: root.day,
            water: { lastDrinkAt: root.lastDrinkAt, todayCount: root.todayWaterCount, todayMl: root.todayWaterMl, lastAmountMl: root.lastAmountMl, log: root.waterLog },
            pomodoro: { todayCompleted: root.todayPomodoroCount, running: root.pomodoroRunning, phase: root.pomodoroPhase, phaseEndsAt: root.pomodoroPhaseEndsAt },
            stand: { lastStandAt: root.lastStandAt },
        }
        stateFile.setText(JSON.stringify(payload, null, 2))
    }

    property FileView stateFile: FileView {
        path: root._statePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root._load(text())
        onLoadFailed: function (error) { root._load("") }
    }

    // Ensure the state directory exists before the first write — FileView does not create
    // parent directories itself.
    property Process _mkdirProc: Process {
        command: [ "mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy-quake-panel" ]
        running: true
    }

    // ---- water ----
    // Takes the amount in ml (chosen via WaterAmountPicker) — callers never guess an
    // amount themselves, they emit requestWaterAmount() and wait for the picker's choice.
    function logWater(amountMl) {
        root._rollOverIfNeeded()
        var now = Date.now()
        var ml = Math.max(1, Math.round(amountMl))
        root.lastDrinkAt = now
        root.todayWaterCount += 1
        root.todayWaterMl += ml
        root.lastAmountMl = ml
        root.waterLog = root.waterLog.concat([{ t: now, ml: ml }])
        root._persist()
        // Drinking resets when the next reminder is needed, but must never touch pomodoro
        // state — that guarantee is structural: this function has no code path that writes
        // any pomodoro* property.
        if (root.pomodoroRunning) {
            waterReminderTimer.stop()
            waterReminderTimer.interval = root.waterThresholdMs
            waterReminderTimer.start()
        }
    }

    property Timer waterReminderTimer: Timer {
        repeat: false
        onTriggered: root.reminder("Time to drink some water")
    }

    // ---- stand (fully independent of pomodoro/water) ----
    property Timer standReminderTimer: Timer {
        interval: root.standIntervalMs
        repeat: true
        running: true
        onTriggered: { root.lastStandAt = Date.now(); root.reminder("Time to stand up and stretch") }
    }

    // Manual "I just stood up" reset (the Stand panel's Reset button) — marks now as the
    // last stand and restarts the countdown, same as a real stand would, without waiting
    // for the timer to fire on its own.
    function resetStand() {
        root.lastStandAt = Date.now()
        standReminderTimer.restart()
        root._persist()
    }

    // ---- pomodoro ----
    property Timer pomodoroTimer: Timer {
        repeat: false
        onTriggered: root._onPhaseEnd()
    }
    // Remaining time left in the current phase when paused — resuming continues from here
    // instead of restarting the full phase. Left at 0 after a phase completes naturally
    // (see _onPhaseEnd -> _startPomodoro) or after a manual reset, so those paths get a
    // fresh full duration instead of resuming a stale one. Not underscore-prefixed
    // (unlike this file's other internal state) because PersonalCarePage.qml reads it
    // directly to tell "genuinely paused mid-session" apart from "fresh/just reset" —
    // both show pomodoroRunning === false, and only this distinguishes them.
    property real pausedRemainingMs: 0

    function togglePomodoro() {
        if (root.pomodoroRunning) root._pausePomodoro()
        else root._startPomodoro()
    }

    function _startPomodoro() {
        root._rollOverIfNeeded()
        var now = Date.now()
        var elapsed = now - root.lastDrinkAt
        if (root.lastDrinkAt === 0 || elapsed >= root.waterThresholdMs) {
            root.reminder("Drink some water before you start")
        } else {
            waterReminderTimer.stop()
            waterReminderTimer.interval = Math.max(1, root.waterThresholdMs - elapsed)
            waterReminderTimer.start()
        }
        root.pomodoroRunning = true
        var dur = root.pausedRemainingMs > 0 ? root.pausedRemainingMs : (root.pomodoroPhase === "work" ? root.pomodoroWorkMs : root.pomodoroBreakMs)
        root.pausedRemainingMs = 0
        root.pomodoroPhaseEndsAt = now + dur
        pomodoroTimer.stop()
        pomodoroTimer.interval = dur
        pomodoroTimer.start()
        root._persist()
    }

    function _pausePomodoro() {
        root.pomodoroRunning = false
        root.pausedRemainingMs = Math.max(0, root.pomodoroPhaseEndsAt - Date.now())
        pomodoroTimer.stop()
        waterReminderTimer.stop() // scoped to the running session that scheduled it — see PLAN.md
        root._persist()
    }

    // Manual reset (the Pomodoro panel's Reset button): stop and clear the current
    // session back to a fresh "work" phase at its full duration — NOT running, and
    // pausedRemainingMs left at 0 (not the frozen remaining time) so
    // PersonalCarePage.qml shows the full 25:00 rather than "Paused": a reset phase is
    // fresh, not mid-session-paused, even though pomodoroRunning is false either way.
    // Leaves todayPomodoroCount alone — this abandons the in-progress cycle, it doesn't
    // erase today's completed count.
    function resetPomodoro() {
        root.pomodoroRunning = false
        root.pomodoroPhase = "work"
        root.pomodoroPhaseEndsAt = 0
        root.pausedRemainingMs = 0
        pomodoroTimer.stop()
        waterReminderTimer.stop() // scoped to the running session — see _pausePomodoro
        root._persist()
    }

    function _onPhaseEnd() {
        if (root.pomodoroPhase === "work") {
            root.todayPomodoroCount += 1
            root.pomodoroPhase = "break"
            root.reminder("Work session done — take a break")
        } else {
            root.pomodoroPhase = "work"
            root.reminder("Break's over — back to work")
        }
        root._startPomodoro() // auto-continue into the next phase
    }
}
