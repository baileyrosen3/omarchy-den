import QtQuick

// A shelter with an open, arched entrance. Keep in sync with docs/den.svg.
Canvas {
  id: icon
  property color color: "white"
  antialiasing: true
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.scale(width / 24, height / 24)
    ctx.strokeStyle = color
    ctx.lineWidth = 1.8
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()
    ctx.moveTo(3, 20)
    ctx.lineTo(5.5, 10)
    ctx.bezierCurveTo(6.6, 5.7, 8.6, 3, 12, 3)
    ctx.bezierCurveTo(15.4, 3, 17.4, 5.7, 18.5, 10)
    ctx.lineTo(21, 20)
    ctx.lineTo(15.5, 20)
    ctx.lineTo(15.5, 16)
    ctx.bezierCurveTo(15.5, 14, 14, 12.5, 12, 12.5)
    ctx.bezierCurveTo(10, 12.5, 8.5, 14, 8.5, 16)
    ctx.lineTo(8.5, 20)
    ctx.closePath()
    ctx.stroke()
  }
}
