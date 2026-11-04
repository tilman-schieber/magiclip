pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui

// Bar button for MagiClip: click for the settings (result mode, model,
// prompts); right-click runs the overlay. "Show in bar" off hides the button
// (settings stay reachable from the overlay with Ctrl+S).
Ui.Panel {
  id: root
  moduleName: "io.github.tilman-schieber.magiclip"
  ipcTarget: "magiclip"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Store { id: store }

  property bool openAdvanced: false
  onOpenedChanged: if (opened) {
    settingsView.page = root.openAdvanced ? "advanced" : "main"
    root.openAdvanced = false
  }

  // omarchy-shell magiclip open | close | toggle | advanced
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function advanced(): void {
      if (root.opened) settingsView.page = "advanced"
      else { root.openAdvanced = true; root.open() }
    }
  }

  function runOverlay() {
    root.close()
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.tilman-schieber.magiclip"])
  }

  visible: store.showInBar
  implicitWidth: visible ? iconButton.implicitWidth : 0
  implicitHeight: iconButton.implicitHeight

  Ui.BarIconButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      ClipIcon {
        color: iconButton.foreground
        fontFamily: iconButton.fontFamily
      }
    }
    tooltipText: "MagiClip · " + store.modelLabel(store.model)
      + (store.mode === "silent" ? " · replaces silently" : " · shows result")
      + "\nClick: settings · Right-click: run on clipboard (Super+Alt+V)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runOverlay()
      else root.toggle()
    }
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: iconButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.spacing.lg

        Ui.PanelHero {
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: "MagiClip"
          meta: store.modelLabel(store.model) + " · " + (store.mode === "silent" ? "replaces silently" : "shows result")
          iconComponent: Component {
            ClipIcon {
              width: Style.font.display * 1.3
              height: width
              color: root.foreground
              fontFamily: root.fontFamily
            }
          }
        }

        Ui.Button {
          width: parent.width
          visible: settingsView.page === "main"
          text: "Run on clipboard  (Super+Alt+V)"
          iconText: "󰅍"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.runOverlay()
        }

        SettingsView {
          id: settingsView
          width: parent.width
          store: store
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
