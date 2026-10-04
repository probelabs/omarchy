---
component: menu
paths:
  - shell/plugins/menu/**
  - shell/services/AppSearch.js
  - shell/plugins/emojis/EmojiSearch.js
  - bin/omarchy-menu*
  - test/shell.d/menu-*
  - test/shell.d/emojis-test.sh
owner: omarchy proof layer maintainers (component "menu" in specs/software)
updated: 2026-10-04
rules:
  - RG-MENU-1 host-dependent tests pin the host
  - RG-MENU-2 one list, one order
  - RG-MENU-3 names are arbitrary Unicode
  - RG-MENU-4 source-extracting tests fail loudly
  - RG-MENU-5 asynchronous loads
# Provenance only. Never rendered into review prompts: a review reads the body below, not this front matter.
sources:
  - "RG-MENU-1, RG-MENU-2 - two points an external review raised on the Apps-list ordering change omacom/omarchy#14155
    (2026-10) that the proof review had missed. Its sort test assumed one locale, and names equal under the sort key
    came out in a different order on two paths."
---
# Review guidance: the menu component (menus, the Apps list, app search, emoji search)

1. **RG-MENU-1. Host-dependent tests must pin the host.** A test whose result depends on settings of the machine
   that runs it (locale and collation, timezone, environment variables, the runtime's build options such as ICU
   data) must set them itself, or assert only what holds under every value. For a test that sorts, compares or
   formats text, run it under at least one collation locale whose rules differ from English before accepting that
   "it passes here".
2. **RG-MENU-2. One list, one order.** When two code paths present the same items to users (the menu itself, the
   list handed to plugins, search results, a cached copy), their sort keys and their tie-breaks must agree. Compare
   the paths on inputs that are equal under the primary key: case variants, Unicode normalization variants
   (composed vs decomposed), duplicate names, equal scores. Each path being deterministic on its own is not enough.
3. **RG-MENU-3. Names are arbitrary Unicode.** Labels come from desktop entries and user files in the user's
   language: any script, combining marks, leading symbols or digits, empty or whitespace-only values. Comparisons
   and matching must not assume ASCII.
4. **RG-MENU-4. Tests that extract code from source must fail loudly.** Menu tests often pull a function out of
   Menu.qml or a script with a regex and run it under node. The test must fail when the extraction no longer
   matches; it must not silently test a fallback, a stub or a copy.
5. **RG-MENU-5. Asynchronous loads.** Menu files, providers and caches load asynchronously and can reload live.
   State a change adds must be correct in every load order and on a reload, not only in the order observed on one
   machine.
