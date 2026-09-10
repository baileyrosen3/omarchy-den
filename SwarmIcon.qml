import QtQuick

// Three connected honeycomb cells. Vector geometry follows the desktop palette.
Canvas {
  id: icon
  property color color: "white"
  onColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.scale(width / 24, height / 24)
    ctx.strokeStyle = color
    ctx.lineWidth = 1.55
    ctx.lineJoin = "round"
    var centers = [[12, 6.5], [7.5, 14.3], [16.5, 14.3]]
    for (var c = 0; c < centers.length; c++) {
      ctx.beginPath()
      for (var i = 0; i < 6; i++) {
        var angle = Math.PI / 3 * i - Math.PI / 6
        var x = centers[c][0] + Math.cos(angle) * 5.2
        var y = centers[c][1] + Math.sin(angle) * 5.2
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.closePath()
      ctx.stroke()
    }
  }
}
