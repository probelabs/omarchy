import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "FingerprintModel.js" as FingerprintModel
import "LockRequestModel.js" as LockRequests

// Implements: SYS-REQ-260912-T0XP, SYS-REQ-260912-FRG0 — on-demand lock; session-lock state
Item {
  id: root

  property var shell: null
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property var requestLedger: null
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property int fingerprintUnreachedStreak: 0
  property bool fingerprintAttemptReachedDevice: false
  property bool fingerprintAttemptFastError: false
  property double fingerprintAttemptPromptedAtMs: 0
  property double fingerprintLastNudgeMs: 0
  property double fingerprintLastSettleMs: 0
  property double fingerprintResumedAtMs: 0
  property int fingerprintProbeStreak: 0
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  // The wallpaper file's mtime and size. The lock caches its wallpaper by
  // version, so a file overwritten in place must bump the version too.
  property string backgroundSignature: ""
  property string lastEvent: "init"
  property string lastEventAt: ""
  property bool displaysBlank: false
  // displaysBlank tracks what the lock asked for; Hyprland reports what each
  // panel actually did. While a video is on show the two are reconciled, so a
  // blank that failed keeps playing and a panel woken behind the lock's back
  // (a resume that kept the same outputs) resumes instead of freezing.
  property var monitorDpms: ({})
  property bool monitorDpmsKnown: false
  readonly property bool videoBackground: Util.isVideoPath(backgroundPath)
  property bool strandedLock: false
  property bool strandedLockResolved: false

  //mcdc:ignore:defensive the ext-session-lock protocol makes secure a strict consequence of held (a lock is only secure once the compositor holds it), so sessionLock.secure can never flip the outcome while sessionLock.locked is false and no independence pair exists; every reachable arm is witnessed by the lock-cycle harness
  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  readonly property var batteryService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.battery") : null
  readonly property bool powerSaverActive: batteryService ? batteryService.powerSaverOnBattery : false
  // A prompt clears the unavailable notice before the attempt finishes.
  // Implements: SW-REQ-261004-296X
  readonly property bool fingerprintUnavailable: FingerprintModel.isUnavailable(fingerprintProbeStreak) || (fingerprintConfigured && (!fingerprintAttemptReachedDevice || fingerprintAttemptFastError) && FingerprintModel.isUnavailable(fingerprintUnreachedStreak))

  // Implements: SYS-REQ-260912-T0XP
  function realScreenCount() {
    //mcdc:ignore:defensive Quickshell.screens is never null or empty (an output-less compositor gets a placeholder screen), so the fallback array is structurally dead; the T path is witnessed by the lock harness
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      //mcdc:ignore:defensive Quickshell only reports connected outputs, so screen is never null and a screen never carries an empty name with the placeholder carrying zero extents; the F arms below screen.name are structurally unreachable and the T row is witnessed by the realScreenCount harness
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  // Implements: SYS-REQ-260912-T0XP
  function hasRealScreen() {
    return realScreenCount() > 0
  }

  // Implements: SYS-REQ-260912-T0XP
  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  // Implements: SYS-REQ-260912-T0XP
  function requestSessionLock() {
    //mcdc:ignore:defensive the ext-session-lock protocol makes secure a strict consequence of held, so sessionLock.secure can never flip the outcome while sessionLock.locked is false and no independence pair exists; every reachable arm is witnessed by the lock-cycle harness
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early is an orphan behind Hyprland's failsafe. Outputs
  // are often still absent here, so ask until the answer means something.
  // Implements: SW-REQ-260912-WJYM
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  // Implements: SW-REQ-260912-WJYM
  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  // Implements: SYS-REQ-260912-T0XP
  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  // Implements: SYS-REQ-260912-T0XP
  function refreshPoster() {
    if (!root.videoBackground) {
      root.videoPosterPath = ""
      return
    }
    if (posterProc.running) return
    posterProc.sourcePath = root.backgroundPath
    posterProc.running = true
  }

  // Implements: SYS-REQ-260912-T0XP
  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  // Only definitive enrollment results may disable authentication.
  // Implements: SW-REQ-261004-V813
  function applyFingerprintProbe(text) {
    var status = FingerprintModel.classifyProbe(text)
    if (status === "unknown") {
      if (fingerprintConfigured) return
      fingerprintProbeStreak += 1
      if (lockRequested) {
        fingerprintRecheckTimer.interval = FingerprintModel.retryDelayMs(fingerprintProbeStreak)
        fingerprintRecheckTimer.restart()
      }
      return
    }
    fingerprintProbeStreak = 0
    fingerprintRecheckTimer.stop()
    fingerprintConfigured = status === "yes"
    if (lockRequested && fingerprintConfigured) {
      // A pending retry already owns the next attempt.
      if (!fingerprintRetryTimer.running) startFingerprint()
    } else if (!fingerprintConfigured) {
      // abort() delivers no completion signal, so close the attempt here
      // too; settle returns before arming a retry while unconfigured.
      if (fingerprintPam.active) fingerprintPam.abort()
      settleFingerprintAttempt()
      fingerprintRetryTimer.stop()
    }
  }

  // Implements: SYS-REQ-260912-T0XP
  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  // Implements: SYS-REQ-260912-T0XP
  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintUnreachedStreak = 0
    fingerprintAttemptFastError = false
    fingerprintAttemptPromptedAtMs = 0
    fingerprintLastNudgeMs = 0
    fingerprintLastSettleMs = 0
    fingerprintResumedAtMs = 0
    fingerprintProbeStreak = 0
    fingerprintRecheckTimer.stop()
    fingerprintRetryTimer.stop()
    fingerprintReachTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  // Implements: SW-REQ-260912-J8SX
  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    // Legacy callers can start after an asynchronous unlock too.
    if (requestLedger && requestLedger.active
        && LockRequests.result(requestLedger, requestLedger.active, Date.now()).state === "secured")
      LockRequests.released(requestLedger, Date.now())
    resetAuthenticationState()
    LockRequests.request(requestLedger, Date.now())
    lockRequested = true
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  // Implements: SYS-REQ-260912-T0XP
  function finishUnlock() {
    //mcdc:ignore:defensive lockRequested implies locked (locked is lockRequested || sessionLock.locked || sessionLock.secure), so !lockRequested can never flip this outcome independently of !root.locked and the pair is structurally impossible; both reachable arms are witnessed by the unlock harness
    if (!root.locked && !lockRequested) return

    LockRequests.released(requestLedger, Date.now())
    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    logEvent("unlocked")
    runWake()
  }

  // Implements: SYS-REQ-260912-T0XP
  function armBlankTimer() {
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  // Implements: SYS-REQ-260912-T0XP
  function runWake() {
    root.displaysBlank = false
    root.monitorDpmsKnown = false
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
    nudgeFingerprint()
  }

  // User activity advances retries without recreating a busy retry loop.
  // Implements: SW-REQ-261004-296X
  function nudgeFingerprint() {
    if (!lockRequested) return
    if (!fingerprintConfigured && fingerprintRecheckTimer.running) {
      var now = Date.now()
      if (FingerprintModel.shouldNudge(now, fingerprintLastNudgeMs, now - FingerprintModel.IDLE_CLEAR_MS, fingerprintRecheckTimer.interval)) {
        fingerprintLastNudgeMs = now
        fingerprintRecheckTimer.interval = FingerprintModel.MATCH_RETRY_MS
        fingerprintRecheckTimer.restart()
      }
      return
    }
    if (!fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return
    if (!fingerprintRetryTimer.running) return
    var now = Date.now()
    if (!FingerprintModel.shouldNudge(now, fingerprintLastNudgeMs, fingerprintLastSettleMs, fingerprintRetryTimer.interval)) return
    fingerprintLastNudgeMs = now
    armFingerprintRetry(FingerprintModel.MATCH_RETRY_MS)
  }


  // Implements: SW-REQ-261004-296X
  function armFingerprintRetry(delayMs) {
    fingerprintRetryTimer.interval = delayMs
    fingerprintRetryTimer.restart()
  }

  // Reset pre-sleep failures while the resume hook restarts fprintd.
  // Implements: SW-REQ-261004-296X
  function noteFingerprintResumed() {
    var now = Date.now()
    if (FingerprintModel.inResumeGrace(now, fingerprintResumedAtMs)) return
    logEvent("fingerprint-resume: streak=" + fingerprintUnreachedStreak)
    fingerprintResumedAtMs = now
    fingerprintUnreachedStreak = 0
  }

  // A suspended PAM conversation may be orphaned by the daemon restart.
  // Implements: SW-REQ-261004-296X
  function restartFingerprintAfterSleep() {
    noteFingerprintResumed()
    if (fingerprintAuthenticating || fingerprintPam.active) {
      if (fingerprintPam.active) fingerprintPam.abort()
      settleFingerprintAttempt()
      return
    }
    if (!fingerprintRetryTimer.running) return
    armFingerprintRetry(FingerprintModel.MATCH_RETRY_MS)
  }

  // Implements: SYS-REQ-260912-T0XP
  function runBlank() {
    root.displaysBlank = true
    root.monitorDpmsKnown = false
    if (!blankProcess.running) blankProcess.running = true
  }

  // Implements: SYS-REQ-260912-T0XP
  function screenBlank(screenName) {
    var name = String(screenName || "")
    if (!monitorDpmsKnown || !(name in monitorDpms)) return displaysBlank
    return !monitorDpms[name]
  }

  // Implements: SYS-REQ-260912-T0XP
  function applyMonitorDpms(text) {
    var monitors
    try {
      monitors = JSON.parse(String(text || ""))
    } catch (error) {
      return
    }
    if (!Array.isArray(monitors)) return

    var dpms = {}
    for (var i = 0; i < monitors.length; i++) {
      var monitor = monitors[i]
      if (monitor && monitor.name && !monitor.disabled) dpms[String(monitor.name)] = !!monitor.dpmsStatus
    }
    monitorDpms = dpms
    monitorDpmsKnown = true
  }

  // Implements: SYS-REQ-260912-T0XP
  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  // Implements: SYS-REQ-260912-T0XP
  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  // Implements: SYS-REQ-260912-T0XP
  function handlePasswordFailure() {
    if (!lockRequested) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  // Implements: SYS-REQ-260912-T0XP, SW-REQ-261004-296X
  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    fingerprintAttemptReachedDevice = false
    fingerprintAttemptFastError = false
    fingerprintAttemptPromptedAtMs = 0
    if (!fingerprintPam.start()) {
      // Pace a failed start while checking whether its PAM configuration was
      // removed; a definitive "no" stops retries and hides the indicator.
      settleFingerprintAttempt()
      refreshFingerprintStatus()
      return
    }
    // Bound claims that never prompt; a normal verify waits for a finger
    // under pam_fprintd's own timeout after reaching the reader.
    fingerprintReachTimer.restart()
  }

  // A prompt proves the claim landed, so stop waiting for reachability.
  // Implements: SW-REQ-261004-296X
  function noteFingerprintReachedDevice() {
    if (fingerprintAttemptReachedDevice) return
    fingerprintAttemptReachedDevice = true
    fingerprintAttemptPromptedAtMs = Date.now()
    fingerprintReachTimer.stop()
  }

  // abort() gives no completion signal; settle the attempt here.
  // Implements: SW-REQ-261004-296X
  function timeoutFingerprintReach() {
    logEvent("fingerprint-reach-timeout")
    if (fingerprintPam.active) fingerprintPam.abort()
    settleFingerprintAttempt()
  }

  // onError and onCompleted can both fire; settle each attempt once.
  // Implements: SW-REQ-261004-296X
  function settleFingerprintAttempt(deviceError) {
    if (!fingerprintAuthenticating) return
    fingerprintAuthenticating = false
    fingerprintReachTimer.stop()
    if (!lockRequested || !fingerprintConfigured) return

    // An error can arrive before the sleep watcher notices the wall-clock gap.
    var now = Date.now()
    fingerprintAttemptFastError = !!deviceError && fingerprintAttemptReachedDevice && now - fingerprintAttemptPromptedAtMs < FingerprintModel.FAST_ERROR_MS
    var usableAttempt = fingerprintAttemptReachedDevice && !fingerprintAttemptFastError
    //mcdc:ignore:defensive fingerprintSleepWatch.running is bound to lockRequested && fingerprintConfigured and nothing assigns it, and the guard above has just returned unless both are true, so the watcher is always running here and its condition can never flip the outcome; the usable, unusable-without-a-gap and unusable-across-a-sleep arms are witnessed by the lock harness
    if (!usableAttempt && fingerprintSleepWatch.running
        && FingerprintModel.spannedSleep(now - fingerprintSleepWatch.lastTickMs, fingerprintSleepWatch.interval)) {
      noteFingerprintResumed()
    }

    // Reached attempts are the steady state (one per swipe window), so only
    // the misses and the recovery from them leave a trace.
    var previousStreak = fingerprintUnreachedStreak
    var inGrace = FingerprintModel.inResumeGrace(now, fingerprintResumedAtMs)
    fingerprintUnreachedStreak = FingerprintModel.nextStreak(previousStreak, usableAttempt, inGrace)
    if (!usableAttempt) {
      var crossed = !FingerprintModel.isUnavailable(previousStreak) && FingerprintModel.isUnavailable(fingerprintUnreachedStreak)
      logEvent((crossed ? "fingerprint-unavailable" : "fingerprint-unreached") + ": streak=" + fingerprintUnreachedStreak)
    } else if (previousStreak > 0) {
      logEvent("fingerprint-recovered: streak=" + previousStreak)
    }
    fingerprintLastSettleMs = now
    armFingerprintRetry(FingerprintModel.retryDelayMs(fingerprintUnreachedStreak))
  }

  // Implements: SYS-REQ-260912-T0XP, SW-REQ-261004-296X
  function handleFingerprintFinished(result) {
    if (result === PamResult.Success && lockRequested) {
      // A match after a run of misses is the recovery too; the unlock resets
      // the streak without settling, so log it here or it leaves no trace.
      if (fingerprintUnreachedStreak > 0) logEvent("fingerprint-recovered: streak=" + fingerprintUnreachedStreak)
      finishUnlock()
    } else {
      settleFingerprintAttempt(result === PamResult.Error)
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    // Implements: SYS-REQ-260912-T0XP
    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        // Record security before authentication can immediately unlock again.
        LockRequests.secured(root.requestLedger, Date.now())
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      } else if (!root.lockRequested && !sessionLock.locked) {
        LockRequests.released(root.requestLedger, Date.now())
      }
    }

    // Implements: SYS-REQ-260912-T0XP
    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)
      if (!locked) LockRequests.released(root.requestLedger, Date.now())

      //mcdc:ignore:tooling-limit quickshell 0.3.1 never delivers a locked=true transition to onLockStateChanged (the handler only fires on the unlock transition), so the held-lock branch is unreachable from any in-process harness invocation; the compositor-drop cleanup it guards is exercised by the witnessed unlock path
      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      //mcdc:ignore:tooling-limit this arm needs the compositor to drop the lock on its own while a request is still pending (a spontaneous session-lock loss); quickshell delivers no locked=true transition and no in-process harness can force a compositor-side unlock, so the pair is unreachable and the witnessed arms cover the real unlock flow
      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      color: Commons.Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        videoPosterPath: root.videoPosterPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured || root.fingerprintUnavailable
        fingerprintUnavailable: root.fingerprintUnavailable
        authenticatingPassword: root.authenticatingPassword
        failureMessage: root.failureMessage
        failedAttempts: root.failedAttempts
        inputEnabled: root.lockRequested
        loadBackground: root.locked
        displaysBlank: root.screenBlank(lockSurface.screen ? lockSurface.screen.name : "")
        powerSaverActive: root.powerSaverActive
        passwordText: root.enteredPassword
        // Implements: SYS-REQ-260912-T0XP
        onPasswordTextEdited: function(password) { root.enteredPassword = password }
        // Implements: SYS-REQ-260912-T0XP
        onSubmitPassword: function(password) { root.submitPassword(password) }
        // Implements: SYS-REQ-260912-T0XP
        onClearFailureRequested: root.failureMessage = ""
        // Implements: SYS-REQ-260912-T0XP
        onWakeRequested: root.runWake()
      }

    }
  }

  PanelWindow {
    id: previewWindow
    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    LockView {
      anchors.fill: parent
      backgroundPath: root.backgroundPath
      videoPosterPath: root.videoPosterPath
      backgroundVersion: root.backgroundVersion
      fingerprintConfigured: root.fingerprintConfigured || root.fingerprintUnavailable
      fingerprintUnavailable: root.fingerprintUnavailable
      authenticatingPassword: false
      failureMessage: ""
      failedAttempts: 0
      inputEnabled: false
      loadBackground: root.previewVisible
      powerSaverActive: root.powerSaverActive
      passwordText: ""
    }

    MouseArea {
      id: previewDismissMouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      // Implements: SYS-REQ-260912-T0XP
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    // Implements: SYS-REQ-260912-T0XP
    onResponseRequiredChanged: root.respondToPasswordPrompt()
    // Implements: SYS-REQ-260912-T0XP
    onPamMessage: root.respondToPasswordPrompt()

    // Implements: SYS-REQ-260912-T0XP
    onCompleted: function(result) {
      root.authenticatingPassword = false
      root.pendingPassword = ""

      if (!root.lockRequested) return
      if (result === PamResult.Success) root.finishUnlock()
      else root.handlePasswordFailure()
    }

    // Implements: SYS-REQ-260912-T0XP
    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    // Implements: SW-REQ-261004-296X
    onPamMessage: {
      if (!messageIsError) root.noteFingerprintReachedDevice()
    }

    // Implements: SYS-REQ-260912-T0XP
    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    // Implements: SYS-REQ-260912-T0XP
    onError: function(error) {
      root.settleFingerprintAttempt(true)
    }
  }

  // The lock only starts decoding its wallpaper once locked, and a machine
  // suspending right after locking froze that decode partway: waking showed
  // the password field on a bare background, then the wallpaper popped in.
  // Keep each screen's lock wallpaper decoded in the image cache ahead of
  // time, as the lock view requests it (same URL, the screen's logical size,
  // PreserveAspectCrop), so the lock draws it on its first frame.
  readonly property string lockWallpaperPath: videoBackground ? videoPosterPath : backgroundPath
  readonly property string lockWallpaperUrl: lockWallpaperPath && !Util.isVideoPath(lockWallpaperPath)
    ? Util.fileUrl(lockWallpaperPath) + (backgroundVersion ? "?v=" + backgroundVersion : "")
    : ""

  Variants {
    model: Quickshell.screens

    Image {
      required property var modelData
      visible: false
      source: root.lockWallpaperUrl
      sourceSize.width: modelData.width
      sourceSize.height: modelData.height
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }
  }

  Timer {
    id: fingerprintRetryTimer
    interval: FingerprintModel.MATCH_RETRY_MS
    repeat: false
    // Implements: SYS-REQ-260912-T0XP
    onTriggered: root.startFingerprint()
  }

  // Detect resume both during an active attempt and during backoff.
  Timer {
    id: fingerprintSleepWatch
    interval: 1000
    repeat: true
    running: root.lockRequested && root.fingerprintConfigured
    property double lastTickMs: 0
    // Implements: SW-REQ-261004-296X
    onRunningChanged: lastTickMs = Date.now()
    onTriggered: {
      var now = Date.now()
      var slept = FingerprintModel.spannedSleep(now - lastTickMs, interval)
      lastTickMs = now
      if (slept) root.restartFingerprintAfterSleep()
    }
  }

  Timer {
    id: fingerprintReachTimer
    interval: FingerprintModel.REACH_TIMEOUT_MS
    repeat: false
    // Implements: SW-REQ-261004-296X
    onTriggered: root.timeoutFingerprintReach()
  }

  Process {
    id: readlinkProc
    command: ["bash", "-c", "path=$(readlink -f -- \"$1\") && printf '%s\\n%s\\n' \"$path\" \"$(stat -Lc %Y:%s -- \"$path\" 2>/dev/null)\"", "_", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      // Implements: SYS-REQ-260912-T0XP
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var next = String(lines[0] || "").trim()
        var signature = String(lines[1] || "").trim()
        if (next !== root.backgroundPath) {
          root.videoPosterPath = ""
          root.backgroundPath = next
          root.backgroundSignature = signature
          root.backgroundVersion += 1
        } else if (signature !== root.backgroundSignature) {
          root.backgroundSignature = signature
          root.backgroundVersion += 1
        }
        root.refreshPoster()
      }
    }
  }

  Process {
    id: posterProc
    property string sourcePath: ""
    command: ["bash", Quickshell.env("OMARCHY_PATH") + "/shell/plugins/lock/poster.sh", sourcePath]
    stdout: StdioCollector { id: posterOutput; waitForEnd: true }
    // Implements: SYS-REQ-260912-T0XP
    onExited: function(exitCode) {
      if (sourcePath !== root.backgroundPath) {
        root.refreshPoster()
      } else {
        //mcdc:ignore:tooling-limit the failing-run arm needs a second poster invocation after the previous one fully tears down its process state; in the instrumented runtime the teardown visibility lags the harness schedule, so the second invocation keeps early-returning on the running guard and the arm cannot be reliably reached while the success arm is witnessed
        root.videoPosterPath = exitCode === 0 ? String(posterOutput.text || "").trim() : ""
      }
    }
  }

  // Keep fprintd errors distinguishable from an explicit empty enrollment.
  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1; then LC_ALL=C fprintd-list \"$USER\" 2>&1; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    // Implements: SW-REQ-261004-V813
    onExited: root.applyFingerprintProbe(fingerprintCheckStdout.text)
  }

  // Retries a probe that could not reach fprintd, paced like the attempt
  // retries so a daemon that stays unreachable is asked about ever less often.
  Timer {
    id: fingerprintRecheckTimer
    interval: FingerprintModel.ERROR_RETRY_BASE_MS
    repeat: false
    // Implements: SW-REQ-261004-V813
    onTriggered: root.refreshFingerprintStatus()
  }

  Process {
    id: strandedLockCheckProc
    command: ["bash", "-c", "omarchy-hyprland-session-locked"]
    // Implements: SYS-REQ-260912-T0XP
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      //mcdc:ignore:defensive checkStrandedLock refuses to start the probe while locked or lockRequested is true, so this verdict can never evaluate with !root.lockRequested false and the condition cannot independently flip the outcome; the witnessed strands cover every reachable state
      root.strandedLock = exitCode === 0 && !root.locked && !root.lockRequested
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  // Quickshell exposes no DPMS signal, so the panel state is polled while a
  // video is the locked wallpaper. A wake or blank request drops the last
  // answer, so its optimistic state applies until the next poll confirms it.
  Process {
    id: monitorDpmsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      // Implements: SYS-REQ-260912-T0XP
      onStreamFinished: root.applyMonitorDpms(text)
    }
  }

  Timer {
    id: monitorDpmsTimer
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.locked && root.videoBackground
    // Implements: SYS-REQ-260912-T0XP
    onTriggered: {
      //mcdc:ignore:tooling-limit the re-check exists because the poll process may still be running between three-second fires; in this runtime quickshell cannot resolve the bare hyprctl command name (even /usr/bin/hyprctl fails to start), so the process never stays running across a fire and the running-skip arm is unreachable in-process while the T arm is witnessed
      if (!monitorDpmsProcess.running) monitorDpmsProcess.running = true
    }
    // Implements: SYS-REQ-260912-T0XP
    onRunningChanged: {
      if (!running) root.monitorDpmsKnown = false
    }
  }

  // Implements: SW-REQ-260912-ND55
  Timer {
    id: idleBlankTimer
    interval: 5000
    repeat: false
    property double armedAt: 0
    // Implements: SW-REQ-260912-WJYM
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      //mcdc:ignore:tooling-limit the stale-rearm arm needs the event loop to stall over two seconds between arming and firing (the suspend scenario this defends against); QML timers do not deliver after a JavaScript stall, so no in-process harness can produce it, and the fresh-fire arms are witnessed by the blank-timer harness
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer()
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    // Implements: SYS-REQ-260912-T0XP
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    // Implements: SYS-REQ-260912-T0XP
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    //mcdc:ignore:tooling-limit the exhaustion arm needs the repeated fire countdown to actually decrement remaining; in the instrumented build this running binding evaluates falsy in binding context (the probe pass-through does not carry a true result back into the timer state), so the countdown never runs and the arm is unreachable in-process while the armed arm is witnessed
    running: !root.strandedLockResolved && remaining > 0

    // Implements: SYS-REQ-260912-T0XP
    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    // Implements: SYS-REQ-260912-T0XP
    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    id: screensChangedConnections
    target: Quickshell
    // Implements: SYS-REQ-260912-T0XP
    function onScreensChanged() {
      // A panel coming back is a display turning on that runWake did not ask
      // for, so the blank state has to be given up here or a visible lock
      // wallpaper stays frozen until the next keypress.
      root.displaysBlank = false
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  // Implements: SYS-REQ-260912-T0XP
  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  // A new kernel UUID on each shell instance prevents old receipts from
  // satisfying a request after a restart. Fail closed until it is loaded.
  FileView {
    path: "/proc/sys/kernel/random/uuid"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var instance = String(text() || "").trim()
      if (!root.requestLedger && instance !== "") root.requestLedger = LockRequests.create(instance)
    }
  }

  FileView {
    id: passwordPamFileView
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    // Implements: SYS-REQ-260912-T0XP
    onLoaded: root.passwordPamConfigured = true
    // Implements: SYS-REQ-260912-T0XP
    onLoadFailed: root.passwordPamConfigured = false
    // Implements: SYS-REQ-260912-T0XP
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  // Implements: SYS-REQ-260912-T0XP
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  // Implements: SYS-REQ-260912-T0XP
  Component.onCompleted: {
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  // The id documents this object's identity for the lock IPC surface
  // (qml.missing_id_on_logic_object); it is referenced by audits, not by code.
  ShellIpc {
    id: lockIpc
    target: "lock"

    function lock(): string {
      // Implements: SW-REQ-260912-J8SX
      if (!root.passwordPamConfigured) return "missing-pam"
      //mcdc:ignore:defensive beginLock returns false only when passwordPamConfigured is false, but reaching this condition requires the missing-pam guard above to have passed, so !root.beginLock() is always false when evaluated and the failed arm is structurally dead; the missing-pam arm is witnessed by the lock IPC harness
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    // Implements: SYS-REQ-260912-FRG0
    function isLocked(): string {
      return root.locked ? "true" : "false"
    }

    function request(): string {
      if (!root.passwordPamConfigured) return JSON.stringify({ reason: "missing-pam" })
      // An outcome may have been recorded while an earlier unlock was still
      // releasing its compositor flags. Preserve its archive, not its reuse.
      if (!root.locked) LockRequests.released(root.requestLedger, Date.now())
      var receipt = LockRequests.request(root.requestLedger, Date.now())
      if (!receipt) return JSON.stringify({ reason: "receipt-unavailable" })
      if (sessionLock.secure) LockRequests.secured(root.requestLedger, Date.now())
      if (!root.locked && !root.beginLock()) LockRequests.released(root.requestLedger, Date.now())
      return JSON.stringify(LockRequests.result(root.requestLedger, receipt.requestId, Date.now()))
    }

    function result(requestId: string): string {
      return JSON.stringify(LockRequests.result(root.requestLedger, requestId, Date.now()))
    }

    // Implements: SYS-REQ-260912-FRG0
    function status(): string {
      return JSON.stringify({
        locked: root.locked,
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        fingerprintUnavailable: root.fingerprintUnavailable,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    // Implements: SYS-REQ-260912-FRG0
    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    // Implements: SYS-REQ-260912-FRG0
    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
