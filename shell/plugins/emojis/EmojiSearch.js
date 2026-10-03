function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  return String((item && item.k) || "").toLowerCase()
}

// A keyword ends at anything that is not a letter, a digit or an apostrophe:
// a space, the "_" in "broken_heart", the "-" in "t-rex", the ":" in
// "man: beard", the quotes in "“reserved”". A letter is any character that has
// a case, "é" too (the shipped keywords are English), and "o’clock" stays one
// word.
function isWordChar(c) {
  return (c >= "0" && c <= "9") || c === "'" || c === "\u2019" || c.toLowerCase() !== c.toUpperCase()
}

// 0 when the query is a whole keyword, 1 when a keyword starts with it, 2 when
// it only appears inside one, -1 when it does not appear. An empty query
// matches everything as a whole.
function matchRank(text, needle) {
  if (!needle) return 0
  var rank = -1
  for (var at = text.indexOf(needle); at >= 0 && rank !== 0; at = text.indexOf(needle, at + 1)) {
    var starts = at === 0 || !isWordChar(text.charAt(at - 1))
    var end = at + needle.length
    var ends = end === text.length || !isWordChar(text.charAt(end))
    var found = starts ? (ends ? 0 : 1) : 2
    if (rank < 0 || found < rank) rank = found
  }
  return rank
}

// Implements: SW-REQ-261004-H41S
function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, Math.ceil(max))
  if (max === 0) return []

  // The picker selects the first result, so whole keywords come first, then
  // keyword starts, then matches inside a word: "ok" finds the OK hand before
  // the broken heart. Within each group the file order stays.
  var groups = [[], [], []]

  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    var rank = matchRank(keywordText(item), needle)
    if (rank < 0) continue
    groups[rank].push(item)
    if (groups[0].length >= max) break
  }

  return groups[0].concat(groups[1], groups[2]).slice(0, max)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis
  }
}
