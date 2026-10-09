import QtQuick
import Quickshell
import "plugins/lock" as LockPlugin

// Drives the lock service's real session lock and prints the password field
// as keystrokes arrive. The shell script owns the compositor and the keyboards.
// Reproduces: KI-261009-MKK2
Item {
  id: root
  LockPlugin.Service { id: service; shell: null }

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: console.log("PROBE event=" + service.lastEvent + " pw=" + JSON.stringify(service.enteredPassword))
  }

  Timer {
    interval: 40000
    running: true
    onTriggered: Qt.quit()
  }

  Component.onCompleted: console.log("PROBE ready")

  Connections {
    target: service
    function onPasswordPamConfiguredChanged() {
      if (!service.passwordPamConfigured) return
      console.log("PROBE beginLock=" + service.beginLock())
    }
  }
}
