extends Control

const PuzzleScript := preload("res://scripts/puzzle.gd")
const ProgressScript := preload("res://scripts/progress.gd")
const Glyph := preload("res://scripts/glyph_button.gd")
const Berth := preload("res://scripts/berth_button.gd")
const SydneyView := preload("res://scripts/sydney_view.gd")
const OffersScript := preload("res://scripts/offers.gd")
const AnalyticsScript := preload("res://scripts/analytics.gd")

const HARBOUR := Color("1b3a4b")
const CREAM := Color("f6efe2")
const INK := Color("1a120f")
const GOLD := Color("f0b429")
const DECK := Color("c4a574")
const DOCK := Color("31464c")
const PALETTE := {
	"coral": Color("e25d45"),
	"teal": Color("1f8a80"),
	"gold": Color("f0b429"),
	"indigo": Color("3d4ec7"),
}
const GLYPHS := {
	"coral": "circle",
	"teal": "square",
	"gold": "triangle",
	"indigo": "diamond",
}

var levels: Array = []
var level_index := 0
var puzzle
var progress = ProgressScript.new()
var offers = OffersScript.new()
var analytics = AnalyticsScript.new()
var level_started_ms := 0
var level_token := 0
var _reward_id := -1
var _pending_kind := ""
var _pending_txn := ""
var _pending_coins := 0
var _pending_consumable := true
var _pending_sku := ""
var event_log: Label
var _doubled := false
var double_button: Button
var last_clear := {}
var deck_height := 0
var sel_kind := ""
var sel_index := -1
var modal_mode := ""

var margin: MarginContainer
var level_label: Label
var title_label: Label
var blurb_label: Label
var status_label: Label
var moves_label: Label
var deck_row: HBoxContainer
var stack_row: HBoxContainer
var hold_button
var hold_button2
var hold_button3
var playing_daily := false
var column_cells: Array = []
var berth_buttons: Array = []

var modal: Control
var interstitial: Control
var modal_title: Label
var modal_body: Label
var star_row: HBoxContainer
var primary_button: Button
var secondary_button: Button
var list_button: Button
var coach: PanelContainer
var coach_label: Label
var coach_lines: PackedStringArray = []
var coach_step := 0

var screens: Control
var play_root: Control
var hub_root: Control
var home_root: Control
var settings_root: Control
var hub_coins: Label
var hub_note: Label
var upgrade_button: Button
var daily_button: Button
var _settings_return := "hub"
var home_list: VBoxContainer
var home_scroll: ScrollContainer
var home_coins: Label
var _list_press := Vector2(-1, -1)
var _list_press_scroll := 0
var settings_note: Label
var sound_button: Button
var haptics_button: Button


func _ready() -> void:
	DisplayServer.window_set_title("Dockside Sort: Cargo Puzzle")
	progress.load_file()
	_load_offers()
	analytics.boot()
	analytics.track("app_open", {
		"session_id": analytics.session_id,
		"app_version": analytics.app_version,
		"country": "unknown",
	})
	if offers.no_forced_ads:
		analytics.track("no_ads_active", {"active": true})
	_build_chrome()
	for path in PuzzleScript.list_level_paths():
		var data: Dictionary = PuzzleScript.load_level(path)
		if not data.is_empty():
			levels.append(data)
	_show_hub()
	resized.connect(_apply_safe_margins)
	_apply_safe_margins()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and margin != null:
		_apply_safe_margins()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode
	if settings_root != null and settings_root.visible:
		if key == KEY_ESCAPE or key == KEY_B:
			_leave_settings()
		elif key == KEY_M:
			_toggle_sound()
		elif key == KEY_N:
			_toggle_haptics()
		return
	if hub_root != null and hub_root.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_1:
			_play_frontier()
		elif key == KEY_S:
			_show_settings()
		elif key == KEY_L or key == KEY_2:
			_show_ships()
		return
	if home_root != null and home_root.visible:
		if key >= KEY_1 and key <= KEY_9:
			_start_level(key - KEY_1)
		elif key == KEY_S:
			_show_settings()
		elif key == KEY_ESCAPE or key == KEY_B:
			_show_hub()
		return
	if modal != null and modal.visible:
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
			_on_primary()
		elif key == KEY_L:
			_show_hub()
		elif key == KEY_ESCAPE and modal_mode == "fail":
			_undo()
		elif key == KEY_ESCAPE and modal_mode == "win":
			_show_hub()
		return
	if coach != null and coach.visible and key == KEY_S:
		_finish_coach()
		return
	if key == KEY_ESCAPE or key == KEY_L:
		_show_hub()
		return
	if key >= KEY_1 and key <= KEY_9:
		_select_column(key - KEY_1)
	elif key == KEY_H:
		_on_hold(0)
	elif key == KEY_J:
		_on_hold(1)
	elif key == KEY_Q:
		_on_berth(0)
	elif key == KEY_W:
		_on_berth(1)
	elif key == KEY_E:
		_on_berth(2)
	elif key == KEY_A:
		_on_berth(3)
	elif key == KEY_U or key == KEY_Z:
		_undo()
	elif key == KEY_R or key == KEY_BACKSPACE:
		_restart()


func _load_current(announce := "") -> void:
	if modal != null:
		modal.visible = false
	sel_kind = ""
	sel_index = -1
	puzzle = PuzzleScript.new()
	puzzle.setup(levels[level_index])
	var level_id := int(puzzle.id)
	progress.clear_temp_for_other(level_id, playing_daily)
	if progress.second_hold:
		puzzle.permanent_slots = 2
	if progress.temp_active(level_id, playing_daily):
		puzzle.extra_slot = true
		puzzle.temp_slot_used = true
	if hold_button2 != null:
		hold_button2.visible = puzzle.permanent_slots >= 2
	if hold_button3 != null:
		hold_button3.visible = puzzle.extra_slot
	level_started_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var attempt_n := analytics.next_attempt(int(puzzle.id))
	analytics.track("level_start", {
		"level_id": int(puzzle.id),
		"attempt_n": attempt_n,
		"chapter": "sydney",
	})
	if playing_daily:
		analytics.track("daily_challenge", {"date": str(progress.observed_day()), "result": "start"})
	if not progress.temp_active(int(puzzle.id), playing_daily):
		analytics.track("assist_offer_shown", {"type": "slot", "source": "coin"}, "slot-coin-%d" % level_token)
		analytics.track("assist_offer_shown", {"type": "slot", "source": "rewarded"}, "slot-reward-%d" % level_token)
	level_label.text = "Daily dock" if playing_daily else "Level %d of %d" % [level_index + 1, levels.size()]
	title_label.text = puzzle.title
	blurb_label.text = puzzle.blurb
	_rebuild_board()
	_begin_coach()
	var budget := "Free undos left: %d. After that, 50 coins or one simulated reward." % puzzle.free_undos_left
	var extra := "Extra hold: 100 coins or one simulated reward, for this unfinished ship only. It caps stars at 2."
	if puzzle.extra_slot:
		extra = "Extra hold is active for this unfinished ship. Undo will not remove it."
	if announce == "":
		_set_status(budget + " " + extra)
	else:
		_set_status(announce + " " + budget)


