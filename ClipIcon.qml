import QtQuick
import qs.Commons

// Clipboard with text lines (md-clipboard_text_outline) and small sparkles
// (md-creation) in its top-right corner: "clipboard + AI". Fills whatever
// square it is given; the clipboard is shifted down-left so the sparkles sit
// in the free corner without touching the clip.
Item {
  id: icon

  property color color: Color.foreground
  property string fontFamily: Style.font.family
  readonly property real size: Math.min(width, height)

  implicitWidth: Style.bar.iconCanvas
  implicitHeight: Style.bar.iconCanvas

  Text {
    text: "󰨸"
    color: icon.color
    font.family: icon.fontFamily
    font.pixelSize: Math.round(icon.size * 0.86)
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: -icon.size * 0.1
    anchors.verticalCenterOffset: icon.size * 0.08
  }

  Text {
    text: "󰙴"
    color: icon.color
    font.family: icon.fontFamily
    font.pixelSize: Math.round(icon.size * 0.5)
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: icon.size * 0.36
    anchors.verticalCenterOffset: -icon.size * 0.34
  }
}
