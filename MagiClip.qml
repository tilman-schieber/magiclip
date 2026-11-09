import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Overlay for bin/magiclip. Type to filter the saved prompts or type a new
// one; Enter sends the clipboard text to Claude with it.
//
// In "review" mode the answer is shown here first (Enter copies it and pastes
// it into the focused window, Shift+Enter only copies it); in "silent" mode
// the overlay closes and the runner replaces the clipboard on its own.
// Ctrl+S switches to the settings (the same ones as the bar widget).
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string runner: root.pluginDir + "/bin/magiclip"
  readonly property int previewLimit: 4000

  property bool opened: false
  property string view: "pick"          // pick | running | result | settings
  property string clipboardText: ""
  property bool clipboardLoading: false
  property int selectedIndex: 0

  // The local switch: start from the default backend, Ctrl+L flips it.
  property bool useLocal: false
  property bool runLocal: false

  property string runPrompt: ""
  property string resultText: ""
  property string errorText: ""
  property string warningText: ""

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Style.font.caption + Style.space(8)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.title + Style.spacing.rowPaddingX * 2)

  readonly property string query: input.text.trim()
  readonly property bool hasClipboard: root.clipboardText.trim().length > 0

  Store { id: store }

  // ── Shell entry points ──────────────────────────────────────────────

  function open(payloadJson) {
    input.text = ""
    root.selectedIndex = 0
    root.clipboardText = ""
    root.clipboardLoading = true
    clipboardProc.running = false
    clipboardProc.running = true
    root.view = "pick"
    root.useLocal = store.backend === "local"
    store.discoverLocal()
    root.rebuild()
    root.opened = true
    Qt.callLater(root.focusView)
  }

  function close() {
    runProc.running = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function show(viewName) {
    if (viewName === "settings") settingsView.page = "main"
    root.view = viewName
    Qt.callLater(root.focusView)
  }

  function focusView() {
    if (root.view === "pick") input.forceActiveFocus()
    else if (root.view === "settings") settingsKeys.forceActiveFocus()
    else resultKeys.forceActiveFocus()
  }

  // ── Prompt list ─────────────────────────────────────────────────────

  // Saved prompts matching every word typed, then (when the typed text is not
  // already a saved prompt) a row that uses the typed text as a new prompt.
  function rebuild() {
    var words = root.query.toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 })
    var exact = false
    promptModel.clear()
    for (var i = 0; i < store.prompts.length; i++) {
      var p = store.prompts[i]
      var lower = p.toLowerCase()
      if (p.trim() === root.query) exact = true
      var ok = true
      for (var j = 0; j < words.length && ok; j++) ok = lower.indexOf(words[j]) !== -1
      if (ok) promptModel.append({ promptText: p, isNew: false })
    }
    if (root.query.length > 0 && !exact) promptModel.append({ promptText: root.query, isNew: true })

    if (promptModel.count === 0) root.selectedIndex = 0
    else root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, promptModel.count - 1))
    Qt.callLater(function() {
      if (promptModel.count > 0) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function move(delta) {
    if (promptModel.count === 0) return
    root.selectedIndex = (root.selectedIndex + delta + promptModel.count) % promptModel.count
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  Connections {
    target: store
    function onPromptsChanged() { if (root.opened && root.view === "pick") root.rebuild() }
  }

  // ── Running ─────────────────────────────────────────────────────────

  function run(promptText) {
    promptText = String(promptText || "").trim()
    if (!promptText || !root.hasClipboard) return
    store.remember(promptText)

    var backendFlag = root.useLocal ? "--local" : "--cloud"
    if (store.mode === "silent") {
      root.close()
      Quickshell.execDetached([root.runner, backendFlag, promptText])
      return
    }

    root.runPrompt = promptText
    root.resultText = ""
    root.errorText = ""
    root.warningText = ""
    runProc.running = false
    runProc.stdoutDone = false
    runProc.stderrDone = false
    runProc.exitCode = -1
    root.runLocal = root.useLocal
    runProc.command = [root.runner, "--print", backendFlag, promptText]
    runProc.running = true
    root.show("running")
  }

  function runSelected() {
    if (promptModel.count === 0) return
    root.run(promptModel.get(root.selectedIndex).promptText)
  }

  function finishRun() {
    if (!runProc.stdoutDone || !runProc.stderrDone || runProc.exitCode < 0) return
    if (!root.opened || root.view !== "running") return
    var out = runStdout.text
    var err = runStderr.text.trim()
    if (runProc.exitCode === 0 && out.trim().length > 0) {
      root.resultText = out
      root.warningText = err
    } else {
      root.errorText = err || "magiclip exited with code " + runProc.exitCode + "."
    }
    root.show("result")
  }

  function retry() {
    if (root.runPrompt) root.run(root.runPrompt)
  }

  // Enter: copy, then paste into the window that had focus before the overlay
  // (Shift+Insert works in terminals and GUI apps). Shift+Enter: copy only.
  function useResult(paste) {
    if (!root.resultText) return
    var text = root.resultText
    root.close()
    var script = 'printf %s "$1" | wl-copy --type text/plain'
    if (paste) script += ' && sleep 0.15 && wtype -M shift -k Insert -m shift'
    Quickshell.execDetached(["sh", "-c", script, "sh", text])
  }

  ListModel { id: promptModel }

  Process {
    id: clipboardProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.clipboardText = text
        root.clipboardLoading = false
      }
    }
    onExited: function(code) {
      if (code !== 0) root.clipboardLoading = false
    }
  }

  Process {
    id: runProc
    property bool stdoutDone: false
    property bool stderrDone: false
    property int exitCode: -1
    stdout: StdioCollector {
      id: runStdout
      waitForEnd: true
      onStreamFinished: { runProc.stdoutDone = true; root.finishRun() }
    }
    stderr: StdioCollector {
      id: runStderr
      waitForEnd: true
      onStreamFinished: { runProc.stderrDone = true; root.finishRun() }
    }
    onExited: function(code) {
      runProc.exitCode = code
      root.finishRun()
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────

  component Hint: Text {
    width: parent ? parent.width : 0
    height: root.footerHeight
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.5
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "magiclip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.focusView() }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ── Pick a prompt ──────────────────────────────────────────

        Column {
          anchors.fill: parent
          spacing: root.contentSpacing
          visible: root.view === "pick"

          Item {
            width: parent.width
            height: root.headerHeight

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: input.text.length === 0
              text: "Pick a prompt or type a new one…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            TextInput {
              id: input
              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              selectionColor: root.selectedBackground
              selectedTextColor: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              clip: true
              focus: true

              onTextChanged: {
                root.selectedIndex = 0
                root.rebuild()
              }

              Keys.onPressed: function(event) {
                var ctrl = event.modifiers & Qt.ControlModifier
                if (event.key === Qt.Key_Escape) {
                  if (input.text.length > 0) input.text = ""
                  else root.close()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  // Ctrl+Enter: use the typed text as is, even if a saved prompt matches.
                  if (ctrl && root.query.length > 0) root.run(root.query)
                  else root.runSelected()
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                  root.move(-1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                  root.move(1)
                  event.accepted = true
                } else if (event.key === Qt.Key_Tab) {
                  // Tab: copy the selected prompt into the field to edit it.
                  if (promptModel.count > 0) input.text = promptModel.get(root.selectedIndex).promptText
                  event.accepted = true
                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                  if (promptModel.count > 0 && !promptModel.get(root.selectedIndex).isNew)
                    store.forget(promptModel.get(root.selectedIndex).promptText)
                  event.accepted = true
                } else if (ctrl && event.key === Qt.Key_S) {
                  root.show("settings")
                  event.accepted = true
                } else if (ctrl && event.key === Qt.Key_L) {
                  root.useLocal = !root.useLocal
                  event.accepted = true
                }
              }
            }
          }

          Item {
            width: parent.width
            height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

            Row {
              anchors.fill: parent

              ListView {
                id: list
                width: parent.width / 2
                height: parent.height
                model: promptModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string promptText
                  required property bool isNew
                  readonly property bool current: index === root.selectedIndex

                  width: ListView.view.width - root.contentMargin
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: current ? root.selectedBackground : "transparent"

                  Text {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    text: row.isNew ? "+  " + row.promptText : row.promptText
                    color: row.current ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.italic: row.isNew
                    elide: Text.ElideRight
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = row.index
                    onClicked: root.run(row.promptText)
                  }
                }
              }

              Item {
                width: parent.width / 2
                height: parent.height
                clip: true

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Style.normalBorderWidth
                  color: Util.alpha(root.border, 0.28)
                }

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: root.contentMargin
                  textFormat: Text.PlainText
                  text: root.clipboardLoading ? ""
                    : root.hasClipboard ? root.clipboardText.slice(0, root.previewLimit)
                    : "The clipboard has no text. Copy something first."
                  color: root.foreground
                  opacity: root.hasClipboard ? 0.85 : 0.58
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignTop
                }
              }
            }
          }

          Hint {
            text: "⏎ run   ⌃⏎ run typed text   ⇥ edit   ⇧⌦ forget   ⌃L local/cloud   ⌃S settings   esc close"
              + "   ·   " + (root.useLocal ? "󰟀 " : "") + store.backendLabel(root.useLocal)
              + (store.mode === "silent" ? " · silent" : "")
          }
        }

        // ── Running / result ───────────────────────────────────────

        Item {
          id: resultKeys
          anchors.fill: parent
          visible: root.view === "running" || root.view === "result"

          Keys.onPressed: function(event) {
            var ctrl = event.modifiers & Qt.ControlModifier
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
              runProc.running = false
              root.show("pick")
              event.accepted = true
            } else if (ctrl && event.key === Qt.Key_R) {
              root.retry()
              event.accepted = true
            } else if (ctrl && event.key === Qt.Key_L) {
              root.useLocal = !root.runLocal
              root.retry()
              event.accepted = true
            } else if (root.view === "result" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
              root.useResult(!(event.modifiers & Qt.ShiftModifier))
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
              resultFlick.contentY = Math.max(0, Math.min(resultFlick.contentHeight - resultFlick.height,
                resultFlick.contentY + (event.key === Qt.Key_Up ? -1 : 1) * Style.space(40)))
              event.accepted = true
            }
          }

          Column {
            anchors.fill: parent
            spacing: root.contentSpacing

            Text {
              width: parent.width
              height: root.headerHeight
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: root.runPrompt
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Flickable {
              id: resultFlick
              width: parent.width
              height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2
              contentWidth: width
              contentHeight: resultBody.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              TextEdit {
                id: resultBody
                width: resultFlick.width
                readOnly: true
                selectByMouse: true
                activeFocusOnPress: false
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                text: root.view === "running" ? "Asking " + store.backendLabel(root.runLocal) + "…"
                  : root.errorText ? root.errorText
                  : root.resultText
                color: root.foreground
                opacity: root.view === "running" ? 0.58 : 1
                selectionColor: root.selectedBackground
                selectedTextColor: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }

            Hint {
              text: root.view === "running" ? "⌫ back   esc cancel"
                : root.errorText ? "⌃R retry   ⌃L ask " + (root.runLocal ? "Claude" : "local") + "   ⌫ back   esc close"
                : (root.warningText ? root.warningText + "   ·   " : "")
                  + "⏎ paste   ⇧⏎ copy only   ⌃R retry   ⌃L ask " + (root.runLocal ? "Claude" : "local")
                  + "   ⌫ back   esc discard   ·   " + store.backendLabel(root.runLocal)
            }
          }
        }

        // ── Settings ───────────────────────────────────────────────

        Item {
          id: settingsKeys
          anchors.fill: parent
          visible: root.view === "settings"

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape && settingsView.page === "advanced") {
              settingsView.page = "main"
              event.accepted = true
            } else if (event.key === Qt.Key_Escape
                || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S)) {
              root.show("pick")
              event.accepted = true
            }
          }

          Column {
            anchors.fill: parent
            spacing: root.contentSpacing

            Flickable {
              width: parent.width
              height: parent.height - root.footerHeight - root.contentSpacing
              contentWidth: width
              contentHeight: settingsView.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              SettingsView {
                id: settingsView
                width: parent.width
                store: store
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            Hint { text: "esc / ⌃S back to prompts" }
          }
        }
      }
    }
  }
}
