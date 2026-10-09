import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// MC/DC fixture driver (phase A, one-output sway) for shell/plugins/lock.
// Instantiates LockView and Service from the instrumented plugin sources and
// walks every decision's arms: property sweeps, direct function calls, real
// PAM transactions against a private /etc/pam.d (swapped per step from
// inside the namespace), a real session lock via WlSessionLock, real
// keystrokes into the locked surface via wtype, and PATH stubs for the
// process-driven branches. Prints LOCK-QML-HARNESS-DONE on success.
//
// Verifies: SW-REQ-261004-V813, SW-REQ-261004-296X, SW-REQ-261004-VVN2
//
// Row dispositions (see proof mcdc show <REQ-ID> for the tables):
//mcdc:ignore:defensive SW-REQ-261004-V813: fingerprint_auth_configured=F, fingerprint_probe_answered=T, fingerprint_was_configured=T, probe_lists_print=F, probe_says_none=F => FALSE -- applyFingerprintProbe returns before it assigns fingerprintConfigured when classifyProbe answers unknown and fingerprint is configured, so an answer that is neither a listed print nor a none cannot clear it [reviewed: REVIEW-261004-D4AD]
//mcdc:ignore:defensive SW-REQ-261004-V813: fingerprint_auth_configured=F, fingerprint_probe_answered=T, fingerprint_was_configured=T, probe_lists_print=T, probe_says_none=T => FALSE -- classifyProbe tests for a ' - #N:' row before either none answer, so an answer that lists a print classifies yes even when another reader has none, and the service sets fingerprintConfigured to true [reviewed: REVIEW-261004-D4AD]
//mcdc:ignore:defensive SW-REQ-261004-V813: fingerprint_auth_configured=T, fingerprint_probe_answered=T, fingerprint_was_configured=F, probe_lists_print=F, probe_says_none=F => FALSE -- an unknown answer while unconfigured returns before fingerprintConfigured is assigned, so it stays false [reviewed: REVIEW-261004-D4AD]
//mcdc:ignore:defensive SW-REQ-261004-V813: fingerprint_auth_configured=T, fingerprint_probe_answered=T, fingerprint_was_configured=T, probe_lists_print=F, probe_says_none=T => FALSE -- a none answer with no listed print classifies no, and the service assigns fingerprintConfigured = (status === "yes"), which is false [reviewed: REVIEW-261004-D4AD]
//mcdc:ignore:defensive SW-REQ-261004-296X: attempt_miss_streak_reached=F, attempt_usable=F, fingerprint_auth_configured=F, fingerprint_reader_unavailable=F, probe_miss_streak_reached=T => FALSE -- fingerprintUnavailable is a binding whose first disjunct is FingerprintModel.isUnavailable(fingerprintProbeStreak) (streak >= 3), so it is true whenever the probe streak reached 3 [reviewed: REVIEW-261004-5V8C]
//mcdc:ignore:defensive SW-REQ-261004-296X: attempt_miss_streak_reached=F, attempt_usable=F, fingerprint_auth_configured=F, fingerprint_reader_unavailable=T, probe_miss_streak_reached=F => FALSE -- the binding is exactly its two disjuncts; with the probe streak below 3 and fingerprint unconfigured both are false, so the reader cannot be reported unavailable [reviewed: REVIEW-261004-5V8C]
//mcdc:ignore:defensive SW-REQ-261004-296X: attempt_miss_streak_reached=T, attempt_usable=F, fingerprint_auth_configured=T, fingerprint_reader_unavailable=F, probe_miss_streak_reached=F => FALSE -- the binding's second disjunct is fingerprintConfigured && (!fingerprintAttemptReachedDevice || fingerprintAttemptFastError) && isUnavailable(fingerprintUnreachedStreak), which holds here, so the binding is true [reviewed: REVIEW-261004-5V8C]
//mcdc:ignore:defensive SW-REQ-261004-VVN2: key_autorepeat=F, key_erases=F, key_press_dropped=T => FALSE -- Keys.onPressed consumes a key without editing only when event.isAutoRepeat && dropsAutoRepeat(key); the only other accepting arm (Escape, Ctrl+U) clears the field, which is an edit [reviewed: REVIEW-261004-F4WB]
//mcdc:ignore:defensive SW-REQ-261004-VVN2: key_autorepeat=T, key_erases=F, key_press_dropped=F => FALSE -- dropsAutoRepeat is true for every key other than Backspace and Delete, and the handler then accepts the event and returns before the TextInput sees it [reviewed: REVIEW-261004-F4WB]
//mcdc:ignore:defensive SW-REQ-261004-VVN2: key_autorepeat=T, key_erases=T, key_press_dropped=T => FALSE -- dropsAutoRepeat is false for Backspace and Delete, so the handler falls through and the TextInput erases [reviewed: REVIEW-261004-F4WB]
import "plugins/lock" as LockPlugin