func _select_column(col: int) -> void:
	if puzzle == null or col < 0 or col >= puzzle.columns.size():
		return
	var stack: Array = puzzle.columns[col]
	if stack.is_empty():
		_set_status("That column is empty.")
		_refresh()
		return
	var empties: int = column_cells[col].size() - stack.size()
	_on_cell(col, empties)


func _on_cell(col: int, row: int) -> void:
	if _modal_blocking():
		return
	var stack: Array = puzzle.columns[col]
	var rows: int = column_cells[col].size()
	if stack.is_empty() or row < rows - stack.size():
		_set_status("Empty cell.")
		return
	if row != rows - stack.size():
		_set_status("Only the top container can move.")
		return
	var token := str(stack[0])
	if PuzzleScript.is_key(token):
		var key_err: String = puzzle.collect_key(col)
		if key_err != "":
			_set_status(key_err)
			return
		sel_kind = ""
		sel_index = -1
		_set_status("Key collected. Locked containers can move.")
		_after_successful_move("key")
		return
	if PuzzleScript.is_locked(token) and puzzle.deck_has_key():
		_set_status("That container is locked. Collect the key first.")
		return
	if sel_kind == "column" and sel_index == col:
		sel_kind = ""
		sel_index = -1
		_set_status("Selection cleared.")
	else:
		sel_kind = "column"
		sel_index = col
		_set_status("%s selected. Tap a stack, or the hold." % puzzle.pretty(PuzzleScript.cargo_color(str(stack[0]))))
		_note_coach("select")
	_refresh()


func _on_berth(berth: int) -> void:
	if _modal_blocking() or puzzle == null:
		return
	if berth < 0 or berth >= puzzle.berths.size():
		return
	if sel_kind == "":
		_set_status("Select a container first.")
		return
	var err := ""
	if sel_kind == "column":
		err = puzzle.move_column_to_berth(sel_index, berth)
	elif sel_kind == "hold":
		err = puzzle.move_hold_to_berth(berth, sel_index)
	if err != "":
		_set_status(err)
		return
	sel_kind = ""
	sel_index = -1
	_after_successful_move()
	_note_coach("stack")


func _on_hold(slot: int = 0) -> void:
	if _modal_blocking() or puzzle == null:
		return
	if slot == 1 and puzzle.permanent_slots < 2:
		return
	if slot == 2 and not puzzle.extra_slot:
		return
	if sel_kind == "column":
		var err: String = puzzle.move_column_to_hold(sel_index, slot)
		if err != "":
			_set_status(err)
			return
		sel_kind = ""
		sel_index = -1
		_after_successful_move("in the hold")
		_note_coach("hold")
		return
	var parked: String = puzzle.hold_color(slot)
	if parked == "":
		_set_status("Select a container, then tap the hold.")
		return
	if sel_kind == "hold" and sel_index == slot:
		sel_kind = ""
		sel_index = -1
		_set_status("Selection cleared.")
	else:
		sel_kind = "hold"
		sel_index = slot
		_set_status("%s in the hold. Tap a stack." % puzzle.pretty(parked))
	_refresh()


func _after_successful_move(how := "stacked") -> void:
	if puzzle.last_shipped != "":
		_set_status("%s shipped." % puzzle.pretty(puzzle.last_shipped))
	elif how == "in the hold":
		_set_status("Parked in the hold.")
	elif how == "key":
		pass
	else:
		_set_status("Stacked.")
	_refresh()
	if puzzle.last_shipped != "" and progress.haptics_on and Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(40)
	if puzzle.is_win():
		if playing_daily:
			last_clear = progress.record_daily_clear()
			last_clear["daily"] = true
			progress.finish_temp()
			analytics.track("daily_challenge", {
				"date": str(progress.observed_day()),
				"result": "clear" if int(last_clear.get("coins", 0)) > 0 else "repeat",
			})
			_show_modal("win")
		else:
			last_clear = progress.record_clear(level_index, int(puzzle.id), levels.size(), puzzle.undos_used, puzzle.undo_limit, puzzle.temp_slot_used)
			last_clear["daily"] = false
			progress.finish_temp()
			var elapsed := int(Time.get_unix_time_from_system() * 1000.0) - level_started_ms
			analytics.track("level_complete", {
				"level_id": int(puzzle.id),
				"stars": int(last_clear.get("stars", 1)),
				"duration_s": maxi(0, elapsed / 1000),
				"undos": puzzle.undos_used,
				"temp_slot_used": puzzle.temp_slot_used,
				"coins_earned": int(last_clear.get("coins", 0)),
			})
			if int(last_clear.get("coins", 0)) > 0:
				analytics.track("assist_offer_shown", {"type": "double_coins", "source": "rewarded"}, "double-%d" % level_token)
			if progress.on_main_clear(int(puzzle.id)):
				progress.stamp_ad()
				analytics.track("ad_impression", {"format": "interstitial", "placement": "main_clear", "simulated": true}, "ad-break-%d" % level_token)
				_show_interstitial()
			else:
				_show_modal("win")
	elif puzzle.is_soft_fail():
		analytics.track("level_fail_soft", {"level_id": int(puzzle.id), "reason": "no_moves"}, "fail-%d" % level_token)
		_show_modal("fail")


func _undo() -> void:
	if puzzle == null:
		return
	if modal != null and modal.visible and modal_mode == "win":
		return
	if puzzle.history.is_empty():
		_set_status("Nothing to undo.")
		return
	if puzzle.free_undos_left <= 0:
		analytics.track("assist_offer_shown", {"type": "undo", "source": "coin"}, "undo-coin-%d" % level_token)
		analytics.track("assist_offer_shown", {"type": "undo", "source": "rewarded"}, "undo-reward-%d" % level_token)
	if puzzle.free_undos_left > 0:
		if not puzzle.undo():
			_set_status("Nothing to undo.")
			return
		puzzle.free_undos_left -= 1
		_after_undo("Free undo. %d left." % puzzle.free_undos_left)
		return
	var before: int = progress.coins
	if not progress.try_spend(ProgressScript.UNDO_PRICE):
		_set_status("Not enough coins. Nothing was spent. Use a simulated reward undo, or restart for free.")
		return
	if not puzzle.undo():
		progress.coins = before
		progress.save_file()
		_set_status("Nothing to undo.")
		return
	analytics.track("assist_accepted", {"type": "undo", "source": "coin"})
	_after_undo("Undo for 50 coins. The coins are not refunded.")


func _after_undo(note: String) -> void:
	sel_kind = ""
	sel_index = -1
	_set_status(note)
	_refresh()
	_note_coach("undo")
	if modal != null and modal.visible and not puzzle.is_soft_fail():
		modal.visible = false


