extends RefCounted

## Local test log only. Events stay in user:// and are never sent.

const MAX_EVENTS := 200
const PATH := "user://analytics_log.json"

var path := PATH
var install_id := ""
var session_id := ""
var app_version := "0.1.0"
var events: Array = []
var attempts := {}
var seen := {}


func boot() -> void:
	app_version = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_load()
	if install_id == "":
		install_id = "local-%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	session_id = "s-%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	_save()


func track(event_name: String, params: Dictionary, dedupe_key := "") -> bool:
	if dedupe_key != "" and bool(seen.get(dedupe_key, false)):
		return false
	if dedupe_key != "":
		seen[dedupe_key] = true
	events.append({
		"name": event_name,
		"params": params,
		"ts_utc": Time.get_datetime_string_from_system(true),
		"session_id": session_id,
		"app_version": app_version,
		"install_id": install_id,
	})
	while events.size() > MAX_EVENTS:
		events.pop_front()
	_save()
	return true


func next_attempt(level_id: int) -> int:
	var key := str(level_id)
	var count := int(attempts.get(key, 0)) + 1
	attempts[key] = count
	_save()
	return count


## Placeholder only. A real crash SDK is a later choice.
func note_crash(message: String) -> void:
	track("crash_or_anr", {"message": message, "placeholder": true})


func recent_text(limit: int) -> String:
	var lines: PackedStringArray = []
	lines.append("Local test log. Nothing is sent off this device.")
	lines.append("Crash reporting is a local placeholder until a SDK is chosen.")
	var start := maxi(0, events.size() - limit)
	for i in range(start, events.size()):
		var row: Dictionary = events[i]
		lines.append("%s  %s" % [str(row.get("ts_utc", "")), str(row.get("name", ""))])
	if lines.size() == 2:
		lines.append("No events yet.")
	return "\n".join(lines)


func _save() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"install_id": install_id,
		"events": events,
		"attempts": attempts,
		"seen": seen,
	}))


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	install_id = str(parsed.get("install_id", ""))
	var raw_events: Variant = parsed.get("events", [])
	if typeof(raw_events) == TYPE_ARRAY:
		events = raw_events
	var raw_attempts: Variant = parsed.get("attempts", {})
	if typeof(raw_attempts) == TYPE_DICTIONARY:
		attempts = raw_attempts
	var raw_seen: Variant = parsed.get("seen", {})
	if typeof(raw_seen) == TYPE_DICTIONARY:
		seen = raw_seen
