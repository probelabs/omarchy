#!/bin/bash
# Red reproducer for KI-NOTIFY-NO-ORIGIN-FIRST-WORD. Runs the LIVE
# shell/plugins/notifications/NotificationLogic.js under node, the way the
# notification card calls it (sanitizeBody for the body line, styledBody for
# the text it renders), on a body from a Chromium-based app with NO origin in
# front of the message. The correct card text is the whole message.
#   exit 0: ok, every message is kept whole
#   exit 1: DEFECT, a message lost its first word
#   exit 2: SETUP, node or the file is missing
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/notifications/NotificationLogic.js"
[[ -f $F ]] || { echo "SETUP: NotificationLogic.js missing"; exit 2; }
command -v node >/dev/null || { echo "SETUP: node missing"; exit 2; }
node - "$F" <<'JS'
const n = require(process.argv[2])
let defect = false
for (const [app, msg] of [
  ['Chromium', 'Node.js 24 is out'],
  ['Chromium', 'github.com/omacom/omarchy can you review?'],
  ['Google Chrome', 'www.example.com is down again'],
]) {
  const shown = n.styledBody(msg, app, '')
  if (shown === msg) console.log(`ok: ${app} keeps ${JSON.stringify(msg)}`)
  else { console.log(`DEFECT: ${app} body ${JSON.stringify(msg)} shows as ${JSON.stringify(shown)}`); defect = true }
}
// Control: the same message from an app that is not a browser is kept.
const control = n.styledBody('Node.js 24 is out', 'Slack', '')
console.log(`${control === 'Node.js 24 is out' ? 'ok' : 'DEFECT'}: control Slack keeps "Node.js 24 is out"`)
process.exit(defect ? 1 : 0)
JS
