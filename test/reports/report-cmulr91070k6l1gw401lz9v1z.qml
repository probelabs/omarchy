import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

// Fixture for report cmulr91070k6l1gw401lz9v1z (omacom/omarchy#10078): observes the REAL lock plugin
// sources of this tree and writes {observed[], asReported, summary} (or {setup})
// to $OMARCHY_QML_TEST_RESULT for test/reports/report-cmulr91070k6l1gw401lz9v1z.sh.
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

  // #10078: the password field sets no length limit of its own. A value pasted
  // or typed into the field goes as-is into the service signal (and from there,
  // per Service.qml submitPassword, into pendingPassword and PAM).
  Timer {
    interval: 1; running: true
    onTriggered: root.guarded(function() {
      var view = root.load("LockView.qml", { width: 1280, height: 800, loadBackground: false })
      var input = root.passwordField(view)
      var reported = -1
      view.passwordTextEdited.connect(function(p) { reported = p.length; view.passwordText = p })
      var qtDefault = 32767
      root.note("the password TextInput's maximumLength is " + input.maximumLength + (input.maximumLength === qtDefault ? " (Qt's built-in default; LockView.qml sets none)" : " (set by LockView.qml)"))
      var sizes = [513, 4096, 100000]
      var accepted = []
      for (var i = 0; i < sizes.length; i++) {
        input.text = ""
        input.insert(0, "a".repeat(sizes[i]))
        accepted.push(input.text.length)
        root.note("inserting " + sizes[i] + " characters leaves " + input.text.length + " in the field; passwordTextEdited reports " + reported + " characters; the masking TextMetrics measures " + (view.passwordText.length) + " dots")
      }
      var asReported = input.maximumLength === qtDefault && accepted[0] === 513 && accepted[1] === 4096
      root.finish(asReported, asReported
        ? "the lock field applies no limit of its own: it takes up to Qt's default 32767 characters and reports them all to the service"
        : "the lock field limits input to " + input.maximumLength + " characters")
    })
  }
}
