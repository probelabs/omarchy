import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

// Fixture for report cmupntnla003f49w4drywtcgj (omacom/omarchy#13954): observes the REAL lock plugin
// sources of this tree and writes {observed[], asReported, summary} (or {setup})
// to $OMARCHY_QML_TEST_RESULT for test/reports/report-cmupntnla003f49w4drywtcgj.sh.
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

  // #13954: the fingerprint PAM stack's messages ("Remove your finger, and try
  // touching the sensor again") never reach the lock screen. The harness runs
  // quickshell in a private mount namespace whose /etc/pam.d holds an
  // omarchy-lock-fingerprint stack that sends that exact message (pam_echo) and
  // then fails (pam_deny) - no reader needed. The fixture starts the REAL
  // fingerprintPam of Service.qml (directly: startFingerprint() also waits for a
  // secured session lock, which a headless fixture does not take) and checks
  // where the message goes.
  readonly property string expectedMessage: "Remove your finger, and try touching the sensor again"
  property var service: null
  property var fpPam: null
  property var seen: []
  property bool done: false

  function stringProps(obj) {
    var out = []
    for (var k in obj) {
      var v
      try { v = obj[k] } catch (e) { continue }
      if (typeof v === "string") out.push([k, v])
    }
    return out
  }

  function conclude() {
    if (done) return
    done = true
    root.guarded(function() {
      var delivered = root.seen.filter(function(s) { return s.text === root.expectedMessage })
      root.note("the fingerprint PamContext relayed " + root.seen.length + " message(s): " + JSON.stringify(root.seen))
      var holders = root.stringProps(root.service).filter(function(p) { return p[1].indexOf(root.expectedMessage) >= 0 }).map(function(p) { return p[0] })
      root.note("Service.qml string properties holding the message after the attempt: " + JSON.stringify(holders) + "; failureMessage=" + JSON.stringify(root.service.failureMessage))
      var view = root.load("LockView.qml", { width: 1280, height: 800, loadBackground: false, fingerprintConfigured: true })
      var inputs = []
      for (var k in view) if (/message|hint|status/i.test(k) && typeof view[k] === "string") inputs.push(k)
      root.note("LockView.qml string inputs that could carry a message: " + JSON.stringify(inputs) + " (failureMessage is set only by handlePasswordFailure)")
      root.note("LockView with fingerprint configured shows " + JSON.stringify(root.visibleTexts(view)) + " (the indicator glyph and the password placeholder)")
      if (delivered.length === 0) { root.setupFailed("the private PAM stack did not deliver the test message (" + JSON.stringify(root.seen) + ")"); return }
      var asReported = holders.length === 0 && inputs.indexOf("fingerprintMessage") < 0 && root.service.failureMessage === ""
      root.finish(asReported, asReported
        ? "a fingerprint PAM message is relayed to the lock service, which keeps nothing of it; the lock view has no element that could show it"
        : "the fingerprint PAM message is kept in " + JSON.stringify(holders))
    })
  }

  Timer {
    interval: 1; running: true
    onTriggered: root.guarded(function() {
      root.service = root.load("Service.qml", { omarchyPath: root.rootPath })
      root.fpPam = root.serviceObject(root.service, function(o) { return o.config === "omarchy-lock-fingerprint" }, "fingerprint PamContext")
      root.fpPam.pamMessage.connect(function() { root.seen.push({ text: String(root.fpPam.message), error: !!root.fpPam.messageIsError }) })
      root.fpPam.completed.connect(function(result) { settle.start() })
      root.service.lockRequested = true
      root.service.fingerprintConfigured = true
      root.service.fingerprintAuthenticating = true
      if (!root.fpPam.start()) { root.setupFailed("fingerprintPam.start() failed in the private PAM namespace"); return }
      giveUp.start()
    })
  }
  Timer { id: settle; interval: 300; onTriggered: root.conclude() }
  Timer { id: giveUp; interval: 15000; onTriggered: root.conclude() }
}