func _restart() -> void:
	if puzzle != null:
		analytics.track("level_fail_soft", {"level_id": int(puzzle.id), "reason": "restart"})
	_load_current("Restarted. Free retry.")


func _next_level() -> void:
	var nxt := level_index + 1
	if playing_daily or nxt >= levels.size():
		playing_daily = false
		_show_hub()
		return
	_start_level(nxt)


func _on_primary() -> void:
	if modal_mode == "win":
		_next_level()
	else:
		_undo()


func _on_secondary() -> void:
	_restart()


func _show_modal(mode: String) -> void:
	modal_mode = mode
	if mode == "win":
		var gained := int(last_clear.get("coins", 0))
		var balance := int(last_clear.get("balance", progress.coins))
		if bool(last_clear.get("daily", false)):
			modal_title.text = "Daily dock clear"
			_paint_stars(0)
			modal_body.text = "+%d coins\nBalance %d\nMain stars and unlocks stay as they were.\nDays change at 00:00 UTC." % [gained, balance]
			primary_button.text = "Port"
			secondary_button.text = "Replay"
		else:
			var stars := int(last_clear.get("stars", 1))
			modal_title.text = "Deck clear"
			_paint_stars(stars)
			modal_body.text = "%d stars\nUndos %d (3-star limit %d)\n+%d coins\nBalance %d" % [stars, puzzle.undos_used, puzzle.undo_limit, gained, balance]
			primary_button.text = "Port" if level_index >= levels.size() - 1 else "Next level"
			secondary_button.text = "Replay"
	else:
		modal_title.text = "No moves left"
		var stuck := "The hold is full and nothing can stack."
		if puzzle.hold == "" or (puzzle.permanent_slots >= 2 and puzzle.hold2 == ""):
			stuck = "Nothing left can move."
		modal_body.text = "%s Undo and Restart stay free. Rewarded undo, a temporary hold, and coin prices are not approved yet." % stuck
		primary_button.text = "Undo"
		secondary_button.text = "Restart"
	if double_button != null:
		var can_double := mode == "win" and not bool(last_clear.get("daily", false)) and int(last_clear.get("coins", 0)) > 0 and not _doubled
		double_button.visible = can_double
		double_button.disabled = false
	secondary_button.visible = true
	star_row.visible = mode == "win" and not bool(last_clear.get("daily", false))
	list_button.visible = mode == "win"
	modal.visible = true


func _paint_stars(filled: int) -> void:
	for i in star_row.get_child_count():
		var pip := star_row.get_child(i) as ColorRect
		pip.color = GOLD if i < filled else Color("c8bfae")


func _start_level(index: int, as_daily := false) -> void:
	if index < 0 or index >= levels.size():
		return
	if not as_daily and not progress.is_unlocked(index):
		return
	level_index = index
	playing_daily = as_daily
	level_token += 1
	_doubled = false
	if hub_root != null:
		hub_root.visible = false
	home_root.visible = false
	settings_root.visible = false
	play_root.visible = true
	_load_current()


func _play_frontier() -> void:
	var index := 0
	for i in levels.size():
		if not progress.is_unlocked(i):
			break
		index = i
		var data: Dictionary = levels[i]
		if progress.best_for(int(data.get("id", i + 1))) == 0:
			break
	_start_level(index)


func _show_hub() -> void:
	if modal != null:
		modal.visible = false
	if play_root != null:
		play_root.visible = false
	if settings_root != null:
		settings_root.visible = false
	if home_root != null:
		home_root.visible = false
	playing_daily = false
	if hub_root != null:
		hub_root.visible = true
	if progress != null:
		var note := progress.on_hub_visit()
		if hub_note != null:
			hub_note.text = note
	_refresh_hub()


func _show_ships() -> void:
	if modal != null:
		modal.visible = false
	if play_root != null:
		play_root.visible = false
	if settings_root != null:
		settings_root.visible = false
	if hub_root != null:
		hub_root.visible = false
	if home_root != null:
		home_root.visible = true
	_rebuild_level_list()


func _show_settings() -> void:
	if home_root != null and home_root.visible:
		_settings_return = "ships"
	else:
		_settings_return = "hub"
	if hub_root != null:
		hub_root.visible = false
	home_root.visible = false
	play_root.visible = false
	settings_root.visible = true
	if modal != null:
		modal.visible = false
	_refresh_settings()


func _toggle_sound() -> void:
	progress.sound_on = not progress.sound_on
	progress.save_file()
	_refresh_settings()


func _toggle_haptics() -> void:
	progress.haptics_on = not progress.haptics_on
	progress.save_file()
	_refresh_settings()


func _load_offers() -> void:
	offers.no_forced_ads = progress.test_no_forced_ads
	offers.transactions = progress.test_transactions.duplicate()


func _store_offers() -> void:
	progress.test_no_forced_ads = offers.no_forced_ads
	progress.test_transactions = offers.transactions.duplicate()
	progress.save_file()


func _mark_no_forced_ads() -> void:
	_pending_kind = "purchase"
	_pending_sku = "no_forced_ads"
	_pending_txn = "noforced-%d" % (offers.next_id + 1)
	_pending_coins = 0
	_pending_consumable = false
	settings_note.text = "Simulated No forced ads, USD 9.99 / AUD 14.99. Local test, not a checkout. Choose a result."


func _arm_pack(sku: String) -> void:
	var pack: Dictionary = ProgressScript.PACKS[sku]
	_pending_kind = "purchase"
	_pending_sku = sku
	_pending_txn = "pack%s-%d" % [sku, offers.next_id + 1]
	_pending_coins = int(pack["coins"])
	_pending_consumable = true
	settings_note.text = "Simulated pack %s, %d coins, USD %s / AUD %s. Local test, not a checkout. Choose a result." % [sku, _pending_coins, pack["usd"], pack["aud"]]


func _arm_reward_undo() -> void:
	if puzzle == null or puzzle.history.is_empty():
		_set_status("Nothing to undo.")
		return
	var begun: Dictionary = offers.begin_rewarded("undo", level_token)
	if not bool(begun.get("ok", false)):
		_set_status("The local test provider is busy. Nothing was spent.")
		return
	progress.stamp_ad()
	analytics.track("ad_impression", {"format": "rewarded", "placement": "undo", "simulated": true})
	_pending_kind = "undo"
	_reward_id = int(begun.get("id", -1))
	_set_status("Simulated reward undo is showing. Choose a result in Settings. Cancel spends nothing.")


func _buy_temp() -> void:
	if puzzle == null:
		return
	var result: Dictionary = progress.buy_temp(int(puzzle.id), playing_daily)
	if bool(result.get("ok", false)):
		puzzle.extra_slot = true
		puzzle.temp_slot_used = true
		analytics.track("assist_accepted", {"type": "slot", "source": "coin"})
		_set_status("Extra hold is active for this unfinished ship. Undo will not remove it.")
		_refresh()
	elif str(result.get("reason", "")) == "active":
		_set_status("The extra hold is already active. It was not bought again.")
	else:
		_set_status("Not enough coins. Nothing was spent.")


