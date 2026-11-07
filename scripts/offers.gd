extends RefCounted

## Local test adapter. This is not a store SDK and not an ad network.
## A completed callback can grant once. Cancel, failure, unavailable, a duplicate
## callback, or a callback from an older level grant nothing.

var busy := false
var next_id := 0
var open_id := -1
var open_placement := ""
var open_level := -1
var open_settled := true
var granted := {}
var no_forced_ads := false
var transactions := {}
var last_break_showed := false
## Production leaves this false. A test may turn it on to check placement rules.
var cadence_enabled := false


func begin_rewarded(placement: String, level_token: int) -> Dictionary:
	if busy:
		return {"ok": false, "id": -1, "reason": "busy"}
	next_id += 1
	busy = true
	open_id = next_id
	open_placement = placement
	open_level = level_token
	open_settled = false
	return {"ok": true, "id": open_id, "reason": ""}


func resolve_rewarded(request_id: int, outcome: String, level_token_now: int) -> Dictionary:
	if request_id != open_id:
		return {"granted": false, "reason": "unknown", "placement": ""}
	if open_settled:
		return {"granted": false, "reason": "duplicate", "placement": open_placement}
	open_settled = true
	busy = false
	if outcome != "completed":
		return {"granted": false, "reason": outcome, "placement": open_placement}
	if open_level != level_token_now:
		return {"granted": false, "reason": "stale", "placement": open_placement}
	if bool(granted.get(str(request_id), false)):
		return {"granted": false, "reason": "duplicate", "placement": open_placement}
	granted[str(request_id)] = true
	return {"granted": true, "reason": "completed", "placement": open_placement}


func purchase(transaction_id: String, outcome: String, consumable: bool, coins_if_completed: int) -> Dictionary:
	if transaction_id == "":
		return {"ok": false, "reason": "invalid", "coins": 0}
	if outcome != "completed":
		return {"ok": false, "reason": outcome, "coins": 0}
	if bool(transactions.get(transaction_id, false)):
		return {"ok": false, "reason": "duplicate", "coins": 0}
	if consumable and coins_if_completed < 0:
		return {"ok": false, "reason": "invalid", "coins": 0}
	transactions[transaction_id] = true
	if consumable:
		return {"ok": true, "reason": "completed", "coins": coins_if_completed}
	no_forced_ads = true
	return {"ok": true, "reason": "completed", "coins": 0}


func restore() -> Dictionary:
	return {"no_forced_ads": no_forced_ads, "coins": 0}


func may_show_interstitial(where: String, break_kind: String) -> bool:
	if no_forced_ads or not cadence_enabled:
		return false
	if where != "break":
		return false
	if break_kind != "completed" and break_kind != "failed":
		return false
	if last_break_showed:
		return false
	return true


func note_break(showed: bool) -> void:
	last_break_showed = showed
