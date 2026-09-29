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

  Process {
    id: shellExec
    command: ["true"]
    stdout: StdioCollector { waitForEnd: true }
  }

  function exec(argv) {
    shellExec.command = argv
    shellExec.running = true
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

  function wtype(args) {
    exec([Quickshell.env("MCDC_WTYPE")].concat(args))
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

    // ---------- Service before PAM is configured ----------
    step(200, function () {
      if (service.beginLock() !== false) throw "beginLock without PAM should return false"
      if (ipc.lock() !== "missing-pam") throw "lock() without PAM should report missing-pam"
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

    step(300, function () {
      // diagnostic: confirm the stub PATH is visible to spawned processes
      exec(["bash", "-c", "command -v hyprctl > \"" + Quickshell.env("MCDC_STUB_STATE") + "/path-dump\" 2>&1; command -v fprintd-list >> \"" + Quickshell.env("MCDC_STUB_STATE") + "/path-dump\" 2>&1"])
    })

    started = Date.now()
    runner.start()
  }
}