func _arm_reward_temp() -> void:
	if puzzle == null:
		return
	if progress.temp_active(int(puzzle.id), playing_daily):
		_set_status("The extra hold is already active.")
		return
	var begun: Dictionary = offers.begin_rewarded("temp_hold", level_token)
	if not bool(begun.get("ok", false)):
		_set_status("The local test provider is busy. Nothing was spent.")
		return
	progress.stamp_ad()
	analytics.track("ad_impression", {"format": "rewarded", "placement": "temp_hold", "simulated": true})
	_pending_kind = "temp"
	_reward_id = int(begun.get("id", -1))
	_set_status("Simulated extra hold. One unfinished level, then it clears. Choose a result in Settings.")


func _restore_test_entitlement() -> void:
	var before: int = progress.coins
	progress.load_file()
	_load_offers()
	var restored: Dictionary = offers.restore()
	settings_note.text = "Restored the local test entitlement (%s). Coins stayed %d." % ["on" if bool(restored.get("no_forced_ads", false)) else "off", progress.coins]
	if progress.coins != before or int(restored.get("coins", 0)) != 0:
		settings_note.text = "Restore tried to change coins."


func _start_test_reward() -> void:
	var begun: Dictionary = offers.begin_rewarded("demo", level_token)
	if not bool(begun.get("ok", false)):
		settings_note.text = "The local test provider is busy. No reward was granted."
		return
	progress.stamp_ad()
	analytics.track("ad_impression", {"format": "rewarded", "placement": "demo", "simulated": true})
	_pending_kind = "reward"
	_reward_id = int(begun.get("id", -1))
	settings_note.text = "Simulated reward is showing. Local test, not an ad network. Choose one result."


func _finish_test_reward(outcome: String) -> void:
	if _pending_kind == "purchase":
		var before_purchase: int = progress.coins
		var bought: Dictionary = offers.purchase(_pending_txn, outcome, _pending_consumable, _pending_coins)
		if bool(bought.get("ok", false)):
			progress.coins += int(bought.get("coins", 0))
			_store_offers()
			var price := "9.99" if _pending_sku == "no_forced_ads" else str(ProgressScript.PACKS[_pending_sku]["usd"])
			analytics.track("iap_purchase", {
				"sku": _pending_sku,
				"price_usd": price,
				"currency": "USD",
				"simulated": true,
			}, "iap-" + _pending_txn)
			if _pending_sku == "no_forced_ads":
				analytics.track("no_ads_active", {"active": true})
			settings_note.text = "Simulated purchase completed once. Coins %d. Local test, not a checkout." % progress.coins
		else:
			settings_note.text = "No purchase: %s. Coins stayed %d." % [str(bought.get("reason", "")), progress.coins]
		if not bool(bought.get("ok", false)) and progress.coins != before_purchase:
			progress.coins = before_purchase
			progress.save_file()
		return
	if _reward_id < 0:
		settings_note.text = "Start a local test reward first."
		return
	var before: int = progress.coins
	var result: Dictionary = offers.resolve_rewarded(_reward_id, outcome, level_token)
	if not bool(result.get("granted", false)):
		settings_note.text = "No reward: %s." % str(result.get("reason", ""))
		return
	analytics.track("ad_reward_earned", {"placement": _pending_kind, "simulated": true}, "reward-%d" % _reward_id)
	if _pending_kind == "undo" and puzzle != null and not puzzle.history.is_empty() and puzzle.undo():
		analytics.track("assist_accepted", {"type": "undo", "source": "rewarded"})
		_after_undo("Simulated reward undo. Nothing was spent.")
		settings_note.text = "One undo granted. Coins stayed %d." % progress.coins
	elif _pending_kind == "temp" and puzzle != null:
		var granted: Dictionary = progress.grant_temp(int(puzzle.id), playing_daily)
		if bool(granted.get("ok", false)):
			puzzle.extra_slot = true
			puzzle.temp_slot_used = true
			analytics.track("assist_accepted", {"type": "slot", "source": "rewarded"})
			_refresh()
		settings_note.text = "Extra hold granted for this unfinished ship. Coins stayed %d." % progress.coins
	elif _pending_kind == "double" and not playing_daily and not _doubled and int(last_clear.get("coins", 0)) > 0:
		var bonus: int = int(last_clear.get("coins", 0))
		progress.coins += bonus
		_doubled = true
		analytics.track("assist_accepted", {"type": "double_coins", "source": "rewarded"})
		progress.save_file()
		settings_note.text = "Doubled once. +%d coins, matching the clear. Balance %d." % [bonus, progress.coins]
		if double_button != null:
			double_button.disabled = true
			double_button.text = "Doubled once"
	else:
		settings_note.text = "Completed once. No coins were added."
	if _pending_kind != "double" and _pending_kind != "undo" and progress.coins != before and _pending_kind != "temp":
		progress.coins = before
		progress.save_file()


func _double_clear() -> void:
	if playing_daily or _doubled or int(last_clear.get("coins", 0)) <= 0:
		return
	var begun: Dictionary = offers.begin_rewarded("double_coins", level_token)
	if not bool(begun.get("ok", false)):
		return
	progress.stamp_ad()
	analytics.track("ad_impression", {"format": "rewarded", "placement": "double_coins", "simulated": true})
	_pending_kind = "double"
	_reward_id = int(begun.get("id", -1))
	var outcomes := modal.find_child("ModalOutcomes", true, false)
	if outcomes != null:
		outcomes.visible = true
	modal_body.text += "\nSimulated double is waiting. The bonus matches this clear only."


func _toggle_event_log() -> void:
	if event_log == null:
		return
	event_log.visible = not event_log.visible
	event_log.text = analytics.recent_text(12)


func _refresh_settings() -> void:
	if sound_button == null:
		return
	sound_button.text = "Sound          %s" % ("On" if progress.sound_on else "Off")
	haptics_button.text = "Haptics       %s" % ("On" if progress.haptics_on else "Off")


func _leave_settings() -> void:
	if _settings_return == "ships":
		_show_ships()
	else:
		_show_hub()


func _refresh_hub() -> void:
	if hub_coins != null:
		hub_coins.text = "Coins %d" % progress.coins
	if upgrade_button != null:
		upgrade_button.add_theme_color_override("font_disabled_color", INK)
		if progress.second_hold:
			upgrade_button.text = "Second hold owned"
			upgrade_button.disabled = true
		elif not progress.upgrade_unlocked:
			upgrade_button.text = "Second hold\nAfter first clear of level 15"
			upgrade_button.disabled = true
		else:
			upgrade_button.text = "Buy second hold\n300 coins"
			upgrade_button.disabled = false
	if daily_button != null:
		daily_button.add_theme_color_override("font_disabled_color", INK)
		if not progress.daily_unlocked():
			daily_button.text = "Daily dock\nAfter clearing level 5"
			daily_button.disabled = true
		elif progress.daily_done_today():
			daily_button.text = "Daily dock · done today\nLevel %d · 00:00 UTC" % progress.daily_level_id()
			daily_button.disabled = false
		else:
			daily_button.text = "Daily dock · Level %d\n30 coins · 00:00 UTC" % progress.daily_level_id()
			daily_button.disabled = false


