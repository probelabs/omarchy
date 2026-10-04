---
component: notifications
paths:
  - shell/plugins/notifications/**
  - bin/omarchy-notification-*
  - test/shell.d/notifications-test.sh
owner: omarchy proof layer maintainers (shell/plugins/notifications; not yet a requirement component on quattro-proof)
updated: 2026-10-04
rules:
  - RG-NOTIF-1 the sender's real format
  - RG-NOTIF-2 sequential rewrites see what earlier ones left
  - RG-NOTIF-3 markup stays inert
  - RG-NOTIF-4 stored notifications replay through current code
  - RG-NOTIF-5 host-dependent tests pin the host
# Provenance only. Never rendered into review prompts: a review reads the body below, not this front matter.
sources:
  - RG-NOTIF-1..5 generalised from the menu component's escapes (RG-MENU-1, input-domain lessons) and the notification
    sanitizer's history (image-tag and newline rewrites measured against Qt); written before review, without the answer
    to any one change
---
# Review guidance: the notifications component (server, toasts, history replay)

1. **RG-NOTIF-1. Check against what the sender really sends.** Notification bodies come from other programs over
   D-Bus (browsers, chat apps, `notify-send`, the shell's own scripts), shaped by the capabilities the server advertises
   (body-markup, body-hyperlinks, images, actions). A change that parses, strips or rewrites a body must hold for the
   sender's actual format under the advertised capabilities: the exact separators, escaping and ordering. Tests should
   use that exact format, not a simplified string.
2. **RG-NOTIF-2. Sequential rewrites see what earlier ones left.** When several rules rewrite the same text one after
   another, check what each later rule receives once an earlier one has run. A rule written for one form of the input
   must not fire on the remainder of another form, and the order of the rules must not change the result for inputs
   both could match.
3. **RG-NOTIF-3. Markup stays inert.** Bodies are rendered as Qt StyledText. Any change must keep the invariant that
   nothing in a body can make the card fetch a resource or render markup the sanitizer did not decide to keep, including
   after newline and entity rewrites. Check the final string Qt parses, not an intermediate one.
4. **RG-NOTIF-4. Stored notifications replay through current code.** History keeps bodies as they arrived and renders
   them with the code of the running shell. A rendering change applies to notifications stored before the change too;
   state that, and check that old stored shapes still render.
5. **RG-NOTIF-5. Host-dependent tests pin the host.** A test whose result can depend on the machine (locale and
   collation, time zone, environment, the runtime's build options) sets those itself or asserts only what holds under
   every value. A claim about host settings needs an executed counterexample (`LC_ALL=… <test>`), not reasoning alone.
