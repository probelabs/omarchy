// Receipts belong to one shell instance and remain valid after authentication.
// Retain completions for thirty wall-clock seconds after release, including reads.
// Keep the active token while its lock remains held and never reuse a token.
// A forward clock jump can expire a receipt early: it becomes unknown and
// callers fail conservatively rather than accepting a different request.
// Implements: SW-REQ-261009-RCPT
function create(instance) {
  return { instance: instance, sequence: 0, active: "", records: {}, order: [] }
}

// Implements: SW-REQ-261009-RCPT
function request(ledger, now) {
  if (!ledger || !ledger.instance) return null
  if (ledger.active) return result(ledger, ledger.active, now)

  var kept = []
  for (var i = 0; i < ledger.order.length; i++) {
    var id = ledger.order[i]
    var record = ledger.records[id]
    if (record.state !== "pending" && now - record.finishedAt >= 30000) delete ledger.records[id]
    else kept.push(id)
  }
  ledger.order = kept
  if (kept.length >= 64) return null

  ledger.sequence += 1
  var requestId = ledger.instance + ":" + ledger.sequence
  ledger.active = requestId
  ledger.records[requestId] = { requestId: requestId, state: "pending" }
  ledger.order.push(requestId)
  return result(ledger, requestId, now)
}

// Implements: SW-REQ-261009-RCPT
function secured(ledger, now) {
  if (!ledger || !ledger.active) return
  var record = ledger.records[ledger.active]
  if (record && record.state === "pending") {
    record.state = "secured"
    record.finishedAt = now
  }
}

// Implements: SW-REQ-261009-RCPT
function released(ledger, now) {
  if (!ledger || !ledger.active) return
  var record = ledger.records[ledger.active]
  if (record && record.state === "pending") {
    record.state = "failed"
  }
  // A caller may join a long-held lock just before authentication releases it.
  // Give that caller the full archived window without changing the outcome.
  if (record) record.finishedAt = now
  ledger.active = ""
}

// Implements: SW-REQ-261009-RCPT
function result(ledger, requestId, now) {
  var record = ledger && Object.prototype.hasOwnProperty.call(ledger.records, requestId) && ledger.records[requestId]
  if (record && requestId !== ledger.active && record.state !== "pending"
      && (now === undefined ? Date.now() : now) - record.finishedAt >= 30000) {
    delete ledger.records[requestId]
    ledger.order.splice(ledger.order.indexOf(requestId), 1)
    record = null
  }
  if (!record) return { requestId: requestId, state: "unknown" }
  return { requestId: record.requestId, state: record.state }
}

if (typeof module !== "undefined") {
  module.exports = { create: create, request: request, secured: secured, released: released, result: result }
}

