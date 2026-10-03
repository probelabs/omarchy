#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-261003-C9GM
#mcdc:ignore:defensive SW-REQ-261003-C9GM: app_displayable=F, app_listed=T, query_terms_matched=F => FALSE -- sortedEntries skips a missing, NoDisplay, hidden or nameless entry before it scores it, so a non-displayable entry reaches rows.push only if one of those continue statements is removed [reviewed: REVIEW-261003-Q2WS]
#mcdc:ignore:defensive SW-REQ-261003-C9GM: app_displayable=F, app_listed=T, query_terms_matched=T => FALSE -- the displayability skips run before fuzzyScore, so a matching term cannot list an entry those skips rejected [reviewed: REVIEW-261003-Q2WS]
#mcdc:ignore:defensive SW-REQ-261003-C9GM: app_displayable=T, app_listed=T, query_terms_matched=F => FALSE -- fuzzyScore returns -1 when allTermsMatch rejects a term and sortedEntries skips a negative score, so an unmatched entry is listed only if that skip is removed [reviewed: REVIEW-261003-Q2WS]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The app library list (shell/services/AppSearch.js, read by the Apps menu
# through AppLibrary.sortedEntries): an entry is listed exactly when it is
# displayable (a name or an id, not NoDisplay, not hidden by the library) and
# every query term matches it. The row order is not part of this test.
run_node_test <<'JS'
// Verifies: SW-REQ-261003-C9GM
const appSearch = requireFromRoot('shell/services/AppSearch.js')
const listed = (entries, query, hidden) => appSearch.sortedEntries(entries, query, hidden).map(row => row.entry.id)
const entries = [
  { id: 'alpha', name: 'Alpha' },
  { id: 'beta', name: 'Beta', noDisplay: true },
  { id: '', name: '' },
  { id: 'gamma', name: 'Gamma', keywords: ['galaxy'] },
  { id: 'delta', name: 'Delta' },
  { id: 'code', name: 'Visual Studio Code', genericName: 'Text Editor' },
]
const hidden = entry => entry.id === 'delta'

// MCDC SW-REQ-261003-C9GM: app_displayable=T, app_listed=T, query_terms_matched=T => TRUE
assertDeepEqual(listed(entries, '', hidden).sort(), ['alpha', 'code', 'gamma'], 'an empty query lists every displayable app')
assertDeepEqual(listed(entries, 'gal', hidden), ['gamma'], 'a keyword term lists the app it matches')
assertDeepEqual(listed(entries, 'vsc', hidden), ['code'], 'a short term matches the acronym')
assertDeepEqual(listed(entries, 'text vis', hidden), ['code'], 'every term must match, in any field')

// MCDC SW-REQ-261003-C9GM: app_displayable=F, app_listed=F, query_terms_matched=F => TRUE
assert(!listed(entries, 'beta', hidden).includes('beta'), 'a NoDisplay app is not listed, even when the query names it')
assert(!listed(entries, 'delta', hidden).includes('delta'), 'an app the library hides is not listed')
assertDeepEqual(listed([{ id: '', name: '' }], '', null), [], 'an entry with no name and no id is not listed')
assertDeepEqual(listed(entries, 'alpha zzz', hidden), [], 'a query with one unmatched term lists nothing')
JS
