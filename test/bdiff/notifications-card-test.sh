#!/bin/bash

# Proof-side witness for SW-REQ-261004-DHZ3 and SYS-REQ-261004-74P8 (mirror
# only; not part of the upstream change). It replays the notification inputs
# of the behaviour-diff corpus through test/bdiff/harness.mjs, which loads this
# checkout's real shell/plugins/notifications/NotificationLogic.js under
# node:vm and calls sanitizeBody and styledBody the way NotificationCard.qml
# calls them. It asserts the exact card lines the harness prints.
#
# No audit test command runs this file: the menu-shell catch-all runs only
# test/shell.d/menu-*-test.sh, and a notifications test does not belong under
# a menu name. The behaviour-diff run executes the same inputs at the base and
# at the head.

# Verifies: SW-REQ-261004-DHZ3, SYS-REQ-261004-74P8
# mcdc:witness-out-of-process
#mcdc:ignore:defensive SW-REQ-261004-DHZ3: chromium_sender=T, message_after_link_kept=F, origin_link_at_start=T => FALSE -- once the origin link matches, sanitizeBody returns the image-stripped body without that link and the white space after it, and runs no other strip on it; a body that loses more needs that early return removed [reviewed: REVIEW-261003-SE8G]
#mcdc:ignore:defensive SYS-REQ-261004-74P8: page_message_shown=F, web_notification_received=T => FALSE -- for a Chromium web notification whose body starts with an origin link the cleanup recognises, sanitizeBody returns the body after that link and its white space at once and runs no other strip; a message that loses its first word needs that early return removed [reviewed: REVIEW-261003-SE8G]

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../shell.d" && pwd)/base-test.sh"

require_command node

HARNESS="$ROOT/test/bdiff/harness.mjs"
CORPUS="$ROOT/test/bdiff/corpus/lifecycle"

# Each case: description, input, the exact card lines the harness prints
# (body-line-shown and card-text; the sanitizeBody lines are left out).
CASES=(
  # MCDC SW-REQ-261004-DHZ3: chromium_sender=T, message_after_link_kept=T, origin_link_at_start=T => TRUE
  # MCDC SYS-REQ-261004-74P8: page_message_shown=T, web_notification_received=T => TRUE
  # STK-REQ-261004-6HJ2:nominal:nominal
  'a Chromium web notification keeps a web address that starts the message'
  notify-link-url-first.events
  'notification 1 app="Chromium" body-line-shown=true card-text="github.com/omacom/omarchy can you review?"
notification 2 app="Chromium" body-line-shown=true card-text="https://github.com/omacom/omarchy/pull/1 is ready"
notification 3 app="Chromium" body-line-shown=true card-text="www.example.com is down again"'

  'a Chromium web notification keeps a dotted first word of the message'
  notify-link-dotted-word.events
  'notification 1 app="Chromium" body-line-shown=true card-text="Node.js 24 is out, upgrade today"
notification 2 app="Chromium" body-line-shown=true card-text="README.md has new install steps"'

  'Brave, Chrome and Edge web notifications keep the start of the message'
  notify-link-other-browsers.events
  'notification 1 app="Brave Browser" body-line-shown=true card-text="github.com/omacom/omarchy can you review?"
notification 2 app="Google Chrome" body-line-shown=true card-text="Node.js 24 is out"
notification 3 app="" body-line-shown=true card-text="teams.microsoft.com link inside"'

  'a Chromium web notification with a plain message loses only the origin link and the white space after it'
  notify-link-plain-message.events
  'notification 1 app="Chromium" body-line-shown=true card-text="See you at 5"
notification 2 app="Chromium" body-line-shown=true card-text="e.g. bring the slides"
notification 3 app="Chromium" body-line-shown=true card-text="Two lines<br/>of message"
notification 4 app="Chromium" body-line-shown=true card-text="indented reply"'

  'without a link, a Chromium body loses only its leading plain-text origin'
  notify-plain-origin.events
  'notification 1 app="Chromium" body-line-shown=true card-text="See you at 5"
notification 2 app="Chromium" body-line-shown=true card-text="github.com/omacom/omarchy can you review?"
notification 3 app="Chromium" body-line-shown=true card-text="Message body"'

  # The two cleanup expressions keep what they match: Unicode white space
  # around the link and after a plain-text origin, a link only at the start,
  # and <a\b not matching a longer tag name.
  'Unicode white space, a link inside the text and an abbr tag clean as before'
  notify-link-space-anchor.events
  'notification 1 app="Chromium" body-line-shown=true card-text="See you at 5"
notification 2 app="Chromium" body-line-shown=true card-text="See you at 5"
notification 3 app="Chromium" body-line-shown=true card-text="See you at 5"
notification 4 app="Chromium" body-line-shown=true card-text="Reply to <a href=\"https://app.slack.com/\">app.slack.com</a> today"
notification 5 app="Chromium" body-line-shown=true card-text="<abbr title=\"x\">chat.example.com</abbr><br/><br/>See you at 5"'

  # MCDC SW-REQ-261004-DHZ3: chromium_sender=T, message_after_link_kept=F, origin_link_at_start=F => TRUE [no-action: the link content localhost:8123, 127.0.0.1:8123, bücher.de, foo.x1, a.b or a <b> element is not what the origin-link expression matches, so nothing is removed; the card text still starts with the link]
  'an origin link the cleanup does not match stays in the card'
  notify-link-origin-kept.events
  'notification 1 app="Chromium" body-line-shown=true card-text="<a href=\"http://localhost:8123/\">localhost:8123</a><br/><br/>github.com/omacom/omarchy can you review?"
notification 2 app="Chromium" body-line-shown=true card-text="<a href=\"http://127.0.0.1:8123/\">127.0.0.1:8123</a><br/><br/>Node.js 24 is out"
notification 3 app="Chromium" body-line-shown=true card-text="<a href=\"https://xn--bcher-kva.de/\">bücher.de</a><br/><br/>Node.js 24 is out"
notification 4 app="Chromium" body-line-shown=true card-text="<a href=\"http://foo.x1/\">foo.x1</a><br/><br/>Node.js 24 is out"
notification 5 app="Chromium" body-line-shown=true card-text="<a href=\"http://a.b/\">a.b</a><br/><br/>Node.js 24 is out"
notification 6 app="Chromium" body-line-shown=true card-text="<a href=\"https://web.whatsapp.com/\"><b>web.whatsapp.com</b></a><br/><br/>Node.js 24 is out"'

  # MCDC SW-REQ-261004-DHZ3: chromium_sender=F, message_after_link_kept=F, origin_link_at_start=T => TRUE [no-action: Slack is not a Chromium-based browser, so the origin cleanup does not run; the card text still starts with the link, and a leading web address stays]
  # MCDC SYS-REQ-261004-74P8: page_message_shown=F, web_notification_received=F => TRUE [no-action: Slack and notify-send are not a browser, so no origin is removed; the card text is the body as sent]
  'a notification from an app that is not a browser keeps its body as sent'
  notify-other-app.events
  'notification 1 app="Slack" body-line-shown=true card-text="<a href=\"https://app.slack.com/\">app.slack.com</a><br/><br/>github.com/omacom/omarchy can you review?"
notification 2 app="Slack" body-line-shown=true card-text="https://example.com/path Message body"
notification 3 app="notify-send" body-line-shown=true card-text="Node.js 24 is out"'

  'a web notification with an empty message shows no body line'
  notify-link-empty-message.events
  'notification 1 app="Chromium" body-line-shown=false card-text=""
notification 2 app="Chromium" body-line-shown=false card-text=""'
)

