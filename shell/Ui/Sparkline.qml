import QtQuick

// A filled area/line history graph — btop's core visual idiom (a live-scrolling load
// graph), built with Canvas since Quickshell/QtQuick has no chart component.
Canvas {
    id: canvas
    property var values: []       // 0..maxValue range, oldest first
    property real maxValue: 100
    property color lineColor: "white"
    property color fillColor: Qt.rgba(1, 1, 1, 0.15)
    property real lineWidth: 2

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onLineColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (values.length < 2 || width <= 0 || height <= 0) return
        var w = width, h = height
        var stepX = w / (values.length - 1)
        var yFor = function (v) { return h - Math.max(0, Math.min(1, v / canvas.maxValue)) * h }

        ctx.beginPath()
        ctx.moveTo(0, yFor(values[0]))
        for (var i = 1; i < values.length; i++) ctx.lineTo(i * stepX, yFor(values[i]))
        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.fillStyle = fillColor
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(0, yFor(values[0]))
        for (var j = 1; j < values.length; j++) ctx.lineTo(j * stepX, yFor(values[j]))
        ctx.strokeStyle = lineColor
        ctx.lineWidth = lineWidth
        ctx.stroke()
    }
}
