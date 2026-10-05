import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.Commons

// Fixture for report cmulr8v3s0je91gw4wt4k3bat (omacom/omarchy#11411): observes the REAL lock plugin
// sources of this tree and writes {observed[], asReported, summary} (or {setup})
// to $OMARCHY_QML_TEST_RESULT for test/reports/report-cmulr8v3s0je91gw4wt4k3bat.sh.
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

  // #11411: the idle blank countdown is frozen by suspend and fires right after
  // resume. Service.qml's wall-clock guard re-arms it, so the woken lock screen
  // blanks one interval later. A resume 5-7 s after arming takes neither branch
  // and blanks at once. The fixture drives the REAL idleBlankTimer of Service.qml:
  // it back-dates armedAt (what the frozen countdown sees after a suspend) and
  // fires the timer, then watches displaysBlank (set by runBlank()).
  property var service: null
  property var blankTimer: null
  property double firedAt: 0
  property bool firstCaseBlankedAtFire: false

  Timer {
    interval: 1; running: true
    onTriggered: root.guarded(function() {
      root.service = root.load("Service.qml", { omarchyPath: root.rootPath })
      root.blankTimer = root.serviceObject(root.service, function(o) { return o.interval === 5000 && o.repeat === false && o.armedAt !== undefined }, "idle blank timer (interval 5000, armedAt)")
      root.service.lockRequested = true
      root.service.displaysBlank = false
      root.note("idleBlankTimer interval " + root.blankTimer.interval + " ms; the session is locked, no password check in flight")
      // Resume after a long suspend: the countdown was armed 20 s of wall-clock time ago.
      root.blankTimer.stop()
      root.blankTimer.armedAt = Date.now() - 20000
      root.firedAt = Date.now()
      root.blankTimer.triggered()
      root.firstCaseBlankedAtFire = root.service.displaysBlank
      root.note("resume 20 s after arming: at the frozen timer's fire the displays " + (root.service.displaysBlank ? "blank" : "stay lit") + "; the timer is " + (root.blankTimer.running ? "re-armed for another " + root.blankTimer.interval + " ms" : "stopped"))
      watch.start()
    })
  }

  // Poll after the resume-time fire: when does displaysBlank flip?
  Timer {
    id: watch
    interval: 100; repeat: true
    property double blankedAt: 0
    onTriggered: root.guarded(function() {
      var elapsed = Date.now() - root.firedAt
      if (root.service.displaysBlank && blankedAt === 0) blankedAt = Date.now()
      if (blankedAt === 0 && elapsed < 9000) return
      stop()
      var afterMs = blankedAt > 0 ? blankedAt - root.firedAt : -1
      root.note(blankedAt > 0
        ? "with no input after that, the displays blank " + (Math.round(afterMs / 100) / 10) + " s after the resume-time fire"
        : "with no input, the displays are still lit 9 s after the resume-time fire")
      // Dead zone: resume 6 s after arming (between interval and interval + 2000 ms).
      root.service.displaysBlank = false
      root.blankTimer.stop()
      root.blankTimer.armedAt = Date.now() - 6000
      root.blankTimer.triggered()
      var deadZone = root.service.displaysBlank
      root.note("resume 6 s after arming (between the 5 s interval and the 7 s guard): the displays " + (deadZone ? "blank at the fire itself" : "stay lit at the fire"))
      root.service.lockRequested = false
      var asReported = !root.firstCaseBlankedAtFire && blankedAt > 0 && afterMs >= 4500 && afterMs <= 6500
      root.finish(asReported, asReported
        ? "after a resume the lock screen blanks about 5 s later with no input (the suspend-gap guard re-arms the countdown)" + (deadZone ? "; a resume 5-7 s after arming blanks at once" : "")
        : "after a resume the lock screen does not blank about 5 s later (blank at " + afterMs + " ms)")
    })
  }
}