func _buy_hold() -> void:
	var before: int = progress.coins
	var result: Dictionary = progress.buy_second_hold()
	if not bool(result.get("ok", false)):
		if str(result.get("reason", "")) == "coins":
			hub_note.text = "Not enough coins. Nothing was spent. Days change at 00:00 UTC."
		elif str(result.get("reason", "")) == "owned":
			hub_note.text = "Second hold is already open."
		else:
			hub_note.text = "The second hold opens after the first clear of level 15."
		if progress.coins != before:
			hub_note.text = "Purchase did not change the save."
	else:
		hub_note.text = "Second hold open. It is permanent and does not change the star rule. Days change at 00:00 UTC."
	_refresh_hub()


func _start_daily() -> void:
	if not progress.daily_unlocked():
		return
	var wanted := progress.daily_level_id()
	var index := -1
	for i in levels.size():
		var data: Dictionary = levels[i]
		if int(data.get("id", 0)) == wanted:
			index = i
			break
	if index < 0:
		return
	_start_level(index, true)


func _paint_hold(button, color: String, slot: int) -> void:
	if button == null:
		return
	if color == "":
		button.clear_face(Color("f7f1e4"))
		button.tooltip_text = "Hold %d — empty" % (slot + 1)
	else:
		button.show_cargo(PALETTE[color], GLYPHS[color])
		button.tooltip_text = "Hold %d — %s" % [slot + 1, puzzle.pretty(color)]
	button.set_selected(sel_kind == "hold" and sel_index == slot)


func _placeholder_row(_which: String) -> void:
	settings_note.text = "Not in this build."


