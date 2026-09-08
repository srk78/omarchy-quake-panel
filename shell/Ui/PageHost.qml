import QtQuick
import "../Pages"

// Swaps between the active pages based on KnobRouter.currentPageIndex. HomeAssistantPage
// is not wired in yet — see KnobRouter.qml's header comment.
Item {
    id: root
    required property var knobRouter
    required property var systemStats
    required property var personalCareState
    required property var hidBridge
    required property var touchRouter
    required property var theme

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.knobRouter.currentPageIndex) {
                case 0: return dashboardComp
                case 1: return careComp
                default: return dashboardComp
            }
        }
    }

    Component { id: dashboardComp; DashboardPage { systemStats: root.systemStats; theme: root.theme } }
    Component { id: careComp; PersonalCarePage { personalCareState: root.personalCareState; touchRouter: root.touchRouter; theme: root.theme } }
}
