import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

// Fixture for report cmus3invr006gcdw4hm3h94a5 (omacom/omarchy#14125): observes the REAL lock plugin
// sources of this tree and writes {observed[], asReported, summary} (or {setup})
// to $OMARCHY_QML_TEST_RESULT for test/reports/report-cmus3invr006gcdw4hm3h94a5.sh.
ShellRoot {
  id: root

  readonly property string rootPath: Quickshell.env("OMARCHY_PATH")
  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property var observed: []
  property bool written: false

  Item { id: host; width: 1280; height: 800 }

  function note(text) { observed.push(String(text)) }

  function finish(asReported, summary) {
    if (written) return
    written = true
    write({ observed: observed, asReported: !!asReported, summary: String(summary) })
  }

  function setupFailed(message) {
    if (written) return
    written = true
    write({ setup: String(message), observed: observed })
  }

  function write(payload) {
    var quoted = "'" + JSON.stringify(payload).replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["bash", "-c", "printf '%s' " + quoted + " > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"", "_", root.resultPath])
  }

  function load(file, props) {
    var component = Qt.createComponent("file://" + rootPath + "/shell/plugins/lock/" + file, Component.PreferSynchronous)
    if (component.status !== Component.Ready) throw new Error("SETUP " + file + " failed to load: " + component.errorString())
    var object = component.createObject(host, props || {})
    if (!object) throw new Error("SETUP " + file + " failed to instantiate: " + component.errorString())
    return object
  }

  // Every descendant item, depth first.
  function descendants(item, out) {
    out = out || []
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { out.push(kids[i]); descendants(kids[i], out) }
    return out
  }

  function passwordField(view) {
    var all = descendants(view)
    for (var i = 0; i < all.length; i++) if (all[i].echoMode === TextInput.Password) return all[i]
    throw new Error("SETUP no password TextInput in LockView")
  }

  // Text items the user can see: visible, non-empty, with no hidden ancestor.
  function visibleTexts(view) {
    var out = []
    var all = descendants(view)
    for (var i = 0; i < all.length; i++) {
      var t = all[i]
      if (t.textFormat === undefined || t.echoMode !== undefined) continue
      if (!t.visible || t.opacity === 0 || String(t.text || "").length === 0) continue
      out.push(String(t.text))
    }
    return out
  }

  function serviceObject(service, predicate, what) {
    var objects = service.data || []
    for (var i = 0; i < objects.length; i++) if (predicate(objects[i])) return objects[i]
    throw new Error("SETUP Service.qml has no " + what)
  }

  function guarded(fn) {
    try { fn() } catch (error) {
      var m = String(error && error.message ? error.message : error)
      if (m.indexOf("SETUP ") === 0) setupFailed(m.slice(6))
      else setupFailed("fixture error: " + m)
    }
  }

  // #14125: after one wrong password the field shows only the failure message.
  // The view gets exactly what Service.qml hands it after handlePasswordFailure():
  // failureMessage "Authentication failed (1)", failedAttempts 1, an empty field,
  // input enabled, no check in flight.
  Timer {
    interval: 1; running: true
    onTriggered: root.guarded(function() {
      var view = root.load("LockView.qml", { width: 1280, height: 800, loadBackground: false, fingerprintConfigured: false })
      var input = root.passwordField(view)
      var before = root.visibleTexts(view)
      root.note("before a failure, the field shows " + JSON.stringify(before) + " (placeholderText " + JSON.stringify(view.placeholderText) + ")")
      view.failureMessage = "Authentication failed (1)"
      view.failedAttempts = 1
      view.passwordText = ""
      var after = root.visibleTexts(view)
      var showsMessage = after.indexOf("Authentication failed (1)") >= 0
      var showsPrompt = after.indexOf(view.placeholderText) >= 0
      root.note("after one failed attempt (empty field), the visible text is " + JSON.stringify(after))
      root.note("the placeholder " + JSON.stringify(view.placeholderText) + (showsPrompt ? " is shown" : " is not shown"))
      root.note("the field border uses the error colour: errorState=" + view.errorState + "; text cursor shown: " + input.cursorVisible + " (showPasswordCursor=" + view.showPasswordCursor + ")")
      root.note("the field still takes input: enabled=" + input.enabled + ", readOnly=" + input.readOnly)
      var cleared = false
      view.clearFailureRequested.connect(function() { cleared = true; view.failureMessage = "" })
      input.text = "a"
      root.note("the first typed character " + (cleared ? "clears the failure message (clearFailureRequested)" : "does not clear the failure message") + "; visible text then " + JSON.stringify(root.visibleTexts(view)))
      var asReported = showsMessage && !showsPrompt && input.enabled && !input.readOnly
      root.finish(asReported, asReported
        ? "after a failed attempt the empty field shows only the failure message (no placeholder, no cursor) while the field still accepts typing"
        : "after a failed attempt the field shows " + JSON.stringify(after))
    })
  }
}