Item {
  id: root

  width: 800
  height: 600

  property string fail: ""
  property var ipc: null

  LockPlugin.LockView {
    id: lockView
    width: 800
    height: 600
  }

  LockPlugin.Service {
    id: service
    shell: null
  }

  // Driver-owned lock surface: takes exclusive keyboard focus when shown, so
  // wtype keystrokes reach a real LockView password field.
  PanelWindow {
    id: keyWindow
    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    LockPlugin.LockView {
      id: keyLockView
      anchors.fill: parent
      inputEnabled: true
    }
  }

  // Helper commands run one at a time, in order: a Process that is still
  // being reaped ignores a new start, so a direct restart could drop a
  // fixture swap or a stub flip.
  property var execQueue: []

  Process {
    id: shellExec
    command: ["true"]
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (!running) Qt.callLater(root.pumpExec)
    }
  }

  function pumpExec() {
    if (shellExec.running || execQueue.length === 0) return
    shellExec.command = execQueue.shift()
    shellExec.running = true
  }

  function exec(argv) {
    execQueue.push(argv)
    pumpExec()
  }

  function stubState(name, value) {
    exec(["bash", "-c", "printf '%s' '" + value + "' > \"" + Quickshell.env("MCDC_STUB_STATE") + "/" + name + "\""])
  }

  // Swap one of the private PAM fixtures into place. The driver runs inside
  // the mount namespace, so this never touches the host.
  function pamSwap(fixture, target) {
    exec(["bash", "-c", "cp \"" + Quickshell.env("MCDC_PAM_DIR") + "/" + fixture + "\" /etc/pam.d/" + target])
  }

  function pamRemove(target) {
    exec(["bash", "-c", "rm -f /etc/pam.d/" + target])
  }

  // The short pause lets the compositor hand the client this run's keymap
  // before the first key.
  function wtype(args) {
    exec([Quickshell.env("MCDC_WTYPE"), "-s", "150"].concat(args))
  }

  function check(condition, message) {
    if (!condition) throw message
  }

  // Fingerprint handles inside the service, found once at startup (before
  // any interval changes), among the service's own direct children.
  property var fpRetry: null
  property var fpReach: null
  property var fpRecheck: null
  property var fpSleepWatch: null
  property var fpPam: null
  property var probeProc: null
  // Each exit of the enrollment probe is one answer the service applied
  // (its own onExited handler runs before this counter's).
  property int probeAnswers: 0
  property int answersMark: 0
  // Keys.onPressed on the lock surface's view wakes the lock on every
  // press, auto-repeats included (counted through the service's re-arm);
  // a typed character wakes it once more through onTextChanged.
  property int keyWakes: 0

  Connections {
    target: root.probeProc
    function onExited() { root.probeAnswers += 1 }
  }

  property var blankTimer: null

  // Every wake the lock view asks for re-arms the idle-blank timer, so its
  // armedAt stamp moves once per key press (repeats arrive ~40 ms apart).
  Connections {
    target: root.blankTimer
    function onArmedAtChanged() { root.keyWakes += 1 }
  }

  function serviceChild(probe) {
    var kids = service.data || []
    for (var i = 0; i < kids.length; i++) {
      if (probe(kids[i])) return kids[i]
    }
    return null
  }

  // The WlSessionLock and the per-start UUID FileView are internal to Service
  // (omacom/omarchy#9429 request receipts); reach them through the child tree.
  function sessionLockObject() {
    return findChild(service, function (o) { return typeof o.secureStateChanged === "function" && typeof o.lockStateChanged === "function" })
  }
  function uuidFileView() {
    return findChild(service, function (o) { return o.path !== undefined && String(o.path).indexOf("random/uuid") >= 0 })
  }

  function serviceSecure() {
    return JSON.parse(ipc.status()).secure === true
  }

  // A suspend as the lock sees it: the event loop does not run while the
  // wall clock moves on (monotonic timers pause across suspend).
  function stallEventLoop(ms) {
    var until = Date.now() + ms
    while (Date.now() < until) {}
  }

  // Service keeps its PAM contexts and the lock IPC object as internal ids;
  // walk the QObject child tree to reach them.
  function findChild(obj, probe) {
    if (!obj) return null
    var pools = [obj.data || [], obj.resources || [], obj.children || []]
    // quickshell attaches the live WlSessionLockSurface as a property, not a
    // QObject child
    if (obj.surface !== undefined && obj.surface !== null) pools.push([obj.surface])
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

  // The service hosts two LockViews (lock surface + preview window); while
  // locked only the lock surface's field is enabled.
  function findTextInput(obj) {
    var fallback = null
    var enabledOne = findChild(obj, function (o) {
      if (!(o instanceof TextInput)) return false
      if (o.enabled) return true
      if (fallback === null) fallback = o
      return false
    })
    return enabledOne !== null ? enabledOne : fallback
  }

  property var keptLedgerForRestore: null
  property var uuidViewForRestore: null
  property real started: 0
  property int position: 0
  property var script: []

  Timer {
    id: runner
    interval: 50
    repeat: true
    running: false
    onTriggered: root.tick()
  }

  function tick() {
    var now = Date.now() - started
    while (position < script.length) {
      var step = script[position]
      if (step.at > now) return
      position += 1
      try {
        step.run()
      } catch (e) {
        fail = "step " + (position - 1) + " (at " + step.at + "ms): " + e
        console.warn("LOCK-QML-HARNESS-FAIL " + fail)
        runner.stop()
        Qt.quit()
        return
      }
    }
    console.log("LOCK-QML-HARNESS-DONE")
    runner.stop()
    Qt.quit()
  }

  Component.onCompleted: {
    ipc = findChild(service, function (o) { return o.target === "lock" })
    fpRetry = serviceChild(function (o) { return o instanceof Timer && o.interval === 250 && !o.repeat })
    fpReach = serviceChild(function (o) { return o instanceof Timer && o.interval === 20000 && !o.repeat })
    fpRecheck = serviceChild(function (o) { return o instanceof Timer && o.interval === 1000 && !o.repeat })
    fpSleepWatch = serviceChild(function (o) { return o instanceof Timer && o.lastTickMs !== undefined })
    fpPam = serviceChild(function (o) { return o.config === "omarchy-lock-fingerprint" })
    blankTimer = serviceChild(function (o) { return o instanceof Timer && o.armedAt !== undefined })
    probeProc = serviceChild(function (o) { return o.command !== undefined && String(o.command).indexOf("fprintd-list") >= 0 })
    if (!fpRetry || !fpReach || !fpRecheck || !fpSleepWatch || !fpPam || !probeProc || !blankTimer) {
      console.warn("LOCK-QML-HARNESS-FAIL fingerprint handles not found: retry=" + !!fpRetry + " reach=" + !!fpReach
                   + " recheck=" + !!fpRecheck + " sleepWatch=" + !!fpSleepWatch + " pam=" + !!fpPam + " probe=" + !!probeProc + " blank=" + !!blankTimer)
      Qt.quit()
      return
    }

    var t = 0
    function step(delay, fn) {
      t += delay
      script.push({ at: t, run: fn })
    }
    // Poll an async expectation: re-checks every 700ms (up to 12 tries)
    // before failing, so event-loop lag cannot turn a slow completion into
    // a harness failure.
    function stepWait(delay, cond, msg) {
      t += delay
      var entry = { at: t, tries: 0, run: function () {
        if (!cond()) {
          entry.tries += 1
          if (entry.tries > 12) throw msg
          entry.at = Date.now() - started + 700
          position -= 1
        }
      } }
      script.push(entry)
    }

    // ---------- LockView (standalone): bindings, handlers, direct text ----
    step(200, function () {
      lockView.passwordText = "abc"
    })
    step(100, function () {
      lockView.passwordText = "abcdefgh"
      lockView.fingerprintConfigured = true
    })
    step(100, function () {
      lockView.failureMessage = "denied"
      lockView.passwordText = "xyz"
    })
    step(100, function () {
      findTextInput(lockView).accepted()
    })
    step(100, function () {
      lockView.passwordText = ""
      findTextInput(lockView).accepted()
      lockView.clearPassword()
      // direct text change: the onTextChanged arms with syncingPasswordText
      // false, exactly like a real keystroke
      findTextInput(lockView).text = "typed-x"
    })
    step(100, function () {
      lockView.inputEnabled = false
      lockView.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      lockView.loadBackground = false
    })
    step(100, function () {
      lockView.inputEnabled = true
      lockView.loadBackground = true
      lockView.displaysBlank = true
    })
    step(100, function () {
      lockView.displaysBlank = false
      lockView.powerSaverActive = true
    })
    step(100, function () {
      lockView.powerSaverActive = false
    })
    step(100, function () {
      lockView.syncPasswordText()
      lockView.forcePasswordFocus()
      lockView.backgroundPath = ""
      lockView.failureMessage = ""
    })
    // blurEnabled arms: loadBackground true with the wallpaper not yet ready,
    // then with a real image file so BackgroundMedia reports ready.
    step(100, function () {
      lockView.loadBackground = true
      lockView.backgroundPath = Quickshell.env("MCDC_FAKE_IMAGE")
    })
    // An unreachable reader: crossed-out icon plus the notice under the
    // field; a reachable one keeps the plain icon and no notice.
    step(100, function () {
      lockView.fingerprintConfigured = true
      lockView.fingerprintUnavailable = true
      var notice = findChild(lockView, function (o) { return o.objectName === "fingerprintUnavailableNotice" })
      var icon = findChild(lockView, function (o) { return o.objectName === "fingerprintIndicator" })
      check(notice.visible, "an unavailable reader shows the notice")
      check(icon.text === "󰺱", "an unavailable reader crosses the icon out")
      lockView.fingerprintUnavailable = false
      check(!notice.visible, "an available reader shows no notice")
      check(icon.text === "󰈷", "an available reader shows the plain icon")
    })

    step(100, function () {
      check(keyLockView.dropsAutoRepeat(Qt.Key_A), "auto-repeat of a letter is dropped")
      check(!keyLockView.dropsAutoRepeat(Qt.Key_Backspace), "auto-repeat of Backspace still edits")
      check(!keyLockView.dropsAutoRepeat(Qt.Key_Delete), "auto-repeat of Delete still edits")
    })

    // ---------- Service before PAM is configured ----------
    step(200, function () {
      if (service.beginLock() !== false) throw "beginLock without PAM should return false"
      if (ipc.lock() !== "missing-pam") throw "lock() without PAM should report missing-pam"
      // Verifies: SW-REQ-261009-RCPT — tracked request IPC refuses without PAM
      check(JSON.parse(ipc.request()).reason === "missing-pam", "request() without PAM should report missing-pam")
      // a secure-state change while nothing is requested or held: the release arm's both conditions true
      var idleLock = sessionLockObject()
      check(idleLock !== null, "the session lock object is reachable")
      idleLock.secureStateChanged()
      // a second load with the ledger already built: the ledger is kept
      var uuidView = uuidFileView()
      check(uuidView !== null && service.requestLedger !== null, "the per-start ledger is built from the kernel UUID")
      var keptLedger = service.requestLedger
      uuidView.reload()
      check(service.requestLedger === keptLedger, "a reload keeps the existing ledger")
      // an empty UUID read builds no ledger (fail closed)
      stubState("empty-uuid", "")
      if (ipc.isLocked() !== "false") throw "isLocked should be false before locking"
      ipc.status()
      // submit with lockRequested forced on and no PAM config: start() fails
      service.lockRequested = true
      service.submitPassword("zz")
      if (service.failedAttempts !== 1) throw "failed start should record a failure"
      service.handlePasswordFailure()
      service.lockRequested = false
      service.handlePasswordFailure()
      service.authenticatingPassword = true
      service.lockRequested = false
      service.respondToPasswordPrompt()
      service.finishUnlock()
      service.authenticatingPassword = false
      // a submit with no lock requested: the guard's first condition
      service.submitPassword("pre-pam")
    })
    step(300, function () {
      var uuidView = uuidFileView()
      var keptLedger = service.requestLedger
      service.requestLedger = null
      uuidView.path = Quickshell.env("MCDC_STUB_STATE") + "/empty-uuid"
      uuidView.reload()
      root.keptLedgerForRestore = keptLedger
      root.uuidViewForRestore = uuidView
    })
    step(300, function () {
      check(service.requestLedger === null, "an empty UUID read builds no ledger")
      service.requestLedger = root.keptLedgerForRestore
      root.uuidViewForRestore.path = "/proc/sys/kernel/random/uuid"
    })
    step(200, function () {
      // double-call guards: the running-condition arms
      service.refreshBackground()
      service.refreshBackground()
      service.refreshFingerprintStatus()
      service.refreshFingerprintStatus()
      service.runWake()
      service.runWake()
      service.runBlank()
      service.runBlank()
      service.recoverStrandedLock()
      service.requestSessionLock()
      service.queueSessionLock()
      service.queueSessionLock()
    })
    step(300, function () {
      // applyMonitorDpms / screenBlank arms, including a null row
      service.applyMonitorDpms("not json")
      service.applyMonitorDpms("{}")
      service.applyMonitorDpms(JSON.stringify([
        { name: "HEADLESS-1", dpmsStatus: true },
        { name: "OFF", dpmsStatus: false },
        { name: "GHOST", dpmsStatus: true, disabled: true },
        { dpmsStatus: false },
        null
      ]))
      if (service.screenBlank("HEADLESS-1") !== false) throw "on-panel screenBlank should be false"
      if (service.screenBlank("OFF") !== true) throw "blanked panel screenBlank should be true"
      if (service.screenBlank("UNKNOWN") !== service.displaysBlank) throw "unknown panel falls back to displaysBlank"
      service.displaysBlank = true
      if (service.screenBlank("UNKNOWN") !== true) throw "fallback should follow displaysBlank"
      service.runWake()
      if (service.screenBlank("OFF") !== false) throw "after wake the map is dropped, fallback applies"
      service.displaysBlank = true
      if (service.screenBlank("UNKNOWN") !== true) throw "fallback should follow displaysBlank again"
      service.displaysBlank = false
    })
    step(200, function () {
      // batteryService / powerSaverActive arms
      service.shell = null
      if (service.powerSaverActive !== false) throw "powerSaver with no shell should be false"
      service.shell = {}
      service.shell = null
      service.shell = {
        services: {},
        firstPartyServiceFor: function (id) { return { powerSaverOnBattery: true } }
      }
      if (service.powerSaverActive !== true) throw "powerSaver from battery service should be true"
      service.shell = {
        services: {},
        firstPartyServiceFor: function (id) { return { powerSaverOnBattery: false } }
      }
      if (service.powerSaverActive !== false) throw "powerSaver false from battery service"
      service.shell = null
    })
    step(200, function () {
      // lockWallpaperUrl arms
      service.videoPosterPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.backgroundPath = Quickshell.env("MCDC_FAKE_IMAGE")
    })
    step(200, function () {
      // strand window with always-unresolved checks: the deny landing below
      // rearms through the configured-change handler, and the countdown then
      // runs its budget to zero untouched
      stubState("strand-mode", "twos")
      service.strandedLockResolved = false
    })
    step(200, function () {
      // poster: slow success with the path swapped mid-flight (mismatch arm),
      // then a failing run (exit-code arm)
      stubState("poster-slow", "1")
      service.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.refreshPoster()
    })
    step(250, function () {
      service.refreshPoster()
      service.backgroundPath = Quickshell.env("MCDC_FAKE_IMAGE")
    })
    step(800, function () {
      stubState("poster-slow", "")
    })
    step(700, function () {
      service.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.refreshPoster()
    })
    step(900, function () {
      service.backgroundPath = Quickshell.env("MCDC_FAKE_IMAGE")
      service.videoPosterPath = ""
    })

    // deny (pam_unix) fixture: beginLock locks for real against the private
    // sway once the watcher flips passwordPamConfigured.
    step(300, function () {
      pamSwap("omarchy-lock-password-deny", "omarchy-lock-password")
    })
    step(300, function () {
      service.beginLock()
    })
    stepWait(700, function () { return service.lockRequested }, "beginLock should have requested the lock")
    step(1400, function () {
      if (!service.lockRequested) throw "beginLock should have requested the lock"
      service.requestSessionLock()
      if (ipc.isLocked() !== "true") throw "isLocked should be true while locked"
      if (ipc.lock() !== "ok") throw "lock() while locked should be ok"
      // Verifies: SW-REQ-261009-RCPT — a tracked request while locked joins the active one
      var held = JSON.parse(ipc.request())
      check(held.requestId !== undefined, "request() while locked returns a receipt")
      check(JSON.parse(ipc.result(held.requestId)).requestId === held.requestId, "result() answers for the same request")
      var ledger = service.requestLedger
      service.requestLedger = null
      check(JSON.parse(ipc.request()).reason === "receipt-unavailable", "request() without a ledger refuses instead of locking untracked")
      service.requestLedger = ledger
      // a lock-state notification while the lock is held: the release hook does not release the receipt
      sessionLockObject().lockStateChanged()
      check(JSON.parse(ipc.result(held.requestId)).state !== "failed", "a held lock keeps its receipt across a lock-state notification")
      // recoverStrandedLock condition arms via direct state
      service.strandedLock = true
      service.recoverStrandedLock()
      service.passwordPamConfigured = false
      service.lockRequested = false
      service.strandedLock = true
      service.recoverStrandedLock()
      service.strandedLock = false
      service.passwordPamConfigured = true
    })
    step(400, function () {
      service.finishUnlock()
    })
    step(200, function () {
      // finishUnlock with no lock held but the request still on
      service.lockRequested = true
      service.finishUnlock()
      service.lockRequested = false
    })
    step(300, function () {
      // Verifies: SW-REQ-261009-RCPT — an unlocked tracked request starts a lock and reads pending;
      // released before it is secure, it reads failed
      var fresh = JSON.parse(ipc.request())
      check(fresh.state === "pending" && service.lockRequested, "request() while unlocked starts a tracked lock")
      // a secure-state change while the request is pending: the release arm's first condition false
      sessionLockObject().secureStateChanged()
      service.finishUnlock()
      check(JSON.parse(ipc.result(fresh.requestId)).state === "failed", "a request released before it is secure reads failed")
      // with no ledger, an unlocked request refuses and does not start a lock (it fails closed on reporting,
      // open on locking): pinned here so a change to that choice is visible
      var ledger = service.requestLedger
      service.requestLedger = null
      check(JSON.parse(ipc.request()).reason === "receipt-unavailable" && !service.lockRequested,
            "request() without a ledger starts no lock")
      // a legacy lock with no ledger still locks (it just tracks nothing)
      check(service.beginLock() === true && service.lockRequested, "beginLock without a ledger still requests the lock")
      service.finishUnlock()
      service.requestLedger = ledger
    })
    step(200, function () {
      // slow strand check, started unlocked and unrequested: the second call
      // meets the running process and the process exits after the lock lands
      stubState("strand-mode", "slow")
      service.strandedLockResolved = false
      service.checkStrandedLock()
    })
    step(500, function () {
      // the slow strand process is still running
      service.checkStrandedLock()
    })
    step(200, function () {
      service.beginLock()
    })
    step(2300, function () {
      // the slow strand process exited while the lock was held
      stubState("strand-mode", "")
      // the exit resolved the strand: the guard's first condition
      service.checkStrandedLock()
    })
    // ---------- held keys in the locked password field (SW-REQ-261004-VVN2) --
    // wtype holds a key down on the real lock surface; the compositor's
    // repeat info makes the Qt client deliver auto-repeat presses
    // (isAutoRepeat) until the release. The typed text lands in the
    // service's enteredPassword through the view's passwordTextEdited.
    step(300, function () {
      check(serviceSecure() && service.lockRequested, "the held-key cases run on a secure lock")
      service.enteredPassword = ""
      wtype(["-P", "x", "-p", "x"])
    })
    stepWait(400, function () { return service.enteredPassword.length > 0 }, "a tapped key should type on the lock")
    step(100, function () {
      // Verifies: SW-REQ-261004-VVN2
      // MCDC SW-REQ-261004-VVN2: key_autorepeat=F, key_erases=F, key_press_dropped=F => TRUE
      check(service.enteredPassword === "x", "a single press types its character")
      service.enteredPassword = ""
      keyWakes = 0
      wtype(["-P", "x", "-s", "1500", "-p", "x"])
    })
    step(2200, function () {
      var typed = service.enteredPassword
      // the first press and at least three repeats woke the lock
      check(keyWakes >= 4, "holding a key should deliver auto-repeat presses (saw " + keyWakes + " wakes)")
      // Verifies: SW-REQ-261004-VVN2
      // MCDC SW-REQ-261004-VVN2: key_autorepeat=T, key_erases=F, key_press_dropped=T => TRUE
      check(typed === "x", "auto-repeats of a held key must not type (field holds " + typed.length + ")")
      service.enteredPassword = "aaaaaaaaaaaaaaaaaaaaaaaa"
      keyWakes = 0
      wtype(["-k", "End", "-P", "BackSpace", "-s", "1500", "-p", "BackSpace"])
    })
    step(2200, function () {
      var left = service.enteredPassword.length
      check(keyWakes >= 4, "holding Backspace should deliver auto-repeat presses (saw " + keyWakes + " wakes)")
      check(left < 23, "holding Backspace keeps erasing (field holds " + left + ")")
      service.enteredPassword = "aaaaaaaaaaaaaaaaaaaaaaaa"
      wtype(["-k", "Home", "-P", "Delete", "-s", "1500", "-p", "Delete"])
    })
    step(2200, function () {
      var left = service.enteredPassword.length
      check(left < 23, "holding Delete keeps erasing (field holds " + left + ")")
      service.enteredPassword = ""
    })
    step(300, function () {
      // real keystrokes into the driver's focused lock surface
      keyWindow.visible = true
      keyLockView.forcePasswordFocus()
      wtype(["-P", "x", "-p", "x"])
    })
    step(450, function () {
      keyLockView.forcePasswordFocus()
      wtype(["-P", "Return", "-p", "Return"])
    })
    step(500, function () {
      keyLockView.forcePasswordFocus()
      wtype(["-P", "Escape", "-p", "Escape"])
    })
    step(450, function () {
      keyLockView.forcePasswordFocus()
      wtype(["-M", "ctrl", "-P", "u", "-p", "u", "-m", "ctrl"])
    })
    step(450, function () {
      keyLockView.forcePasswordFocus()
      wtype(["-M", "shift", "-P", "u", "-p", "u", "-m", "shift"])
    })
    step(450, function () {
      keyLockView.forcePasswordFocus()
      wtype(["-P", "Escape", "-p", "Escape"])
    })
    step(450, function () {
      wtype(["-P", "Return", "-p", "Return"])
    })
    step(400, function () {
      keyWindow.visible = false
      // submitPassword condition arms: empty, then a wrong password against
      // pam_unix, spaced out so the transaction completes between submits
      service.submitPassword("")
    })
    step(700, function () {
      service.submitPassword("wrong-one")
    })
    stepWait(1200, function () { return service.failedAttempts >= 1 }, "pam_unix submit should have recorded a failure")
    step(400, function () {
      // re-submit while authenticating: the guard's middle condition
      service.authenticatingPassword = true
      service.submitPassword("wrong-two")
      service.authenticatingPassword = false
      service.respondToPasswordPrompt()
      service.resetAuthenticationState()
      service.respondToPasswordPrompt()
    })
    step(400, function () {
      // a submit whose PAM completes after the lock is already gone
      service.beginLock()
      service.submitPassword("late-attempt")
    })
    step(150, function () {
      service.finishUnlock()
    })
    step(200, function () {
      service.handleFingerprintFinished(PamResult.Failure)
    })
    step(600, function () {
      // more late attempts: drop the request without aborting so the PAM
      // completion lands with no lock requested
      service.beginLock()
      service.submitPassword("late-attempt-2")
      service.lockRequested = false
    })
    stepWait(1400, function () { return !service.authenticatingPassword }, "late attempt should have settled")
    step(400, function () {
      service.beginLock()
      service.submitPassword("late-attempt-3")
      service.lockRequested = false
    })
    stepWait(1400, function () { return !service.authenticatingPassword }, "late attempt should have settled")
    step(100, function () {
      // direct fingerprint-finished arms, then relock through the strand
      // check so the permit submit lands on a held lock
      service.handleFingerprintFinished(PamResult.Failure)
      service.lockRequested = true
      service.fingerprintConfigured = false
      service.handleFingerprintFinished(PamResult.Failure)
      service.handleFingerprintFinished(PamResult.Success)
      if (service.lockRequested) throw "fingerprint Success should finish the unlock"
      service.lockRequested = false
      service.handleFingerprintFinished(PamResult.Failure)
      service.startFingerprint()
      // a strand exit while the request is on but the lock is not held
      service.strandedLockResolved = false
      service.lockRequested = true
      service.passwordPamConfigured = false
      service.passwordPamConfigured = true
    })
    step(500, function () {
      // a submit with no lock requested: the guard's first condition
      service.submitPassword("post-unlock-2")
    })

    // permit (pam_permit) fixture: real password success path on the
    // strand-recovered lock.
    step(300, function () {
      pamSwap("omarchy-lock-password-permit", "omarchy-lock-password")
    })
    step(600, function () {
      if (!service.lockRequested) service.beginLock()
      service.submitPassword("correct-pass")
    })
    // resubmit on each retry: the swapped fixture may land after the first
    // submit read the still-deny file
    stepWait(1300, function () {
      if (service.lockRequested) service.submitPassword("correct-pass")
      return !service.lockRequested
    }, "pam_permit submit should have finished the unlock")
    step(300, function () {
      // a submit whose success completion lands with no lock requested
      service.submitPassword("late-permit")
    })

    // ---------- preview window + final IPC sweep ----------
    step(300, function () {
      ipc.preview()
    })
    step(500, function () {
      ipc.hidePreview()
      ipc.status()
      if (ipc.lock() !== "ok") throw "lock() with PAM configured should succeed"
    })

    // ---------- monitorDpms timer: locked + video ----------
    step(400, function () {
      // re-assert the video here: the preview's background refresh may have
      // landed a real wallpaper path in between
      service.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.beginLock()
    })
    // the hyprctl stub answers after 12s, so five fires land before the
    // video drops: (T) running, then (F) running, then the (T,F) binding flip
    step(13500, function () {
      service.backgroundPath = Quickshell.env("MCDC_FAKE_IMAGE")
      service.finishUnlock()
    })

    // ---------- idleBlankTimer choreography ----------
    // Natural five-second fires walk the guard arms: armed with the
    // authenticating flag on (which the changed-handler cannot stop), the
    // fire meets (T,F) and skips; flag off re-arms through the handler and
    // the next fresh fire blanks (T,T); request off skips (F).
    step(400, function () {
      service.lockRequested = true
      service.authenticatingPassword = true
      service.armBlankTimer()
    })
    step(5500, function () {
      if (service.displaysBlank) throw "blank while authenticating must not blank"
    })
    step(200, function () {
      service.authenticatingPassword = false
    })
    stepWait(5500, function () { return service.displaysBlank }, "blank timer should have blanked the displays")
    step(200, function () {
      service.lockRequested = false
      service.runWake()
      service.armBlankTimer()
    })
    step(5500, function () {
      // (F,skip): no lock, no blank
      if (service.displaysBlank) throw "blank timer without a lock must not blank"
    })

    // ---------- password PAM hung active, then reset ----------
    step(400, function () {
      pamSwap("omarchy-lock-password-hang", "omarchy-lock-password")
      service.beginLock()
    })
    step(900, function () {
      // the pam_exec fixture is in place: the transaction stays active
      service.submitPassword("hang-attempt")
    })
    step(600, function () {
      // resetAuthenticationState with the password context active
      service.resetAuthenticationState()
    })

    // ---------- fingerprint PAM: hung active window, then fast errors ----
    step(400, function () {
      pamSwap("omarchy-lock-fingerprint-hang", "omarchy-lock-fingerprint")
      if (!service.lockRequested) service.beginLock()
      stubState("fprintd", "yes")
    })
    step(500, function () {
      service.refreshFingerprintStatus()
    })
    stepWait(600, function () { return service.fingerprintConfigured }, "fingerprintConfigured did not flip true")
    step(100, function () {
      // the enrollment stub answers no here, so the refresh handler records
      // configured=false and the still-active hung transaction takes the
      // else-if abort arm
      stubState("fprintd", "no")
      service.refreshFingerprintStatus()
    })
    step(700, function () {
      // start a fresh hung transaction for the reset arm; an abort leaves
      // the authenticating flag set, so settle it through the handler first
      service.handleFingerprintFinished(PamResult.Failure)
      service.fingerprintConfigured = true
      service.startFingerprint()
    })
    step(400, function () {
      // the transaction is confirmed active by now; the reset must abort it
      service.startFingerprint()
      service.resetAuthenticationState()
    })
    step(200, function () {
      // the broken-module fixture is swapped in for the error arms below
      pamSwap("omarchy-lock-fingerprint-broken", "omarchy-lock-fingerprint")
    })
    step(450, function () {
      // this error carries (locked, configured) and arms the retry
      service.fingerprintConfigured = true
      service.startFingerprint()
    })
    step(250, function () {
      // a second start whose error lands after configured flips false while
      // the request stays on: the handler's skip arm
      service.startFingerprint()
      service.fingerprintConfigured = false
    })
    stepWait(900, function () { return !service.fingerprintAuthenticating }, "broken-module attempt should have settled")
    step(200, function () {
      // a third start: the retry's error lands with configured still false
      service.beginLock()
      service.fingerprintConfigured = true
      service.startFingerprint()
      service.fingerprintConfigured = false
    })
    stepWait(900, function () { return !service.fingerprintAuthenticating }, "broken-module attempt should have settled")
    step(200, function () {
      // one final start with the request dropped right after: the error
      // lands with the handler's request-off arm
      service.beginLock()
      service.fingerprintConfigured = true
      service.startFingerprint()
      service.lockRequested = false
    })
    stepWait(900, function () { return !service.fingerprintAuthenticating }, "broken-module attempt should have settled")
    step(600, function () {
      service.beginLock()
    })
    step(150, function () {
      // unlock while the broken-module error is in flight: the handler's
      // request-off arm
      service.finishUnlock()
    })
    step(600, function () {
      service.beginLock()
    })
    step(100, function () {
      // the fingerprint fixture is removed: the start below must fail once
      // the removal lands
      pamRemove("omarchy-lock-fingerprint")
      service.fingerprintConfigured = true
    })
    stepWait(700, function () {
      if (!service.fingerprintAuthenticating) return true
      service.startFingerprint()
      return false
    }, "start should have failed without a PAM fixture")
    step(600, function () {
      service.finishUnlock()
    })

    step(200, function () {
      // keep a hung fingerprint transaction alive across the unlock so the
      // unlocked refreshes meet an active context
      service.fingerprintConfigured = true
      service.startFingerprint()
    })
    step(200, function () {
      // unlocked refreshes: the else-if chain evaluates with the enrollment
      // stub answering yes (skip) and then no (abort of the live context)
      stubState("fprintd", "yes")
      service.refreshFingerprintStatus()
    })
    step(400, function () {
      stubState("fprintd", "no")
      service.refreshFingerprintStatus()
    })

    // ---------- strand: exit while requested-but-unheld, resolved guard ----
    step(300, function () {
      // resolved first so the rearm runs against it, then re-open the
      // countdown for a clean run to zero
      service.strandedLockResolved = true
      service.passwordPamConfigured = false
      service.passwordPamConfigured = true
    })
    step(300, function () {
      service.strandedLock = false
      service.strandedLockResolved = false
      service.lockRequested = true
      service.checkStrandedLock()
    })
    stepWait(700, function () { return service.strandedLockResolved }, "strand exit should have resolved while the request was still on")
    step(200, function () {
      service.lockRequested = false
      // resolved guard arm against a live check
      service.checkStrandedLock()
    })

    // ---------- poster: same-path success cycles ----------
    step(400, function () {
      service.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.refreshPoster()
    })
    stepWait(1500, function () { return service.videoPosterPath !== "" }, "poster success should set videoPosterPath")
    step(200, function () {
      // a failing poster run: the exit-code ternary false arm (the long gap
      // lets the success process finish and clear its running flag)
      stubState("poster-fail", "1")
    })
    step(2500, function () {
      service.backgroundPath = Quickshell.env("MCDC_FAKE_VIDEO")
      service.refreshPoster()
    })
    step(600, function () {
      stubState("poster-fail", "")
    })

    // ---------- strand countdown: budget exhausted, then a resolved rearm --
    step(300, function () {
      // twos keeps every check unresolved, so the rearm below restarts the
      // budget and the countdown runs to zero untouched
      stubState("strand-mode", "twos")
      service.strandedLockResolved = false
      service.passwordPamConfigured = false
      service.passwordPamConfigured = true
    })
    step(2000, function () {
      var retry = findChild(service, function (o) {
        return o.remaining !== undefined && o.budget !== undefined
      })
      console.warn("STRAND-TIMER t2 remaining=" + (retry ? retry.remaining : "?") + " running=" + (retry ? retry.running : "?"))
    })
    step(9500, function () {
      // the budget exhausted while unresolved: running flips false
      var retry = findChild(service, function (o) {
        return o.remaining !== undefined && o.budget !== undefined
      })
      console.warn("STRAND-TIMER t3 remaining=" + (retry ? retry.remaining : "?") + " running=" + (retry ? retry.running : "?"))
    })
    step(300, function () {
      stubState("strand-mode", "")
      service.strandedLockResolved = true
      service.passwordPamConfigured = false
      service.passwordPamConfigured = true
    })
    step(400, function () {
      // a screens change rearms the strand timer with resolution already in
      // place: the rearm's resolved-skip arm
      exec(["bash", "-c", "SWAYSOCK=" + Quickshell.env("MCDC_SWAYSOCK") + " " + Quickshell.env("MCDC_SWAYMSG") + " output HEADLESS-1 unplug"])
    })
    step(1200, function () {
      exec(["bash", "-c", "SWAYSOCK=" + Quickshell.env("MCDC_SWAYSOCK") + " " + Quickshell.env("MCDC_SWAYMSG") + " create_output"])
    })

    // ---------- fingerprint reader: probe answers, misses, prompts, sleep ----
    // A real lock with the fprintd-list stub answering the enrollment probe
    // and PAM fixtures standing in for the reader: nologin (an error
    // message, never a prompt), prompt (two prompts, then waits for a
    // finger), silent (never answers).
    step(400, function () {
      if (service.lockRequested || service.locked) service.finishUnlock()
      pamSwap("omarchy-lock-fingerprint-nologin", "omarchy-lock-fingerprint")
    })
    step(300, function () {
      stubState("fprintd", "unknown")
    })
    step(300, function () {
      check(!service.fingerprintConfigured, "fingerprint should start unconfigured")
      answersMark = probeAnswers
      service.beginLock()
      // Verifies: SW-REQ-261004-296X
      // MCDC SW-REQ-261004-296X: attempt_miss_streak_reached=F, attempt_usable=F, fingerprint_auth_configured=F, fingerprint_reader_unavailable=F, probe_miss_streak_reached=F => TRUE
      check(service.fingerprintProbeStreak === 0 && service.fingerprintUnreachedStreak === 0 && !service.fingerprintUnavailable,
            "a fresh lock with no misses does not report the reader unavailable")
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the lock's enrollment probe should answer")
    step(50, function () {
      // Verifies: SW-REQ-261004-V813
      // MCDC SW-REQ-261004-V813: fingerprint_auth_configured=F, fingerprint_probe_answered=T, fingerprint_was_configured=F, probe_lists_print=F, probe_says_none=F => TRUE
      check(String(probeProc.stdout.text).indexOf("ListEnrolledFingers failed") >= 0, "the probe answered with a D-Bus failure")
      check(!service.fingerprintConfigured && service.fingerprintProbeStreak === 1,
            "an unreachable fprintd leaves fingerprint unconfigured and counts the miss")
      check(fpRecheck.running && fpRecheck.interval === 1000, "an unknown answer re-probes after the first backoff")
    })
    // the recheck timer asks again after 1 s and 2 s
    stepWait(2500, function () { return service.fingerprintProbeStreak >= 3 }, "three unknown answers should build the probe streak")
    step(50, function () {
      check(serviceSecure(), "the lock should be secure by now")
      check(!service.fingerprintConfigured && service.fingerprintUnavailable,
            "three unknown answers report the reader unavailable without inventing an enrollment")
      // the preview view binds the same service state as the lock
      // surface's (whose instance the session lock does not expose); show
      // it for the check
      service.previewVisible = true
      var view = findChild(service, function (o) { return o.dropsAutoRepeat !== undefined })
      var icon = findChild(view, function (o) { return o.objectName === "fingerprintIndicator" })
      var notice = findChild(view, function (o) { return o.objectName === "fingerprintUnavailableNotice" })
      check(view.fingerprintConfigured && view.fingerprintUnavailable, "the view is told the reader is unavailable")
      check(icon.visible && icon.text === "󰺱", "the view crosses the icon out")
      check(notice.visible, "the view explains the unavailable reader")
      service.previewVisible = false
      check(fpRecheck.running && fpRecheck.interval === 4000, "the third miss backs the probe off to 4 s")
      stubState("fprintd", "yes")
    })
    step(300, function () {
      // user activity shortens the probe backoff to the swipe interval
      service.runWake()
      check(fpRecheck.running && fpRecheck.interval === 250, "input promptly re-probes an unreachable fprintd")
    })
    stepWait(400, function () { return service.fingerprintConfigured }, "a listed print should enable fingerprint")
    // the attempt meets the nologin reader: an error message, no prompt
    stepWait(300, function () { return service.fingerprintUnreachedStreak >= 1 }, "an attempt that never prompts should count as a miss")
    step(50, function () {
      // Verifies: SW-REQ-261004-296X
      // MCDC SW-REQ-261004-296X: attempt_miss_streak_reached=F, attempt_usable=F, fingerprint_auth_configured=T, fingerprint_reader_unavailable=F, probe_miss_streak_reached=F => TRUE
      check(service.fingerprintUnreachedStreak < 3 && !service.fingerprintAttemptReachedDevice && !service.fingerprintUnavailable,
            "a miss or two does not report the reader unavailable yet")
      check(service.fingerprintProbeStreak === 0 && !fpRecheck.running, "a definitive answer clears the probe streak and its recheck")
    })
    stepWait(2500, function () { return service.fingerprintUnreachedStreak >= 3 }, "three misses in a row should build the attempt streak")
    step(50, function () {
      check(service.fingerprintConfigured && service.fingerprintUnavailable, "three unreached attempts report the reader unavailable")
      check(fpRetry.running && fpRetry.interval >= 4000, "the third miss backs the attempt off to 4 s or more")
      check(service.lockRequested, "misses never unlock")
      stubState("fprintd", "no")
    })
    step(300, function () {
      answersMark = probeAnswers
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the none answer should arrive")
    step(50, function () {
      // Verifies: SW-REQ-261004-V813
      // MCDC SW-REQ-261004-V813: fingerprint_auth_configured=F, fingerprint_probe_answered=T, fingerprint_was_configured=T, probe_lists_print=F, probe_says_none=T => TRUE
      check(/has no fingers enrolled/.test(probeProc.stdout.text) && !/ - #[0-9]+:/.test(probeProc.stdout.text), "the probe answered none")
      check(!service.fingerprintConfigured, "an empty enrollment disables fingerprint")
      // Verifies: SW-REQ-261004-296X
      // MCDC SW-REQ-261004-296X: attempt_miss_streak_reached=T, attempt_usable=F, fingerprint_auth_configured=F, fingerprint_reader_unavailable=F, probe_miss_streak_reached=F => TRUE
      check(service.fingerprintUnreachedStreak >= 3 && !service.fingerprintAttemptReachedDevice && !service.fingerprintUnavailable,
            "a reader with no enrolled print is not reported unavailable, whatever its misses")
      check(!fpRetry.running && !service.fingerprintAuthenticating && !fpReach.running, "no enrollment stops the attempts")
      pamSwap("omarchy-lock-fingerprint-prompt", "omarchy-lock-fingerprint")
    })
    step(300, function () {
      stubState("fprintd", "yes")
    })
    step(300, function () {
      service.refreshFingerprintStatus()
    })
    // re-ask on each poll: the stub flip may land after the first probe
    stepWait(300, function () {
      if (service.fingerprintConfigured) return true
      console.warn("waiting for the listed print; last probe answer " + JSON.stringify(probeProc.stdout.text))
      service.refreshFingerprintStatus()
      return false
    }, "the listed print should enable fingerprint again")
    stepWait(100, function () { return service.fingerprintAttemptReachedDevice }, "the prompting reader should reach the device")
    step(400, function () {
      // Verifies: SW-REQ-261004-296X
      // MCDC SW-REQ-261004-296X: attempt_miss_streak_reached=T, attempt_usable=T, fingerprint_auth_configured=T, fingerprint_reader_unavailable=F, probe_miss_streak_reached=F => TRUE
      check(service.fingerprintConfigured && service.fingerprintUnreachedStreak >= 3 && service.fingerprintAttemptReachedDevice
            && !service.fingerprintAttemptFastError && !service.fingerprintUnavailable,
            "a finger prompt clears the unavailable report before the attempt ends")
      check(service.fingerprintAuthenticating && fpPam.active && !fpReach.running, "a prompted attempt waits for a finger without the reach bound")
      stubState("fprintd", "both")
    })
    step(300, function () {
      answersMark = probeAnswers
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the two-reader answer should arrive")
    step(50, function () {
      // Verifies: SW-REQ-261004-V813
      // MCDC SW-REQ-261004-V813: fingerprint_auth_configured=T, fingerprint_probe_answered=T, fingerprint_was_configured=T, probe_lists_print=T, probe_says_none=T => TRUE
      check(/has no fingers enrolled/.test(probeProc.stdout.text) && / - #[0-9]+:/.test(probeProc.stdout.text), "the probe answered for two readers")
      check(service.fingerprintConfigured, "a print listed on one reader keeps fingerprint configured though another reader has none")
      check(service.fingerprintAuthenticating && fpPam.active, "the attempt in flight carries on")
      answersMark = probeAnswers
    })
    step(600, function () {
      // Verifies: SW-REQ-261004-V813
      // MCDC SW-REQ-261004-V813: fingerprint_auth_configured=T, fingerprint_probe_answered=F, fingerprint_was_configured=F, probe_lists_print=F, probe_says_none=F => TRUE [no-action: the probe-exit counter does not move across this 600 ms window, so no enrollment answer arrived, and fingerprintConfigured keeps the value the last answer gave]
      check(probeAnswers === answersMark && service.fingerprintConfigured, "with no probe answer the configured state does not change")
      stubState("fprintd", "unknown")
    })
    step(300, function () {
      answersMark = probeAnswers
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the unknown answer should arrive")
    step(50, function () {
      check(String(probeProc.stdout.text).indexOf("ListEnrolledFingers failed") >= 0, "the probe answered with a D-Bus failure")
      check(service.fingerprintConfigured && service.fingerprintProbeStreak === 0 && !fpRecheck.running,
            "an unknown answer keeps a known enrollment and leaves recovery to PAM")
      check(fpSleepWatch.running && fpPam.active && service.fingerprintAttemptReachedDevice, "a prompted attempt is in flight before the sleep")
    })
    step(100, function () {
      // suspend with the prompted attempt in flight: the watcher's next
      // tick sees the wall-clock gap and restarts the attempt
      stallEventLoop(3300)
    })
    stepWait(100, function () { return service.fingerprintResumedAtMs > 0 }, "the sleep watcher should notice the gap")
    step(50, function () {
      check(service.lockRequested, "resume never unlocks")
      check(service.fingerprintUnreachedStreak === 0, "the reached attempt the sleep cut short counts as usable and clears the streak")
    })
    // the 250 ms retry starts a fresh prompted attempt
    stepWait(300, function () { return fpPam.active && service.fingerprintAttemptReachedDevice }, "the attempt should restart after the sleep")
    step(100, function () {
      // the next attempt meets a reader that never answers
      pamSwap("omarchy-lock-fingerprint-silent", "omarchy-lock-fingerprint")
    })
    step(300, function () {
      // the reach bound's handler on a live conversation aborts it
      service.timeoutFingerprintReach()
      check(!fpPam.active && !service.fingerprintAuthenticating && !fpReach.running, "the reach bound closes a live attempt")
      service.fingerprintResumedAtMs = 0
    })
    stepWait(1500, function () { return fpPam.active && !service.fingerprintAttemptReachedDevice }, "a silent attempt should be in flight")
    step(100, function () {
      check(fpReach.running, "an attempt that has not prompted runs under the reach bound")
      // suspend with an unreached attempt in flight; on resume the
      // conversation errors out before the watcher's tick
      stallEventLoop(3300)
      var before = service.fingerprintUnreachedStreak
      service.settleFingerprintAttempt(true)
      check(service.fingerprintResumedAtMs > 0, "an error after a sleep notes the resume itself")
      check(service.fingerprintUnreachedStreak === 1, "a miss in the resume grace counts as the first (was " + before + ")")
      check(fpPam.active && !service.fingerprintAuthenticating, "the errored conversation is still open")
    })
    stepWait(100, function () { return !fpPam.active }, "the watcher should close the leftover conversation")
    step(300, function () {
      check(service.lockRequested, "resume never unlocks")
      stubState("fprintd", "no")
    })
    step(300, function () {
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return !service.fingerprintConfigured }, "the none answer should disable fingerprint")
    step(200, function () {
      service.finishUnlock()
      stubState("fprintd", "unknown")
    })
    step(300, function () {
      answersMark = probeAnswers
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the unlocked unknown answer should arrive")
    step(50, function () {
      check(!fpRecheck.running, "an unknown probe outside the lock does not re-probe")
      stubState("fprintd", "yes")
    })
    step(300, function () {
      answersMark = probeAnswers
      service.refreshFingerprintStatus()
    })
    stepWait(300, function () { return probeAnswers > answersMark }, "the unlocked listed answer should arrive")
    // a probe started earlier can finish first and bump the counter; wait for the listed answer itself
    stepWait(50, function () { return service.fingerprintConfigured }, "the unlocked listed answer should configure the reader")
    step(50, function () {
      check(service.fingerprintConfigured && !service.fingerprintAuthenticating, "a listed print outside the lock starts nothing")
      stubState("fprintd", "no")
    })

    // ---------- fingerprint attempt bookkeeping with crafted state ----------
    // The arms the reader fixtures cannot time (fast errors, prompt clocks,
    // retry pacing, the resume grace) are driven by calling the service
    // with crafted attempt state, as upstream's lock-fingerprint-service
    // fixture does. No session lock is held, so startFingerprint never opens
    // a conversation and every call below runs synchronously in this step.
    step(300, function () {
      check(!serviceSecure() && !fpPam.active, "the crafted walk runs with no lock and no conversation")
      service.lockRequested = true
      service.fingerprintConfigured = true
      service.resetAuthenticationState()

      // a listed print while a retry is pending leaves the retry in charge
      service.armFingerprintRetry(250)
      service.applyFingerprintProbe("Fingerprints for user test on Goodix:\n - #0: right-index-finger")
      check(service.fingerprintConfigured && !service.fingerprintAuthenticating && fpRetry.running, "a pending retry owns the next attempt")
      fpRetry.stop()

      // nudges: nothing pending, a backed-off retry, then the cooldown
      service.nudgeFingerprint()
      check(!fpRetry.running, "input with no retry pending starts nothing")
      service.fingerprintAuthenticating = true
      service.nudgeFingerprint()
      service.fingerprintAuthenticating = false
      service.armFingerprintRetry(8000)
      service.nudgeFingerprint()
      check(fpRetry.interval === 250, "input advances a backed-off retry")
      service.armFingerprintRetry(8000)
      service.nudgeFingerprint()
      check(fpRetry.interval === 8000, "continuous input cannot collapse every retry")
      fpRetry.stop()

      // a usable attempt with no misses before it
      service.fingerprintAuthenticating = true
      service.fingerprintAttemptReachedDevice = false
      service.noteFingerprintReachedDevice()
      service.noteFingerprintReachedDevice()
      service.settleFingerprintAttempt()
      check(service.fingerprintUnreachedStreak === 0 && fpRetry.interval === 250, "a reached attempt retries at the swipe interval")

      // device errors: unreached, slow after the prompt, fast after it
      service.fingerprintAuthenticating = true
      service.fingerprintAttemptReachedDevice = false
      service.settleFingerprintAttempt(true)
      check(service.fingerprintUnreachedStreak === 1, "an error before any prompt is a miss")
      service.fingerprintAuthenticating = true
      service.fingerprintAttemptReachedDevice = true
      service.fingerprintAttemptPromptedAtMs = Date.now() - 5000
      service.settleFingerprintAttempt(true)
      check(service.fingerprintUnreachedStreak === 0 && !service.fingerprintAttemptFastError, "an error long after the prompt is usable and recovers")
      service.fingerprintAuthenticating = true
      service.fingerprintAttemptReachedDevice = true
      service.fingerprintAttemptPromptedAtMs = Date.now()
      service.settleFingerprintAttempt(true)
      check(service.fingerprintUnreachedStreak === 1 && service.fingerprintAttemptFastError, "an error right after the prompt is a miss")

      // the streak crosses into unavailable at 3, and stays past it
      service.fingerprintUnreachedStreak = 2
      service.fingerprintAuthenticating = true
      service.fingerprintAttemptReachedDevice = false
      service.settleFingerprintAttempt()
      check(service.fingerprintUnreachedStreak === 3 && service.fingerprintUnavailable, "the third miss reports unavailable")
      service.fingerprintAuthenticating = true
      service.settleFingerprintAttempt()
      check(service.fingerprintUnreachedStreak === 4 && service.fingerprintUnavailable, "further misses keep it unavailable")

      // resume: grace once, then inside it
      service.fingerprintResumedAtMs = 0
      service.noteFingerprintResumed()
      var resumedAt = service.fingerprintResumedAtMs
      check(resumedAt > 0 && service.fingerprintUnreachedStreak === 0, "a resume clears the pre-sleep misses")
      service.fingerprintUnreachedStreak = 2
      service.noteFingerprintResumed()
      check(service.fingerprintResumedAtMs === resumedAt && service.fingerprintUnreachedStreak === 2, "a second resume inside the grace changes nothing")

      // restart after sleep: an attempt in flight, a pending retry, neither
      service.fingerprintAuthenticating = true
      service.restartFingerprintAfterSleep()
      check(!service.fingerprintAuthenticating && fpRetry.running, "a resume settles the attempt in flight")
      service.armFingerprintRetry(8000)
      service.restartFingerprintAfterSleep()
      check(fpRetry.running && fpRetry.interval === 250, "a resume restarts a pending wait at the swipe interval")
      fpRetry.stop()
      service.restartFingerprintAfterSleep()
      check(!fpRetry.running, "a resume with nothing pending starts nothing")

      // a reach timeout with no conversation open
      service.fingerprintAuthenticating = true
      service.timeoutFingerprintReach()
      check(!service.fingerprintAuthenticating, "the reach bound closes the attempt")

      // completions: a match after misses unlocks; one with no lock settles
      service.lockRequested = false
      service.fingerprintAuthenticating = true
      service.handleFingerprintFinished(PamResult.Success)
      check(!service.fingerprintAuthenticating && !service.lockRequested, "a match with no lock requested only settles")
      service.lockRequested = true
      service.fingerprintUnreachedStreak = 2
      service.handleFingerprintFinished(PamResult.Success)
      check(!service.lockRequested && service.fingerprintUnreachedStreak === 0, "a match after misses unlocks")

      service.fingerprintConfigured = false
      service.resetAuthenticationState()
    })

    step(300, function () {
      // diagnostic: confirm the stub PATH is visible to spawned processes
      exec(["bash", "-c", "command -v hyprctl > \"" + Quickshell.env("MCDC_STUB_STATE") + "/path-dump\" 2>&1; command -v fprintd-list >> \"" + Quickshell.env("MCDC_STUB_STATE") + "/path-dump\" 2>&1"])
    })

    started = Date.now()
    runner.start()
  }
}
