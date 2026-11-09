import QtQuick
import qs.Commons
import qs.Ui as Ui

// Settings UI shared by the bar widget's panel and the overlay (Ctrl+S).
// Two pages: "main" (result mode, prompts, bar) and "advanced" (model,
// effort, standing instructions), reached through the row at the bottom.
Column {
  id: view

  required property var store
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int promptListHeight: Style.space(260)
  property string page: "main"            // main | advanced

  readonly property color dim: Qt.darker(view.foreground, 1.55)
  readonly property int ruleCount: view.store.instructions.split("\n")
    .filter(function(l) { return l.trim().length > 0 }).length
  readonly property string advancedSummary: (view.store.backend === "local"
      ? view.store.backendLabel(true)
      : view.store.modelLabel(view.store.model) + " · " + view.store.effort + " effort")
    + (view.ruleCount > 0 ? " · " + view.ruleCount + (view.ruleCount === 1 ? " rule" : " rules") : "")

  readonly property var backendOptions: [
    { value: "claude", label: "Claude" },
    { value: "local", label: "Local (Ollama)" }
  ]
  readonly property string localStatusText: {
    switch (view.store.localStatus) {
    case "checking": return "Looking for models…"
    case "ok": return view.store.localModels.length + (view.store.localModels.length === 1 ? " model" : " models")
    case "empty": return "Ollama runs, but has no models. Pull one with `ollama pull <model>`."
    case "offline": return "Ollama is not reachable at " + view.store.localUrl + "."
    default: return ""
    }
  }

  onPageChanged: if (view.page === "advanced") view.store.discoverLocal()

  spacing: Style.spacing.lg

  component Label: Text {
    width: parent ? parent.width : 0
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  // A full-width clickable row: title on the left, detail and a chevron on
  // the right. Used to switch between the two pages.
  component NavRow: Item {
    id: nav
    property string title: ""
    property string detail: ""
    property bool back: false
    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(Style.spacing.controlHeight, navTitle.implicitHeight + Style.space(12))

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: navArea.containsMouse ? Util.alpha(view.foreground, 0.08) : "transparent"
      border.width: nav.back ? 0 : Style.normalBorderWidth
      border.color: Util.alpha(view.foreground, 0.25)
    }
    Text {
      id: navTitle
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      text: (nav.back ? "󰁍  " : "") + nav.title
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: nav.back ? Style.font.title : Style.font.body
    }
    Text {
      anchors.left: navTitle.right
      anchors.leftMargin: Style.spacing.md
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: nav.detail + (nav.back ? "" : "  󰅂")
      color: view.dim
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideLeft
    }
    MouseArea {
      id: navArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: nav.clicked()
    }
  }

  // ════════════════════════════ Advanced page ════════════════════════

  NavRow {
    visible: view.page === "advanced"
    back: true
    title: "Advanced"
    onClicked: view.page = "main"
  }

  // ── Backend ────────────────────────────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "advanced"

    Ui.PanelSectionHeader {
      width: parent.width
      text: "Default backend"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Ui.ButtonGroup {
      width: parent.width
      foreground: view.foreground
      fontFamily: view.fontFamily
      options: view.backendOptions
      value: view.store.backend
      onChanged: function(v) { view.store.set("backend", v) }
    }
    Label { text: "Ctrl+L in the overlay switches to the other one for a single run." }
  }

  // ── Local model ────────────────────────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "advanced"

    Item {
      width: parent.width
      implicitHeight: localHeader.implicitHeight

      Ui.PanelSectionHeader {
        id: localHeader
        width: parent.width
        text: "Local model"
        foreground: view.foreground
        fontFamily: view.fontFamily
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Refresh"
        color: refreshArea.containsMouse ? view.foreground : view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        MouseArea {
          id: refreshArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.store.discoverLocal()
        }
      }
    }
    Ui.Dropdown {
      width: parent.width
      visible: view.store.localModels.length > 0
      showLabel: false
      foreground: view.foreground
      fontFamily: view.fontFamily
      options: view.store.localModels
      value: view.store.localModel
      onChanged: function(v) { view.store.set("localModel", v) }
    }
    Label { text: view.localStatusText }
    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        id: urlLabel
        anchors.verticalCenter: urlField.verticalCenter
        text: "Server"
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
      Ui.TextField {
        id: urlField
        width: parent.width - urlLabel.width - parent.spacing
        text: view.store.localUrl
        foreground: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        onEditingFinished: {
          var url = text.trim().replace(/\/+$/, "")
          if (url && url !== view.store.localUrl) {
            view.store.set("localUrl", url)
            Qt.callLater(view.store.discoverLocal)
          }
        }
      }
    }
  }

  // ── Claude model ───────────────────────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "advanced"

    Ui.PanelSectionHeader {
      width: parent.width
      text: "Claude model"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Ui.Dropdown {
      width: parent.width
      showLabel: false
      foreground: view.foreground
      fontFamily: view.fontFamily
      options: view.store.modelOptions
      value: view.store.model
      onChanged: function(v) { view.store.set("model", v) }
    }
    Label { text: "Effort (how long it thinks)" }
    Ui.ButtonGroup {
      width: parent.width
      foreground: view.foreground
      fontFamily: view.fontFamily
      options: view.store.effortOptions
      value: view.store.effort
      onChanged: function(v) { view.store.set("effort", v) }
    }
  }

  // ════════════════════════════ Main page ════════════════════════════

  // ── After running a prompt ─────────────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "main"

    Ui.PanelSectionHeader {
      width: parent.width
      text: "Result"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }
    Ui.ButtonGroup {
      width: parent.width
      foreground: view.foreground
      fontFamily: view.fontFamily
      options: view.store.modeOptions
      value: view.store.mode
      onChanged: function(v) { view.store.set("mode", v) }
    }
    Label {
      text: view.store.mode === "review"
        ? "The answer appears in the overlay; Enter pastes it where you were, Shift+Enter only copies it."
        : "The overlay closes and the answer replaces the clipboard; a notification shows when it's done."
    }
  }

  // ── Always apply (advanced page) ───────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "advanced"

    Ui.PanelSectionHeader {
      width: parent.width
      text: "Always apply"
      foreground: view.foreground
      fontFamily: view.fontFamily
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(72), instructionsEdit.contentHeight + Style.spacing.inputPaddingY * 2)
      radius: Style.cornerRadius
      color: "transparent"
      border.width: Style.normalBorderWidth
      border.color: instructionsEdit.activeFocus ? Color.accent : Util.alpha(view.foreground, 0.25)

      Text {
        anchors.fill: instructionsEdit
        visible: instructionsEdit.text.length === 0
        text: "e.g. German uses Swiss spelling (ss, not ß). Never use em dashes."
        color: view.dim
        font: instructionsEdit.font
        wrapMode: Text.Wrap
      }

      TextEdit {
        id: instructionsEdit
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.controlPaddingX
        anchors.topMargin: Style.spacing.inputPaddingY
        anchors.bottomMargin: Style.spacing.inputPaddingY
        color: view.foreground
        selectionColor: Color.accent
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        selectByMouse: true

        function save() {
          saveTimer.stop()
          if (text !== view.store.instructions) view.store.set("instructions", text)
        }

        // Follow the file while not editing; don't clobber what is being typed.
        Component.onCompleted: text = view.store.instructions
        Connections {
          target: view.store
          function onInstructionsChanged() {
            if (!instructionsEdit.activeFocus) instructionsEdit.text = view.store.instructions
          }
        }

        onTextChanged: if (activeFocus) saveTimer.restart()
        onActiveFocusChanged: if (!activeFocus) save()

        Timer {
          id: saveTimer
          interval: 800
          onTriggered: instructionsEdit.save()
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.NoButton
          cursorShape: Qt.IBeamCursor
        }
      }
    }

    Label { text: "Added to every request, whatever the prompt. One rule per line works well." }
  }

  // ── Prompts (main page) ────────────────────────────────────────────

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: view.page === "main"

    Item {
      width: parent.width
      implicitHeight: promptsHeader.implicitHeight

      Ui.PanelSectionHeader {
        id: promptsHeader
        width: parent.width
        text: "Prompts"
        foreground: view.foreground
        fontFamily: view.fontFamily
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Reset to defaults"
        color: resetArea.containsMouse ? view.foreground : view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        MouseArea {
          id: resetArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.store.resetPrompts()
        }
      }
    }

    ListView {
      id: promptList
      width: parent.width
      height: Math.min(view.promptListHeight, contentHeight)
      clip: true
      spacing: Style.space(4)
      boundsBehavior: Flickable.StopAtBounds
      model: view.store.prompts

      delegate: Row {
        id: promptRow
        required property string modelData
        required property int index
        width: ListView.view.width
        spacing: Style.space(4)

        Ui.TextField {
          id: field
          width: promptRow.width - upButton.width - removeButton.width - promptRow.spacing * 2
          text: promptRow.modelData
          foreground: view.foreground
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          onEditingFinished: if (text !== promptRow.modelData) view.store.edit(promptRow.index, text)
          Component.onCompleted: cursorPosition = 0
          onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
        }
        Ui.PanelActionButton {
          id: upButton
          anchors.verticalCenter: field.verticalCenter
          iconText: "󰁝"
          tooltipText: "Move up"
          foreground: view.foreground
          fontFamily: view.fontFamily
          opacity: promptRow.index > 0 ? 1 : 0.3
          onClicked: view.store.moveUp(promptRow.index)
        }
        Ui.PanelActionButton {
          id: removeButton
          anchors.verticalCenter: field.verticalCenter
          iconText: "󰆴"
          tooltipText: "Remove"
          foreground: view.foreground
          fontFamily: view.fontFamily
          onClicked: view.store.forget(promptRow.modelData)
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(4)

      Ui.TextField {
        id: newPrompt
        width: parent.width - addButton.width - parent.spacing
        placeholderText: "New prompt…"
        foreground: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: {
          view.store.add(text)
          text = ""
          Qt.callLater(function() { promptList.positionViewAtEnd() })
        }
      }
      Ui.PanelActionButton {
        id: addButton
        anchors.verticalCenter: newPrompt.verticalCenter
        iconText: "󰐕"
        tooltipText: "Add prompt"
        foreground: view.foreground
        fontFamily: view.fontFamily
        onClicked: newPrompt.accepted()
      }
    }

    Label { text: "Prompts you run move to the top. Edit one and press Enter to save; clear it to remove it." }
  }

  // ── Bar ────────────────────────────────────────────────────────────

  Item {
    width: parent.width
    implicitHeight: Math.max(barLabel.implicitHeight, barToggle.implicitHeight)
    visible: view.page === "main"

    Text {
      id: barLabel
      anchors.left: parent.left
      anchors.right: barToggle.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Show in bar"
      color: view.foreground
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }
    Ui.ToggleSwitch {
      id: barToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      foreground: view.foreground
      checked: view.store.showInBar
      onToggled: view.store.set("showInBar", !view.store.showInBar)
    }
  }
  Label {
    visible: view.page === "main" && !view.store.showInBar
    text: "Hidden from the bar. Open these settings from the overlay (Super+Alt+V, then Ctrl+S)."
  }

  NavRow {
    visible: view.page === "main"
    title: "Advanced"
    detail: view.advancedSummary
    onClicked: view.page = "advanced"
  }
}