for ((i = 0; i < ${#CASES[@]}; i += 3)); do
  description=${CASES[i]}
  expected=${CASES[i + 2]}
  # A harness LOAD-ERROR, MISSING or ERROR line, or a non-zero exit, fails the
  # case by name with the whole harness output.
  out=$(LC_ALL=C.UTF-8 node "$HARNESS" "$ROOT" "$CORPUS/${CASES[i + 1]}" 2>&1) && rc=0 || rc=$?
  got=$(printf '%s\n' "$out" | grep -E '^notification [0-9]+ app=' || true)
  if [[ $rc -eq 0 && $got == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "harness exit: $rc
expected: $expected
got:      $got
harness output:
$out"
  fi
done

# The plain-text branch of sanitizeBody, asserted on its own result: without an
# origin link, the leading plain-text origin chat.example.com:8123 and its blank
# line go and the message after it stays whole, including a web address it
# starts with.
# MCDC SW-REQ-261004-DHZ3: chromium_sender=T, message_after_link_kept=F, origin_link_at_start=F => TRUE [no-action: no origin link, so the link replacement removes nothing; sanitizeBody returns the plain-text branch result asserted below: "See you at 5" and "github.com/omacom/omarchy can you review?", the message after the plain-text origin]
description='without an origin link, sanitizeBody keeps the message after the plain-text origin'
out=$(LC_ALL=C.UTF-8 node "$HARNESS" "$ROOT" "$CORPUS/notify-plain-origin.events" 2>&1) && rc=0 || rc=$?
got=$(printf '%s\n' "$out" | grep -E '^notification [12] sanitizeBody=' || true)
expected='notification 1 sanitizeBody="See you at 5"
notification 2 sanitizeBody="github.com/omacom/omarchy can you review?"'
if [[ $rc -eq 0 && $got == "$expected" ]]; then
  pass "$description"
else
  fail "$description" "harness exit: $rc
expected: $expected
got:      $got
harness output:
$out"
fi
