import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

// Fixture for report cmulr91vo0k9f1gw499ic4jis (omacom/omarchy#9913): observes the REAL lock plugin
// sources of this tree and writes {observed[], asReported, summary} (or {setup})
// to $OMARCHY_QML_TEST_RESULT for test/reports/report-cmulr91vo0k9f1gw499ic4jis.sh.
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

  // Fingerprint retry policy of the REAL Service.qml at this commit (after
  // upstream #7158): what happens after an attempt ends without a match, after
  // attempts that never reach the reader, and while the displays are blank.
  // Attempts are settled through the service's own handlers
  // (handleFingerprintFinished / settleFingerprintAttempt) with the attempt
  // flags a real PAM conversation would have set; the next scan is the
  // fingerprintRetryTimer (startFingerprint() also waits for a secured session
  // lock, which a headless fixture does not take, so the fixture reads the timer).
  Timer {
    interval: 1; running: true
    onTriggered: root.guarded(function() {
      var s = root.load("Service.qml", { omarchyPath: root.rootPath })
      var retry = root.serviceObject(s, function(o) { return o.interval === 250 && o.repeat === false && o.armedAt === undefined }, "fingerprint retry timer (250 ms)")
      s.lockRequested = true
      s.fingerprintConfigured = true

      function miss(reached, result) {
        s.fingerprintAuthenticating = true
        s.fingerprintAttemptReachedDevice = reached
        s.fingerprintAttemptPromptedAtMs = reached ? Date.now() - 31000 : 0
        s.handleFingerprintFinished(result)
      }

      // 1. One attempt that reached the reader and ended without a match.
      miss(true, PamResult.Failed)
      var afterMiss = retry.running ? retry.interval : -1
      root.note("after one attempt that reached the reader and did not match: the next attempt is " + (afterMiss > 0 ? "armed in " + afterMiss + " ms" : "not armed"))

      // 2. The same while the displays are blank (runBlank(), as the idle blank timer calls it).
      s.runBlank()
      var retryKeptByBlank = retry.running
      miss(true, PamResult.Failed)
      var whileBlank = retry.running ? retry.interval : -1
      root.note("runBlank() " + (retryKeptByBlank ? "leaves the pending retry running" : "stops the pending retry") + "; with displaysBlank=" + s.displaysBlank + " a miss arms the next attempt " + (whileBlank > 0 ? "in " + whileBlank + " ms" : "never"))

      // 3. Attempts that never reach the reader (device refusing / errors) in a row.
      s.displaysBlank = false
      var waits = []
      for (var i = 0; i < 9; i++) { miss(false, PamResult.Error); waits.push(retry.running ? retry.interval : -1) }
      root.note("9 unreached/error attempts in a row arm the next attempt after " + JSON.stringify(waits) + " ms (unavailable notice: " + s.fingerprintUnavailable + ")")
      root.note("after them the retry is " + (retry.running ? "still armed" : "stopped") + " and the lock is still requested (" + s.lockRequested + "): retries go on while the session stays locked")

      s.lockRequested = false
      s.resetAuthenticationState()
      var asReported = afterMiss > 0 && whileBlank > 0 && retryKeptByBlank
      root.finish(asReported, asReported
        ? "the lock re-arms the fingerprint scan after every miss, also while the displays are blank (250 ms after a miss; error streaks back off to a 40 s cap), for as long as the session is locked"
        : "the lock does not re-arm the fingerprint scan while the displays are blank")
    })
  }
}
