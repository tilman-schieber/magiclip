import QtQuick
import Quickshell
import Quickshell.Io

// Settings and the prompt list, shared by the overlay, the bar widget and
// bin/magiclip through two files:
//
//   ~/.config/magiclip/config.json        { model, effort, mode, showInBar }
//   ~/.local/state/magiclip/prompts.json  [ "prompt", ... ] most recent first
//
// Every instance (overlay, one bar widget per monitor) watches both files, so
// a change made in one shows up in the others.
Item {
  id: store
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: store.home + "/.config/magiclip"
  readonly property string stateDir: store.home + "/.local/state/magiclip"

  readonly property var defaultPrompts: [
    "Fix spelling and grammar. Keep the meaning, tone and language.",
    "Rewrite to be shorter and clearer.",
    "Summarize in a few bullet points.",
    "Translate to English.",
    "Translate to German.",
    "Make it more formal and polite.",
    "Make it more casual and friendly.",
    "Write a reply to this message.",
    "Extract the action items as a checklist.",
    "Explain what this code does.",
    "Convert to Markdown."
  ]
  readonly property var defaultConfig: ({
    model: "claude-sonnet-5-5",
    effort: "low",
    mode: "review",
    showInBar: true
  })

  readonly property var modelOptions: [
    { value: "claude-haiku-5-5", label: "Claude Haiku 5.5 · fastest, cheapest" },
    { value: "claude-sonnet-5-5", label: "Claude Sonnet 5.5 · balanced" },
    { value: "claude-opus-5-5", label: "Claude Opus 5.5 · smarter, slower" },
    { value: "claude-fable-5-1", label: "Claude Fable 5.1 · most capable, expensive" }
  ]
  readonly property var effortOptions: [
    { value: "low", label: "Low" },
    { value: "medium", label: "Medium" },
    { value: "high", label: "High" }
  ]
  readonly property var modeOptions: [
    { value: "review", label: "Show result" },
    { value: "silent", label: "Replace silently" }
  ]

  readonly property int promptLimit: 100

  property var config: store.defaultConfig
  property var prompts: []
  property bool ready: false

  readonly property string model: String(store.config.model || store.defaultConfig.model)
  readonly property string effort: String(store.config.effort || store.defaultConfig.effort)
  readonly property string mode: store.config.mode === "silent" ? "silent" : "review"
  readonly property bool showInBar: store.config.showInBar !== false

  // ── Local backend (Ollama) ──────────────────────────────────────────

  readonly property string backend: store.config.backend === "local" ? "local" : "claude"
  readonly property string localUrl: String(store.config.localUrl || "http://localhost:11434").replace(/\/+$/, "")
  // Empty means "the first installed model", like the runner does.
  readonly property string localModelSetting: typeof store.config.localModel === "string" ? store.config.localModel : ""
  readonly property string localModel: store.localModelSetting
    || (store.localModels.length > 0 ? store.localModels[0] : "")

  property var localModels: []
  property string localStatus: "unknown"   // unknown | checking | ok | empty | offline

  function backendLabel(useLocal) {
    return useLocal ? (store.localModel ? store.localModel + " (local)" : "local model")
                    : store.modelLabel(store.model)
  }

  function discoverLocal() {
    if (discoverProc.running) return
    store.localStatus = "checking"
    discoverProc.command = ["curl", "-sS", "--max-time", "3", store.localUrl + "/api/tags"]
    discoverProc.running = true
  }

  function readLocal(raw) {
    var names = []
    try {
      var models = JSON.parse(raw).models || []
      for (var i = 0; i < models.length; i++) if (models[i].name) names.push(String(models[i].name))
    } catch (e) {
      store.localModels = []
      store.localStatus = "offline"
      return
    }
    names.sort()
    store.localModels = names
    store.localStatus = names.length > 0 ? "ok" : "empty"
  }
  readonly property string instructions: typeof store.config.instructions === "string" ? store.config.instructions : ""

  function modelLabel(id) {
    for (var i = 0; i < store.modelOptions.length; i++)
      if (store.modelOptions[i].value === id) return store.modelOptions[i].label.split(" · ")[0]
    return id
  }

  // ── Config ──────────────────────────────────────────────────────────

  function loadConfig(raw) {
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    var next = Object.assign({}, store.defaultConfig)
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
      for (var k in parsed) next[k] = parsed[k]
    store.config = next
  }

  function set(key, value) {
    var next = Object.assign({}, store.config)
    next[key] = value
    store.config = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // ── Prompts ─────────────────────────────────────────────────────────

  function loadPrompts(raw) {
    var list = null
    try { list = JSON.parse(raw) } catch (e) { list = null }
    if (!Array.isArray(list)) {
      store.setPrompts(store.defaultPrompts.slice())
      return
    }
    store.prompts = list.filter(function(p) { return typeof p === "string" && p.trim().length > 0 })
  }

  function setPrompts(list) {
    var seen = ({})
    var clean = []
    for (var i = 0; i < list.length; i++) {
      var p = String(list[i] || "").trim()
      if (!p || seen[p]) continue
      seen[p] = true
      clean.push(p)
    }
    store.prompts = clean.slice(0, store.promptLimit)
    promptsFile.setText(JSON.stringify(store.prompts, null, 2) + "\n")
  }

  // Most recently used first; a prompt used again moves back to the top.
  function remember(promptText) {
    var rest = store.prompts.filter(function(p) { return p !== promptText })
    store.setPrompts([promptText].concat(rest))
  }

  function forget(promptText) {
    store.setPrompts(store.prompts.filter(function(p) { return p !== promptText }))
  }

  function add(promptText) {
    if (!String(promptText || "").trim()) return
    store.setPrompts(store.prompts.concat([promptText]))
  }

  function edit(index, promptText) {
    if (index < 0 || index >= store.prompts.length) return
    var next = store.prompts.slice()
    if (String(promptText || "").trim()) next[index] = promptText
    else next.splice(index, 1)
    store.setPrompts(next)
  }

  function moveUp(index) {
    if (index <= 0 || index >= store.prompts.length) return
    var next = store.prompts.slice()
    var p = next[index]
    next[index] = next[index - 1]
    next[index - 1] = p
    store.setPrompts(next)
  }

  function resetPrompts() {
    store.setPrompts(store.defaultPrompts.slice())
  }

  // ── Files ───────────────────────────────────────────────────────────

  Component.onCompleted: mkdirProc.running = true

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", store.configDir, store.stateDir]
    onExited: {
      configFile.path = store.configDir + "/config.json"
      promptsFile.path = store.stateDir + "/prompts.json"
      store.ready = true
    }
  }

  Process {
    id: discoverProc
    // A failed curl leaves stdout empty, which readLocal treats as offline.
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: store.readLocal(text)
    }
  }

  FileView {
    id: configFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: store.loadConfig(text())
    onLoadFailed: store.loadConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: promptsFile
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: store.loadPrompts(text())
    onLoadFailed: store.loadPrompts("")
    onFileChanged: reload()
  }
}