func _build_hub() -> void:
	hub_root = VBoxContainer.new()
	hub_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hub_root.add_theme_constant_override("separation", 12)
	screens.add_child(hub_root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := _label("SYDNEY", 28, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var settings_button := _action_button("Settings", Color("d7e4ea"), INK)
	settings_button.custom_minimum_size = Vector2(180, 72)
	settings_button.add_theme_font_size_override("font_size", 24)
	settings_button.pressed.connect(_show_settings)
	top.add_child(title)
	top.add_child(settings_button)
	hub_root.add_child(top)
	hub_coins = _label("Coins 0", 32, CREAM)
	hub_root.add_child(hub_coins)
	var yard := SydneyView.new()
	yard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	yard.custom_minimum_size = Vector2(0, 220)
	yard.clip_contents = true
	hub_root.add_child(yard)
	var play := _action_button("Play", GOLD, INK)
	play.custom_minimum_size = Vector2(0, 84)
	play.pressed.connect(_play_frontier)
	hub_root.add_child(play)
	var ships := _action_button("Ships", CREAM, INK)
	ships.custom_minimum_size = Vector2(0, 72)
	ships.pressed.connect(_show_ships)
	hub_root.add_child(ships)
	upgrade_button = _action_button("Second hold", CREAM, INK)
	upgrade_button.custom_minimum_size = Vector2(0, 72)
	upgrade_button.add_theme_font_size_override("font_size", 22)
	upgrade_button.pressed.connect(_buy_hold)
	hub_root.add_child(upgrade_button)
	daily_button = _action_button("Daily dock", Color("d7e4ea"), INK)
	daily_button.custom_minimum_size = Vector2(0, 72)
	daily_button.add_theme_font_size_override("font_size", 22)
	daily_button.pressed.connect(_start_daily)
	hub_root.add_child(daily_button)
	hub_note = _label("Days change at 00:00 UTC.", 20, CREAM)
	hub_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hub_root.add_child(hub_note)
	_refresh_hub()


func _build_home() -> void:
	home_root = VBoxContainer.new()
	home_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_root.add_theme_constant_override("separation", 14)
	screens.add_child(home_root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := _label("SHIPS", 22, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var port_button := _action_button("Port", GOLD, INK)
	port_button.custom_minimum_size = Vector2(140, 72)
	port_button.add_theme_font_size_override("font_size", 24)
	port_button.pressed.connect(_show_hub)
	var settings_button := _action_button("Settings", Color("d7e4ea"), INK)
	settings_button.custom_minimum_size = Vector2(180, 72)
	settings_button.add_theme_font_size_override("font_size", 24)
	settings_button.pressed.connect(_show_settings)
	top.add_child(title)
	top.add_child(port_button)
	top.add_child(settings_button)
	home_root.add_child(top)
	home_coins = _label("Coins 0", 36, CREAM)
	home_root.add_child(home_coins)
	home_root.add_child(_label("Ships", 28, CREAM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A short drag scrolls. A tap, below this distance, still opens the ship.
	scroll.scroll_deadzone = 20
	scroll.gui_input.connect(_on_ship_list_input)
	home_root.add_child(scroll)
	home_scroll = scroll
	home_list = VBoxContainer.new()
	home_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_list.add_theme_constant_override("separation", 12)
	scroll.add_child(home_list)


func _rebuild_level_list() -> void:
	if home_list == null:
		return
	home_coins.text = "Coins %d" % progress.coins
	_free_children(home_list)
	for i in levels.size():
		var data: Dictionary = levels[i]
		var button := _action_button("", CREAM, INK)
		button.custom_minimum_size = Vector2(0, 88)
		button.add_theme_font_size_override("font_size", 26)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var title := str(data.get("title", "Level"))
		# Rows ignore the pointer so a finger drag reaches the scroller.
		# Taps are handled in _on_ship_list_input.
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.set_meta("level_index", i)
		if not progress.is_unlocked(i):
			button.text = "%d   %s\nLocked" % [i + 1, title]
			button.disabled = true
			button.add_theme_color_override("font_disabled_color", INK)
			button.add_theme_stylebox_override("disabled", _box(Color("d5dee3"), Color("5c6b73"), 4, 22, 8))
		else:
			var stars := progress.best_for(int(data.get("id", i + 1)))
			var mark := "No stars yet" if stars == 0 else "%d stars" % stars
			button.text = "%d   %s\n%s" % [i + 1, title, mark]
		home_list.add_child(button)


func _on_ship_list_input(event: InputEvent) -> void:
	if home_scroll == null or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_list_press = mb.global_position
		_list_press_scroll = home_scroll.scroll_vertical
		return
	if _list_press.x < 0.0:
		return
	var moved := mb.global_position.distance_to(_list_press)
	var scrolled: int = absi(home_scroll.scroll_vertical - _list_press_scroll)
	_list_press = Vector2(-1, -1)
	if moved < 20.0 and scrolled < 8:
		_activate_ship_at(mb.global_position)


func _activate_ship_at(global_pos: Vector2) -> void:
	if home_list == null:
		return
	for child in home_list.get_children():
		var button := child as Button
		if button == null or not button.get_global_rect().has_point(global_pos):
			continue
		if not button.has_meta("level_index"):
			return
		var index := int(button.get_meta("level_index"))
		if progress.is_unlocked(index):
			_start_level(index)
		return


func _build_settings() -> void:
	settings_root = Control.new()
	settings_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_root.visible = false
	screens.add_child(settings_root)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_root.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 12)
	scroll.add_child(inner)
	inner.add_child(_label("Settings", 40, CREAM))
	var log_button := _action_button("Local event log", Color("d7e4ea"), INK)
	log_button.custom_minimum_size = Vector2(0, 64)
	log_button.add_theme_font_size_override("font_size", 20)
	log_button.pressed.connect(_toggle_event_log)
	inner.add_child(log_button)
	event_log = _label("", 16, CREAM)
	event_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_log.visible = false
	inner.add_child(event_log)
	var top_back := _action_button("Back", GOLD, INK)
	top_back.custom_minimum_size = Vector2(0, 72)
	top_back.pressed.connect(_leave_settings)
	inner.add_child(top_back)
	sound_button = _action_button("Sound", CREAM, INK)
	sound_button.custom_minimum_size = Vector2(0, 84)
	sound_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sound_button.pressed.connect(_toggle_sound)
	haptics_button = _action_button("Haptics", CREAM, INK)
	haptics_button.custom_minimum_size = Vector2(0, 84)
	haptics_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	haptics_button.pressed.connect(_toggle_haptics)
	inner.add_child(sound_button)
	inner.add_child(haptics_button)
	for row_name in ["Privacy", "Support"]:
		var row := _action_button("%s\nNot in this build" % row_name, Color("d7e4ea"), INK)
		row.custom_minimum_size = Vector2(0, 72)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 22)
		row.pressed.connect(_placeholder_row.bind(row_name))
		inner.add_child(row)
	inner.add_child(_label("Local test. Not a store.", 22, INK))
	var ads := _action_button("Simulated No forced ads\nUSD 9.99 / AUD 14.99", CREAM, INK)
	ads.custom_minimum_size = Vector2(0, 72)
	ads.add_theme_font_size_override("font_size", 22)
	ads.pressed.connect(_mark_no_forced_ads)
	inner.add_child(ads)
	var restore := _action_button("Restore local test entitlement", Color("d7e4ea"), INK)
	restore.custom_minimum_size = Vector2(0, 72)
	restore.add_theme_font_size_override("font_size", 22)
	restore.pressed.connect(_restore_test_entitlement)
	inner.add_child(restore)
	var reward := _action_button("Start local test reward", GOLD, INK)
	reward.custom_minimum_size = Vector2(0, 72)
	reward.add_theme_font_size_override("font_size", 22)
	reward.pressed.connect(_start_test_reward)
	inner.add_child(reward)
	var outcomes := VBoxContainer.new()
	outcomes.add_theme_constant_override("separation", 8)
	var outcome_names := ["completed", "cancelled", "failed", "unavailable"]
	for row_i in 2:
		var outcome_row := HBoxContainer.new()
		outcome_row.add_theme_constant_override("separation", 8)
		for col_i in 2:
			var outcome: String = outcome_names[row_i * 2 + col_i]
			var choice := _action_button(outcome.substr(0, 1).to_upper() + outcome.substr(1), Color("d7e4ea"), INK)
			choice.custom_minimum_size = Vector2(0, 64)
			choice.add_theme_font_size_override("font_size", 20)
			choice.pressed.connect(_finish_test_reward.bind(outcome))
			outcome_row.add_child(choice)
		outcomes.add_child(outcome_row)
	inner.add_child(outcomes)
	for sku in ["S", "M", "L"]:
		var pack: Dictionary = ProgressScript.PACKS[sku]
		var pack_button := _action_button("Simulated pack %s · %d coins\nUSD %s / AUD %s" % [sku, int(pack["coins"]), pack["usd"], pack["aud"]], Color("d7e4ea"), INK)
		pack_button.custom_minimum_size = Vector2(0, 72)
		pack_button.add_theme_font_size_override("font_size", 18)
		pack_button.pressed.connect(_arm_pack.bind(sku))
		inner.add_child(pack_button)
	var cadence_note := _label("Simulated interstitial: every 3rd main clear after level 10, only if 90 seconds have passed since a simulated ad. Not a real ad.", 20, INK)
	cadence_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(cadence_note)
	settings_note = _label("", 22, GOLD)
	settings_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(settings_note)
	var back := _action_button("Back", GOLD, INK)
	back.custom_minimum_size = Vector2(0, 84)
	back.pressed.connect(_leave_settings)
	inner.add_child(back)
	_refresh_settings()


func _build_coach(parent: VBoxContainer) -> void:
	coach = PanelContainer.new()
	coach.visible = false
	coach.add_theme_stylebox_override("panel", _box(Color("fff4cc"), INK, 4, 16, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	coach_label = _label("", 22, INK)
	coach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skip := _action_button("Skip", Color("d7e4ea"), INK)
	skip.custom_minimum_size = Vector2(120, 64)
	skip.add_theme_font_size_override("font_size", 22)
	skip.pressed.connect(_finish_coach)
	row.add_child(coach_label)
	row.add_child(skip)
	coach.add_child(row)
	parent.add_child(coach)


func _coach_lines_for(level_id: int) -> PackedStringArray:
	match level_id:
		1:
			return PackedStringArray(["Tap the bright top container.", "Now tap its matching stack."])
		2:
			return PackedStringArray(["Tap a container, then tap its stack."])
		3:
			return PackedStringArray(["Select a container, then tap Hold to park it."])
		4:
			return PackedStringArray(["Undo puts the last move back."])
	return PackedStringArray()


func _begin_coach() -> void:
	if coach == null or puzzle == null:
		return
	if progress.seen_ftue(int(puzzle.id)):
		coach.visible = false
		return
	coach_lines = _coach_lines_for(int(puzzle.id))
	coach_step = 0
	if coach_lines.is_empty():
		coach.visible = false
		return
	coach_label.text = coach_lines[0]
	coach.visible = true


func _note_coach(action: String) -> void:
	if coach == null or not coach.visible or puzzle == null:
		return
	var want := ""
	match int(puzzle.id):
		1:
			want = "select" if coach_step == 0 else "stack"
		2:
			want = "stack"
		3:
			want = "hold"
		4:
			want = "undo"
	if action == want:
		_advance_coach()


func _advance_coach() -> void:
	var step_name := coach_lines[coach_step] if coach_step < coach_lines.size() else "coach"
	analytics.track("ftue_step", {"step_name": step_name, "success": true})
	coach_step += 1
	if coach_step >= coach_lines.size():
		_finish_coach()
	else:
		coach_label.text = coach_lines[coach_step]


func _finish_coach() -> void:
	if coach == null or puzzle == null:
		return
	coach.visible = false
	analytics.track("ftue_step", {"step_name": "skip_or_done", "success": true}, "ftue-done-%d" % int(puzzle.id))
	if not progress.seen_ftue(int(puzzle.id)):
		progress.mark_ftue(int(puzzle.id))
		progress.save_file()


func _modal_blocking() -> bool:
	return modal != null and modal.visible


func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


func _refresh() -> void:
	if puzzle == null:
		return
	moves_label.text = "Undos %d" % puzzle.undos_used
	for c in puzzle.columns.size():
		var stack: Array = puzzle.columns[c]
		var rows: int = column_cells[c].size()
		var empties := rows - stack.size()
		for r in rows:
			var cell = column_cells[c][r]
			if r < empties:
				cell.clear_face(Color(0.45, 0.32, 0.16, 0.28))
				cell.set_selected(false)
				cell.modulate = Color.WHITE
				cell.tooltip_text = "Empty cell"
			else:
				var token_name := str(stack[r - empties])
				var color_name := token_name
				if PuzzleScript.is_key(token_name):
					cell.show_cargo(Color("f2d48a"), "key")
					color_name = "key"
				elif PuzzleScript.is_locked(token_name):
					color_name = PuzzleScript.cargo_color(token_name)
					cell.show_cargo(PALETTE[color_name], GLYPHS[color_name], true)
				else:
					cell.show_cargo(PALETTE[color_name], GLYPHS[color_name])
				var is_top := r == empties
				# Buried cargo keeps the same fill. A grey multiply made teal look like another colour.
				cell.modulate = Color.WHITE
				cell.set_selected(is_top and sel_kind == "column" and sel_index == c)
				var mark := ""
				if puzzle.is_double_column(c) and not PuzzleScript.is_key(token_name):
					mark = "TOP" if is_top else "UNDER"
				cell.set_order_mark(mark)
				cell.tooltip_text = puzzle.pretty(color_name)
	for b in puzzle.berths.size():
		var berth = berth_buttons[b]
		berth.set_state(str(puzzle.locks[b]), puzzle.berths[b], puzzle.capacity, PALETTE, GLYPHS)
		berth.set_selected(false)
	_paint_hold(hold_button, puzzle.hold, 0)
	if hold_button2 != null:
		hold_button2.visible = puzzle.permanent_slots >= 2
		if puzzle.permanent_slots >= 2:
			_paint_hold(hold_button2, puzzle.hold2, 1)
	if hold_button3 != null:
		hold_button3.visible = puzzle.extra_slot
		if puzzle.extra_slot:
			_paint_hold(hold_button3, puzzle.hold3, 2)


func _rebuild_board() -> void:
	_free_children(deck_row)
	_free_children(stack_row)
	column_cells.clear()
	berth_buttons.clear()
	deck_height = 0
	for col in puzzle.columns:
		deck_height = max(deck_height, (col as Array).size())
	for c in puzzle.columns.size():
		var col_box := VBoxContainer.new()
		col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_box.add_theme_constant_override("separation", 8)
		var double_col: bool = puzzle.is_double_column(c)
		var caption_text := "Top, then bottom" if double_col else "Col %d" % (c + 1)
		var caption := _label(caption_text, 22, CREAM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_box.add_child(caption)
		var cells: Array = []
		var row_count := 2 if double_col else deck_height
		for r in row_count:
			var cell: Button = Glyph.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cell.custom_minimum_size = Vector2(108, 108)
			cell.pressed.connect(_on_cell.bind(c, r))
			col_box.add_child(cell)
			cells.append(cell)
		deck_row.add_child(col_box)
		column_cells.append(cells)
	for b in puzzle.berths.size():
		var wrap := VBoxContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_theme_constant_override("separation", 6)
		var berth: Button = Berth.new()
		berth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		berth.custom_minimum_size = Vector2(120, 228)
		berth.pressed.connect(_on_berth.bind(b))
		var name := "Stack %d" % (b + 1)
		if str(puzzle.locks[b]) != "":
			name = puzzle.pretty(str(puzzle.locks[b]))
		var caption := _label(name, 22, CREAM)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wrap.add_child(berth)
		wrap.add_child(caption)
		stack_row.add_child(wrap)
		berth_buttons.append(berth)
	_refresh()


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = HARBOUR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	screens = Control.new()
	screens.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screens.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(screens)

	play_root = VBoxContainer.new()
	play_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_root.add_theme_constant_override("separation", 12)
	screens.add_child(play_root)
	var root_box: VBoxContainer = play_root

	var kicker_row := HBoxContainer.new()
	kicker_row.add_theme_constant_override("separation", 12)
	var kicker := _label("DOCKSIDE SORT", 18, GOLD)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var levels_button := _action_button("Port", Color("d7e4ea"), INK)
	levels_button.custom_minimum_size = Vector2(140, 64)
	levels_button.add_theme_font_size_override("font_size", 22)
	levels_button.pressed.connect(_show_hub)
	kicker_row.add_child(kicker)
	kicker_row.add_child(levels_button)
	root_box.add_child(kicker_row)

	var info := HBoxContainer.new()
	level_label = _label("Level", 26, CREAM)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_label = _label("Moves 0", 26, GOLD)
	moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(level_label)
	info.add_child(moves_label)
	root_box.add_child(info)

	title_label = _label("Morning Shift", 40, CREAM)
	root_box.add_child(title_label)
	blurb_label = _label("", 22, Color("f6efe2cc"))
	blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(blurb_label)
	_build_coach(root_box)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _box(CREAM, INK, 0, 14, 12))
	status_label = _label("", 22, INK)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(status_label)
	root_box.add_child(status_panel)
	var offer_row := HBoxContainer.new()
	offer_row.add_theme_constant_override("separation", 8)
	var reward_undo := _action_button("Reward undo", Color("d7e4ea"), INK)
	reward_undo.custom_minimum_size = Vector2(0, 64)
	reward_undo.add_theme_font_size_override("font_size", 18)
	reward_undo.pressed.connect(_arm_reward_undo)
	var buy_temp := _action_button("Extra hold 100", GOLD, INK)
	buy_temp.custom_minimum_size = Vector2(0, 64)
	buy_temp.add_theme_font_size_override("font_size", 18)
	buy_temp.pressed.connect(_buy_temp)
	var reward_temp := _action_button("Reward hold", Color("d7e4ea"), INK)
	reward_temp.custom_minimum_size = Vector2(0, 64)
	reward_temp.add_theme_font_size_override("font_size", 18)
	reward_temp.pressed.connect(_arm_reward_temp)
	offer_row.add_child(reward_undo)
	offer_row.add_child(buy_temp)
	offer_row.add_child(reward_temp)
	root_box.add_child(offer_row)

	var deck_panel := PanelContainer.new()
	deck_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_panel.add_theme_stylebox_override("panel", _box(DECK, Color("6e5230"), 4, 22, 14))
	deck_row = HBoxContainer.new()
	deck_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_row.add_theme_constant_override("separation", 14)
	deck_panel.add_child(deck_row)
	root_box.add_child(deck_panel)

	var stack_panel := PanelContainer.new()
	stack_panel.add_theme_stylebox_override("panel", _box(DOCK, Color("10181c"), 4, 22, 12))
	stack_row = HBoxContainer.new()
	stack_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_row.add_theme_constant_override("separation", 14)
	stack_panel.add_child(stack_row)
	root_box.add_child(stack_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	root_box.add_child(bottom)

	var hold_wrap := VBoxContainer.new()
	hold_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_wrap.add_theme_constant_override("separation", 4)
	var hold_caption := _label("HOLD", 20, GOLD)
	hold_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hold_row := HBoxContainer.new()
	hold_row.add_theme_constant_override("separation", 8)
	hold_button = Glyph.new()
	hold_button.custom_minimum_size = Vector2(120, 120)
	hold_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_button.pressed.connect(_on_hold.bind(0))
	hold_button2 = Glyph.new()
	hold_button2.custom_minimum_size = Vector2(120, 120)
	hold_button2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_button2.visible = false
	hold_button2.pressed.connect(_on_hold.bind(1))
	hold_button3 = Glyph.new()
	hold_button3.custom_minimum_size = Vector2(96, 96)
	hold_button3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold_button3.visible = false
	hold_button3.pressed.connect(_on_hold.bind(2))
	hold_row.add_child(hold_button)
	hold_row.add_child(hold_button2)
	hold_row.add_child(hold_button3)
	hold_wrap.add_child(hold_caption)
	hold_wrap.add_child(hold_row)
	bottom.add_child(hold_wrap)

	bottom.add_child(_bottom_action("Undo", GOLD, INK, _undo))
	bottom.add_child(_bottom_action("Restart", Color("d7e4ea"), INK, _restart))

	_build_hub()
	_build_home()
	_build_settings()
	_build_modal()
	_build_interstitial()


func _build_interstitial() -> void:
	interstitial = Control.new()
	interstitial.visible = false
	interstitial.mouse_filter = Control.MOUSE_FILTER_STOP
	interstitial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(interstitial)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.09, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interstitial.add_child(dim)
	var label := _label("Simulated interstitial. Local test, not an ad network. It appears before the results, and it is not shown again on this screen.", 28, CREAM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 36
	label.offset_top = 280
	label.offset_right = -36
	label.offset_bottom = -360
	interstitial.add_child(label)
	var dismiss := _action_button("Continue", GOLD, INK)
	dismiss.custom_minimum_size = Vector2(0, 84)
	dismiss.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dismiss.offset_top = -220
	dismiss.offset_bottom = -120
	dismiss.offset_left = -180
	dismiss.offset_right = 180
	dismiss.pressed.connect(_dismiss_interstitial)
	interstitial.add_child(dismiss)


func _show_interstitial() -> void:
	if interstitial != null:
		interstitial.visible = true


func _dismiss_interstitial() -> void:
	if interstitial != null:
		interstitial.visible = false
	_show_modal("win")


func _build_modal() -> void:
	modal = Control.new()
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.07, 0.09, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _box(CREAM, INK, 6, 28, 28))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	modal_title = _label("", 40, INK)
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_row = HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 12)
	for _i in 3:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(36, 36)
		star_row.add_child(pip)
	modal_body = _label("", 24, INK)
	modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_body.custom_minimum_size = Vector2(460, 0)
	box.add_child(modal_title)
	box.add_child(star_row)
	box.add_child(modal_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	primary_button = _action_button("Next level", GOLD, INK)
	primary_button.custom_minimum_size = Vector2(210, 96)
	primary_button.pressed.connect(_on_primary)
	secondary_button = _action_button("Restart", Color("d7e4ea"), INK)
	secondary_button.custom_minimum_size = Vector2(210, 96)
	secondary_button.pressed.connect(_on_secondary)
	row.add_child(primary_button)
	row.add_child(secondary_button)
	box.add_child(row)
	double_button = _action_button("Double this clear\nLocal test", GOLD, INK)
	double_button.custom_minimum_size = Vector2(460, 72)
	double_button.add_theme_font_size_override("font_size", 22)
	double_button.visible = false
	double_button.pressed.connect(_double_clear)
	box.add_child(double_button)
	var modal_outcomes := HBoxContainer.new()
	modal_outcomes.name = "ModalOutcomes"
	modal_outcomes.visible = false
	modal_outcomes.add_theme_constant_override("separation", 8)
	for outcome_name in ["completed", "cancelled", "failed", "unavailable"]:
		var modal_choice := _action_button(outcome_name.substr(0, 1).to_upper() + outcome_name.substr(1, 4), Color("d7e4ea"), INK)
		modal_choice.custom_minimum_size = Vector2(0, 56)
		modal_choice.add_theme_font_size_override("font_size", 16)
		modal_choice.pressed.connect(_finish_test_reward.bind(outcome_name))
		modal_outcomes.add_child(modal_choice)
	box.add_child(modal_outcomes)
	list_button = _action_button("Port", Color("d7e4ea"), INK)
	list_button.custom_minimum_size = Vector2(460, 72)
	list_button.add_theme_font_size_override("font_size", 24)
	list_button.pressed.connect(_show_hub)
	box.add_child(list_button)


func _bottom_action(text: String, fill: Color, ink: Color, handler: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	var spacer := _label(" ", 20, HARBOUR)
	spacer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button := _action_button(text, fill, ink)
	button.pressed.connect(handler)
	wrap.add_child(spacer)
	wrap.add_child(button)
	return wrap


func _action_button(text: String, fill: Color, ink: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 132)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	var normal := _box(fill, INK, 6, 22, 8)
	var pressed := _box(fill.darkened(0.08), INK, 6, 22, 8)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", normal)
	return button


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _box(fill: Color, border: Color, width: int, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _apply_safe_margins() -> void:
	if margin == null:
		return
	var inset := _safe_insets()
	margin.add_theme_constant_override("margin_left", int(maxf(inset.x, 20.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(inset.y, 36.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(inset.z, 20.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(inset.w, 28.0)))


func _safe_insets() -> Vector4:
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0 or size.x <= 0.0 or size.y <= 0.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var left := float(safe.position.x)
	var top := float(safe.position.y)
	var right := float(maxi(0, screen.x - safe.position.x - safe.size.x))
	var bottom := float(maxi(0, screen.y - safe.position.y - safe.size.y))
	return Vector4(left * size.x / float(screen.x), top * size.y / float(screen.y), right * size.x / float(screen.x), bottom * size.y / float(screen.y))


func _free_children(node: Node) -> void:
	while node.get_child_count() > 0:
		var child := node.get_child(0)
		node.remove_child(child)
		child.free()
