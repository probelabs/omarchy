import QtQuick
import Quickshell
import Quickshell.Services.Pam
import "plugins/lock" as LockPlugin

// MC/DC fixture driver (phase B, zero compositor outputs, no USER). The
// placeholder screen (empty name, zero extents) covers the no-real-screen
// arms, and the absent PAM fixture covers the fingerprint start-failure and
// the lock IPC failed arms.
Item {
  id: root

  width: 800
  height: 600

  property var ipc: null

  LockPlugin.LockView { id: lockView }
  LockPlugin.Service { id: service; shell: null }

  property int phase: 0

  function findChild(obj, probe) {
    if (!obj) return null
    var pools = [obj.data || [], obj.resources || [], obj.children || []]
    for (var p = 0; p < pools.length; p++) {
      var kids = pools[p]
      for (var i = 0; i < kids.length; i++) {
        if (probe(kids[i])) return kids[i]
        var found = findChild(kids[i], probe)
        if (found) return found
      }
    }
    return null
  }

  Timer {
    id: runner
    interval: 400
    repeat: true
    running: true
    onTriggered: root.tick()
  }

  function tick() {
    phase += 1
    try {
      if (phase === 1) {
        if (Quickshell.env("USER") !== "") throw "phase B expects USER unset"
        if (service.realScreenCount() !== 0) throw "phase B expects no real screens"
        if (service.hasRealScreen()) throw "hasRealScreen should be false"
        var placeholder = (Quickshell.screens || [])[0]
        if (!placeholder || placeholder.width !== 0 || placeholder.name !== "") {
          throw "phase B expects the placeholder screen, got " + JSON.stringify(placeholder)
        }
        service.lockRequested = true
        service.requestSessionLock()
        if (!service.pendingSessionLock) throw "no-real-screen path should set pendingSessionLock"
      } else if (phase === 2) {
        service.requestSessionLock()
        service.logEvent("custom-event")
        service.requestSessionLock()
      } else if (phase === 3) {
        service.queueSessionLock()
        service.queueSessionLock()
      } else if (phase === 4) {
        // stabilize timer expired; a further queueSessionLock sees it stopped
        service.queueSessionLock()
        // fingerprint start with no PAM fixture: start() must fail
        service.fingerprintConfigured = true
        service.startFingerprint()
        if (service.fingerprintAuthenticating) throw "start should have failed without a PAM fixture"
        // lock IPC with no PAM fixture on an unlocked session
        ipc = findChild(service, function (o) { return o.target === "lock" })
        if (ipc === null) throw "lock IPC object not found"
        if (ipc.lock() !== "missing-pam") throw "lock() without PAM should report missing-pam"
      } else if (phase >= 6) {
        console.log("LOCK-QML-HARNESS-DONE")
        runner.stop()
        Qt.quit()
      }
    } catch (e) {
      console.warn("LOCK-QML-HARNESS-FAIL phase-B " + phase + ": " + e)
      runner.stop()
      Qt.quit()
    }
  }
}
