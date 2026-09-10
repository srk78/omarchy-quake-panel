import QtQuick

// Per-page knob mode table — the QML analog of Bedrock Panel's `effectiveKnob`/
// `knobRouting.js`: raw hardware gestures come in verbatim, and this resolves what they
// mean on the currently active page. Global gestures (rotate = switch page, hold = log
// water from any page) live here directly since there are only a few pages; `press`
// is the one gesture that varies per page.
//
// ToastOverlay deliberately has NO wiring into this router at all — reminders can never
// steal or reinterpret a knob gesture. That is what actually guarantees reminders don't
// interfere with the pomodoro, not just a convention.
QtObject {
    id: root

    // Home Assistant page is out of the rotation for now — embedding a WebEngineView
    // inside Quickshell crashes hard (Chromium's base::CommandLine needs
    // QtWebEngineQuick::initialize() called before QGuiApplication is constructed, which
    // Quickshell's own binary doesn't do). See Pages/HomeAssistantPage.qml and the repo
    // README for the plan to revisit this (external kiosk browser window instead).
    property int currentPageIndex: 0 // 0=System, 1=PersonalCare, 2=Settings, 3=PA
    readonly property int pageCount: 4
    required property var personalCareState
    required property var waterAmountPicker
    required property var paState

    readonly property var modeTable: [
        { press: "noop" },           // 0: System
        { press: "pomodoroToggle" }, // 1: Personal Care
        { press: "noop" },           // 2: Settings
        { press: "pushToTalk" },     // 3: PA — press to start listening, press again to send
    ]

    function dispatch(event) {
        // While the water-amount picker is open, the knob drives IT instead of its normal
        // per-page meaning — rotate cycles the highlighted amount, press confirms. This is
        // the one place a global overlay is allowed to borrow the knob: it's a deliberate,
        // synchronous menu the user just opened, not a background reminder (contrast
        // ToastOverlay, which never touches the knob at all).
        if (root.waterAmountPicker.shown) {
            if (event.type === "rotate") root.waterAmountPicker.moveSelection(event.dir)
            else if (event.type === "press") root.waterAmountPicker.confirm()
            return
        }
        if (event.type === "rotate") {
            currentPageIndex = (currentPageIndex + (event.dir > 0 ? 1 : -1) + pageCount) % pageCount
        } else if (event.type === "hold") {
            if (event.phase === "start") personalCareState.requestWaterAmount()
        } else if (event.type === "press") {
            var action = root.modeTable[root.currentPageIndex].press
            if (action === "pomodoroToggle") personalCareState.togglePomodoro()
            else if (action === "pushToTalk") paState.togglePushToTalk()
            // "noop" on System/Settings intentionally does nothing in v1
        }
    }
}
