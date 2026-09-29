import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons

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
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
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

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  readonly property var batteryService: shell && shell.services ? shell.firstPartyServiceFor("omarchy.battery") : null
  readonly property bool powerSaverActive: batteryService ? batteryService.powerSaverOnBattery : false

  // Implements: SYS-REQ-260912-T0XP
  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
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
    fingerprintRetryTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  // Implements: SW-REQ-260912-J8SX
  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
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
    if (!root.locked && !lockRequested) return

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

  // Implements: SYS-REQ-260912-T0XP
  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    if (!fingerprintPam.start()) {
      fingerprintAuthenticating = false
    }
  }

  // Implements: SYS-REQ-260912-T0XP
  function handleFingerprintFinished(result) {
    fingerprintAuthenticating = false

    if (!lockRequested) return
    if (result === PamResult.Success) {
      finishUnlock()
    } else if (fingerprintConfigured) {
      fingerprintRetryTimer.restart()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    // Implements: SYS-REQ-260912-T0XP
    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    // Implements: SYS-REQ-260912-T0XP
    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

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
      color: Color.background

      LockView {
        id: lockView
        anchors.fill: parent
        backgroundPath: root.backgroundPath
        videoPosterPath: root.videoPosterPath
        backgroundVersion: root.backgroundVersion
        fingerprintConfigured: root.fingerprintConfigured
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
      fingerprintConfigured: root.fingerprintConfigured
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

    // Implements: SYS-REQ-260912-T0XP
    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    // Implements: SYS-REQ-260912-T0XP
    onError: function(error) {
      root.fingerprintAuthenticating = false
      if (root.lockRequested && root.fingerprintConfigured) fingerprintRetryTimer.restart()
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
    interval: 250
    repeat: false
    // Implements: SYS-REQ-260912-T0XP
    onTriggered: root.startFingerprint()
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
        root.videoPosterPath = exitCode === 0 ? String(posterOutput.text || "").trim() : ""
      }
    }
  }

  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -qi finger; then echo yes; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    // Implements: SYS-REQ-260912-T0XP
    onExited: {
      root.fingerprintConfigured = String(fingerprintCheckStdout.text || "").trim() === "yes"
      if (root.lockRequested && root.fingerprintConfigured) root.startFingerprint()
      else if (!root.fingerprintConfigured && fingerprintPam.active) fingerprintPam.abort()
    }
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
      if (!root.locked && !root.beginLock()) return "failed"
      return "ok"
    }

    // Implements: SYS-REQ-260912-FRG0
    function isLocked(): string {
      return root.locked ? "true" : "false"
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
